///|
/// Ephemeral positioned view over a `CstToken`.
/// Mirrors `SyntaxNode` but for leaf tokens.
pub struct SyntaxToken {
  cst : CstToken
  offset : Int
} derive(Debug)

///|
pub fn SyntaxToken::new(cst : CstToken, offset : Int) -> SyntaxToken {
  { cst, offset }
}

///|
pub fn SyntaxToken::start(self : SyntaxToken) -> Int {
  self.offset
}

///|
pub fn SyntaxToken::end(self : SyntaxToken) -> Int {
  self.offset + self.cst.text_len()
}

///|
pub fn SyntaxToken::kind(self : SyntaxToken) -> RawKind {
  self.cst.kind
}

///|
pub fn SyntaxToken::text(self : SyntaxToken) -> String {
  self.cst.text
}

///|
/// Show: compact form — "SyntaxToken@[start,end)"
pub impl Show for SyntaxToken with output(self, logger) {
  logger.write_string("SyntaxToken@[")
  logger.write_string(self.start().to_string())
  logger.write_string(",")
  logger.write_string(self.end().to_string())
  logger.write_string(")")
}

///|
/// A child element — either an interior node or a leaf token, both positioned.
pub(all) enum SyntaxElement {
  Node(SyntaxNode)
  Token(SyntaxToken)
} derive(Show, Debug)

///|
pub fn SyntaxElement::start(self : SyntaxElement) -> Int {
  match self {
    Node(n) => n.start()
    Token(t) => t.start()
  }
}

///|
pub fn SyntaxElement::end(self : SyntaxElement) -> Int {
  match self {
    Node(n) => n.end()
    Token(t) => t.end()
  }
}

///|
/// Ephemeral positioned view over a `CstNode`.
///
/// A `SyntaxNode` pairs an immutable `CstNode` with the absolute byte
/// `offset` of its start in the source. Unlike `CstNode`, `SyntaxNode`
/// values are created on demand and are not cached or shared.
///
/// **Invariant:** `offset + cst.text_len` is the exclusive end byte.
pub struct SyntaxNode {
  priv cst : CstNode
  priv parent : SyntaxNode?
  priv offset : Int
} derive(Debug(ignore=[SyntaxNode]))

///|
/// Full constructor. `parent` is `None` for root nodes.
/// Prefer `SyntaxNode::from_cst` for root construction.
pub fn SyntaxNode::new(
  cst : CstNode,
  parent : SyntaxNode?,
  offset : Int,
) -> SyntaxNode {
  { cst, parent, offset }
}

///|
/// Create a root SyntaxNode from a CstNode (offset = 0, no parent).
pub fn SyntaxNode::from_cst(cst : CstNode) -> SyntaxNode {
  SyntaxNode::new(cst, None, 0)
}

///|
/// The parent node, or None when this is the root.
pub fn SyntaxNode::parent(self : SyntaxNode) -> SyntaxNode? {
  self.parent
}

///|
/// First interior-node child, or None if this is a leaf or has only token children.
/// Thin wrapper over nth_child(0).
pub fn SyntaxNode::first_child(self : SyntaxNode) -> SyntaxNode? {
  self.nth_child(0)
}

///|
/// First token anywhere in this subtree (depth-first, left-to-right).
/// Returns None when the subtree contains no tokens.
pub fn SyntaxNode::first_token(self : SyntaxNode) -> SyntaxToken? {
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => return Some(SyntaxToken::new(tok, offset))
      CstElement::Node(child_cst) =>
        match SyntaxNode::new(child_cst, None, offset).first_token() {
          Some(_) as found => return found
          None => offset = offset + child_cst.text_len
        }
    }
  }
  None
}

///|
/// Absolute byte offset of this node's start in the source.
pub fn SyntaxNode::start(self : SyntaxNode) -> Int {
  self.offset
}

///|
/// Exclusive byte offset of this node's end in the source (`start + text_len`).
pub fn SyntaxNode::end(self : SyntaxNode) -> Int {
  self.offset + self.cst.text_len
}

///|
/// The language-agnostic kind of the underlying `CstNode`.
pub fn SyntaxNode::kind(self : SyntaxNode) -> RawKind {
  self.cst.kind
}

///|
/// Show: compact form — "SyntaxNode@[start,end)"
pub impl Show for SyntaxNode with output(self, logger) {
  logger.write_string("SyntaxNode@[")
  logger.write_string(self.start().to_string())
  logger.write_string(",")
  logger.write_string(self.end().to_string())
  logger.write_string(")")
}

///|
/// Child `SyntaxNode`s with computed absolute offsets. Leaf tokens are skipped;
/// only interior `CstNode` children are returned.
pub fn SyntaxNode::children(self : SyntaxNode) -> Array[SyntaxNode] {
  let result : Array[SyntaxNode] = []
  for offset = self.offset, i = 0; i < self.cst.children.length(); {
    match self.cst.children[i] {
      Node(cst_child) => {
        result.push(SyntaxNode::new(cst_child, Some(self), offset))
        continue offset + cst_child.text_len, i + 1
      }
      Token(token) => continue offset + token.text_len(), i + 1
    }
  }
  result
}

///|
/// All direct children as `SyntaxElement`s, preserving token order.
pub fn SyntaxNode::all_children(self : SyntaxNode) -> Array[SyntaxElement] {
  let result : Array[SyntaxElement] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Node(child_cst) => {
        result.push(
          SyntaxElement::Node(SyntaxNode::new(child_cst, Some(self), offset)),
        )
        offset = offset + child_cst.text_len
      }
      CstElement::Token(tok) => {
        result.push(SyntaxElement::Token(SyntaxToken::new(tok, offset)))
        offset = offset + tok.text_len()
      }
    }
  }
  result
}

///|
/// Direct leaf tokens only (child nodes are skipped).
pub fn SyntaxNode::tokens(self : SyntaxNode) -> Array[SyntaxToken] {
  let result : Array[SyntaxToken] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        result.push(SyntaxToken::new(tok, offset))
        offset = offset + tok.text_len()
      }
      CstElement::Node(child) => offset = offset + child.text_len
    }
  }
  result
}

///|
/// First direct token child matching `kind`, with its absolute offset.
pub fn SyntaxNode::find_token(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxToken? {
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        if tok.kind == kind {
          return Some(SyntaxToken::new(tok, offset))
        }
        offset = offset + tok.text_len()
      }
      CstElement::Node(child) => offset = offset + child.text_len
    }
  }
  None
}

///|
/// All direct token children matching `kind`, in source order.
pub fn SyntaxNode::tokens_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> Array[SyntaxToken] {
  let result : Array[SyntaxToken] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        if tok.kind == kind {
          result.push(SyntaxToken::new(tok, offset))
        }
        offset = offset + tok.text_len()
      }
      CstElement::Node(child) => offset = offset + child.text_len
    }
  }
  result
}

///|
/// Tight byte span of this node, skipping leading and trailing trivia tokens.
///
/// Pass `trivia_kind` to identify whitespace/comment tokens to skip.
/// Interior `CstNode` children are never treated as trivia.
pub fn SyntaxNode::tight_span(
  self : SyntaxNode,
  trivia_kind? : RawKind? = None,
) -> (Int, Int) {
  let mut pos = self.offset
  let mut tight_start = self.offset
  let mut tight_end = self.offset
  let mut found_start = false
  for elem in self.cst.children {
    let len = match elem {
      CstElement::Token(t) => t.text_len()
      CstElement::Node(n) => n.text_len
    }
    let contributes = match (elem, trivia_kind) {
      (CstElement::Token(t), Some(tk)) => t.kind != tk
      (CstElement::Token(_), None) => true
      (CstElement::Node(_), _) => true
    }
    if contributes {
      if not(found_start) {
        tight_start = pos
        found_start = true
      }
      tight_end = pos + len
    }
    pos = pos + len
  }
  if not(found_start) {
    return (self.offset, self.offset)
  }
  (tight_start, tight_end)
}

///|
/// Returns the underlying `CstNode`.
///
/// **Advanced use only.** Use this when you need to pass the raw
/// `CstNode` to infrastructure that requires it (e.g. reuse cursors).
/// Prefer the SyntaxNode API for all navigation and position queries.
pub fn SyntaxNode::cst_node(self : SyntaxNode) -> CstNode {
  self.cst
}

///|
/// Structure-only equality: two SyntaxNodes are equal iff their underlying
/// CstNodes are equal. Offset and parent are intentionally excluded so that
/// Memo[SyntaxNode] correctly skips recomputation when only positions shift
/// (e.g. after inserting a leading space) but the tree structure is unchanged.
pub impl Eq for SyntaxNode with equal(self, other : SyntaxNode) -> Bool {
  self.cst == other.cst
}

///|
/// Generic JSON serialization of a SyntaxNode.
/// Produces: { "kind": <raw int>, "start": <int>, "end": <int>, "children": [...] }
/// Tokens appear as: { "kind": <raw int>, "text": <string>, "start": <int>, "end": <int> }
/// For typed semantic JSON, use the view types in your language package instead.
pub impl ToJson for SyntaxNode with to_json(self) -> Json {
  let RawKind(k) = self.cst.kind
  let children_json : Array[Json] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        let RawKind(tk) = tok.kind
        children_json.push({
          "kind": (tk : Int),
          "text": tok.text,
          "start": (offset : Int),
          "end": offset + tok.text_len(),
        })
        offset = offset + tok.text_len()
      }
      CstElement::Node(child_cst) => {
        let child_syn = SyntaxNode::new(child_cst, Some(self), offset)
        children_json.push(child_syn.to_json())
        offset = offset + child_cst.text_len
      }
    }
  }
  {
    "kind": (k : Int),
    "start": (self.offset : Int),
    "end": (self.end() : Int),
    "children": children_json,
  }
}

///|
/// Return the nth interior-node child (0-indexed, skipping token children).
/// Returns None if there are fewer than n+1 interior children.
pub fn SyntaxNode::nth_child(self : SyntaxNode, n : Int) -> SyntaxNode? {
  let mut count = 0
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Node(child_cst) => {
        if count == n {
          return Some(SyntaxNode::new(child_cst, Some(self), offset))
        }
        count = count + 1
        offset = offset + child_cst.text_len
      }
      CstElement::Token(tok) => offset = offset + tok.text_len()
    }
  }
  None
}

///|
/// First interior-node child whose kind matches `kind`, or None.
pub fn SyntaxNode::child_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxNode? {
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Node(child_cst) => {
        if child_cst.kind == kind {
          return Some(SyntaxNode::new(child_cst, Some(self), offset))
        }
        offset = offset + child_cst.text_len
      }
      CstElement::Token(tok) => offset = offset + tok.text_len()
    }
  }
  None
}

///|
/// Deepest descendant node whose span contains `offset`.
///
/// Drills into the first child whose `[start, end)` covers `offset`,
/// recursing until no deeper child matches. Returns `self` when:
/// - no child's span covers `offset` (including empty nodes where `start == end`)
/// - `offset` is outside this node's span entirely
///
/// **Out-of-range input:** if `offset < self.start()` or `offset >= self.end()`,
/// the function returns `self` without recursing. Callers querying a
/// well-formed tree should ensure the offset is within the root's span;
/// out-of-range offsets will silently produce the root rather than a deep node.
pub fn SyntaxNode::find_at(self : SyntaxNode, offset : Int) -> SyntaxNode {
  let mut pos = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Node(child_cst) => {
        let child_end = pos + child_cst.text_len
        if pos <= offset && offset < child_end {
          let child = SyntaxNode::new(child_cst, Some(self), pos)
          return child.find_at(offset)
        }
        pos = child_end
      }
      CstElement::Token(tok) => pos = pos + tok.text_len()
    }
  }
  self
}

///|
/// Checked variant of find_at.
/// Returns None when offset is outside this node's [start, end) span.
/// Returns Some(node) for any in-span offset.
///
/// Use this when "nothing here" is a meaningful outcome. Prefer find_at
/// when you want a conservative fallback for IDE traversal.
pub fn SyntaxNode::find_at_checked(
  self : SyntaxNode,
  offset : Int,
) -> SyntaxNode? {
  if offset < self.start() || offset >= self.end() {
    None
  } else {
    Some(self.find_at(offset))
  }
}

///|
/// True when this node's kind equals error_kind.
/// Does not traverse children — use contains_errors for subtree checking.
pub fn SyntaxNode::is_error(self : SyntaxNode, error_kind : RawKind) -> Bool {
  self.kind() == error_kind
}

///|
/// True when the subtree rooted at this node contains any error node
/// (kind == error_node_kind) or any error token (kind == error_token_kind).
/// Delegates to CstNode::has_errors.
pub fn SyntaxNode::contains_errors(
  self : SyntaxNode,
  error_node_kind : RawKind,
  error_token_kind : RawKind,
) -> Bool {
  self.cst.has_errors(error_node_kind, error_token_kind)
}
