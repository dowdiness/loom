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
/// Result of a position query on a syntax tree.
///
/// - `None`: no tokens cover the offset (empty tree or out-of-range offset).
/// - `Single`: offset falls inside one token's span, or exactly matches a
///   zero-width token (`start == end == offset`).
/// - `Between`: offset sits exactly on the boundary between two adjacent tokens
///   (`left.end() == offset == right.start()`). The IDE caller should prefer
///   the right token for most completion/hover uses.
pub enum TokenAtOffset {
  None
  Single(SyntaxToken)
  Between(SyntaxToken, SyntaxToken)
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
/// Internal use only — callers outside seam use `from_cst`.
fn SyntaxNode::new(
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
/// Create a root SyntaxNode from a CstNode at a given byte offset, no parent.
/// Use when the CstNode originates from a sub-range of a larger source
/// (e.g. embedding a partial parse result at a known position).
/// Prefer `from_cst` when the node starts at position 0.
pub fn SyntaxNode::from_cst_at(cst : CstNode, offset : Int) -> SyntaxNode {
  SyntaxNode::new(cst, None, offset)
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
  self.children_from(0)
}

///|
/// Walk children flattening RepeatGroup nodes transparently.
/// Calls `on_node(cst_node, parent, offset)` for each non-RepeatGroup node child.
/// Calls `on_token(cst_token, offset)` for each token child.
/// Returns the final offset after traversing all children.
fn walk_children_flat(
  children : Array[CstElement],
  parent : SyntaxNode,
  offset : Int,
  on_node : (CstNode, SyntaxNode, Int) -> Unit,
  on_token : (CstToken, Int) -> Unit,
) -> Int {
  let mut pos = offset
  for elem in children {
    match elem {
      CstElement::Node(child) =>
        if child.kind == repeat_group_kind {
          pos = walk_children_flat(
            child.children,
            parent,
            pos,
            on_node,
            on_token,
          )
        } else {
          on_node(child, parent, pos)
          pos = pos + child.text_len
        }
      CstElement::Token(tok) => {
        on_token(tok, pos)
        pos = pos + tok.text_len()
      }
    }
  }
  pos
}

///|
/// Interior-node children starting from index `start` (0-indexed, tokens skipped).
/// Like `children()` but skips the first `start` node children without
/// allocating SyntaxNodes for them. Negative `start` is treated as 0.
pub fn SyntaxNode::children_from(
  self : SyntaxNode,
  start : Int,
) -> Array[SyntaxNode] {
  let result : Array[SyntaxNode] = []
  let count : Ref[Int] = Ref::new(0)
  walk_children_flat(
    self.cst.children,
    self,
    self.offset,
    fn(child, parent, pos) {
      if count.val >= start {
        result.push(SyntaxNode::new(child, Some(parent), pos))
      }
      count.val = count.val + 1
    },
    fn(_tok, _pos) {  },
  )
  |> ignore
  result
}

///|
/// All direct children as `SyntaxElement`s, preserving token order.
pub fn SyntaxNode::all_children(self : SyntaxNode) -> Array[SyntaxElement] {
  let result : Array[SyntaxElement] = []
  walk_children_flat(
    self.cst.children,
    self,
    self.offset,
    fn(child, parent, pos) {
      result.push(
        SyntaxElement::Node(SyntaxNode::new(child, Some(parent), pos)),
      )
    },
    fn(tok, pos) {
      result.push(SyntaxElement::Token(SyntaxToken::new(tok, pos)))
    },
  )
  |> ignore
  result
}

///|
/// Partition direct children into interior nodes and leaf tokens.
/// When `trivia_kind` is provided, tokens of that kind are excluded.
/// Both arrays preserve source order. Useful for infix expressions
/// where nodes are operands and tokens are operators.
pub fn SyntaxNode::nodes_and_tokens(
  self : SyntaxNode,
  trivia_kind? : RawKind? = None,
) -> (Array[SyntaxNode], Array[SyntaxToken]) {
  let nodes : Array[SyntaxNode] = []
  let tokens : Array[SyntaxToken] = []
  walk_children_flat(
    self.cst.children,
    self,
    self.offset,
    fn(child, parent, pos) {
      nodes.push(SyntaxNode::new(child, Some(parent), pos))
    },
    fn(tok, pos) {
      let keep = match trivia_kind {
        Some(tk) => tok.kind != tk
        None => true
      }
      if keep {
        tokens.push(SyntaxToken::new(tok, pos))
      }
    },
  )
  |> ignore
  (nodes, tokens)
}

///|
/// Direct leaf tokens only (child nodes are skipped).
pub fn SyntaxNode::tokens(self : SyntaxNode) -> Array[SyntaxToken] {
  let result : Array[SyntaxToken] = []
  walk_children_flat(
    self.cst.children,
    self,
    self.offset,
    fn(_child, _parent, _pos) {  },
    fn(tok, pos) { result.push(SyntaxToken::new(tok, pos)) },
  )
  |> ignore
  result
}

///|
/// First direct token child matching `kind`, with its absolute offset.
pub fn SyntaxNode::find_token(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxToken? {
  let result : SyntaxToken? = None
  fn search(children : Array[CstElement], off : Int) -> (SyntaxToken?, Int) {
    let mut pos = off
    for elem in children {
      match elem {
        CstElement::Token(tok) => {
          if tok.kind == kind {
            return (Some(SyntaxToken::new(tok, pos)), pos)
          }
          pos = pos + tok.text_len()
        }
        CstElement::Node(child) =>
          if child.kind == repeat_group_kind {
            let (found, new_pos) = search(child.children, pos)
            if found is Some(_) {
              return (found, new_pos)
            }
            pos = new_pos
          } else {
            pos = pos + child.text_len
          }
      }
    }
    (result, pos)
  }
  let (found, _) = search(self.cst.children, self.offset)
  found
}

///|
/// Text of the first direct token child matching `kind`, or "" if not found.
/// Shorthand for `find_token(kind).map(fn(t) { t.text() }).unwrap_or("")`.
pub fn SyntaxNode::token_text(self : SyntaxNode, kind : RawKind) -> String {
  match self.find_token(kind) {
    Some(t) => t.text()
    None => ""
  }
}

///|
/// All direct token children matching `kind`, in source order.
pub fn SyntaxNode::tokens_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> Array[SyntaxToken] {
  let result : Array[SyntaxToken] = []
  walk_children_flat(
    self.cst.children,
    self,
    self.offset,
    fn(_child, _parent, _pos) {  },
    fn(tok, pos) {
      if tok.kind == kind {
        result.push(SyntaxToken::new(tok, pos))
      }
    },
  )
  |> ignore
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
  let tight_start : Ref[Int] = Ref::new(self.offset)
  let tight_end : Ref[Int] = Ref::new(self.offset)
  let found_start : Ref[Bool] = Ref::new(false)
  fn scan(children : Array[CstElement], off : Int) -> Int {
    let mut pos = off
    for elem in children {
      match elem {
        CstElement::Node(n) =>
          if n.kind == repeat_group_kind {
            pos = scan(n.children, pos)
          } else {
            if not(found_start.val) {
              tight_start.val = pos
              found_start.val = true
            }
            tight_end.val = pos + n.text_len
            pos = pos + n.text_len
          }
        CstElement::Token(t) => {
          let len = t.text_len()
          let contributes = match trivia_kind {
            Some(tk) => t.kind != tk
            None => true
          }
          if contributes {
            if not(found_start.val) {
              tight_start.val = pos
              found_start.val = true
            }
            tight_end.val = pos + len
          }
          pos = pos + len
        }
      }
    }
    pos
  }
  scan(self.cst.children, self.offset) |> ignore
  if not(found_start.val) {
    return (self.offset, self.offset)
  }
  (tight_start.val, tight_end.val)
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
  walk_children_flat(
    self.cst.children,
    self,
    self.offset,
    fn(child, parent, pos) {
      let child_syn = SyntaxNode::new(child, Some(parent), pos)
      children_json.push(child_syn.to_json())
    },
    fn(tok, pos) {
      let RawKind(tk) = tok.kind
      children_json.push({
        "kind": (tk : Int),
        "text": tok.text,
        "start": (pos : Int),
        "end": pos + tok.text_len(),
      })
    },
  )
  |> ignore
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
  let count : Ref[Int] = Ref::new(0)
  let result : SyntaxNode? = None
  fn search(
    children : Array[CstElement],
    parent : SyntaxNode,
    off : Int,
  ) -> (SyntaxNode?, Int) {
    let mut pos = off
    for elem in children {
      match elem {
        CstElement::Node(child_cst) =>
          if child_cst.kind == repeat_group_kind {
            let (found, new_pos) = search(child_cst.children, parent, pos)
            if found is Some(_) {
              return (found, new_pos)
            }
            pos = new_pos
          } else {
            if count.val == n {
              return (Some(SyntaxNode::new(child_cst, Some(parent), pos)), pos)
            }
            count.val = count.val + 1
            pos = pos + child_cst.text_len
          }
        CstElement::Token(tok) => pos = pos + tok.text_len()
      }
    }
    (result, pos)
  }
  let (found, _) = search(self.cst.children, self, self.offset)
  found
}

///|
/// First interior-node child whose kind matches `kind`, or None.
pub fn SyntaxNode::child_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxNode? {
  let result : SyntaxNode? = None
  fn search(
    children : Array[CstElement],
    parent : SyntaxNode,
    off : Int,
  ) -> (SyntaxNode?, Int) {
    let mut pos = off
    for elem in children {
      match elem {
        CstElement::Node(child_cst) =>
          if child_cst.kind == repeat_group_kind {
            let (found, new_pos) = search(child_cst.children, parent, pos)
            if found is Some(_) {
              return (found, new_pos)
            }
            pos = new_pos
          } else if child_cst.kind == kind {
            return (Some(SyntaxNode::new(child_cst, Some(parent), pos)), pos)
          } else {
            pos = pos + child_cst.text_len
          }
        CstElement::Token(tok) => pos = pos + tok.text_len()
      }
    }
    (result, pos)
  }
  let (found, _) = search(self.cst.children, self, self.offset)
  found
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
  fn drill_children(
    children : Array[CstElement],
    parent : SyntaxNode,
    base_offset : Int,
    target : Int,
  ) -> SyntaxNode? {
    let mut pos = base_offset
    for elem in children {
      match elem {
        CstElement::Node(child_cst) => {
          let child_end = pos + child_cst.text_len
          if pos <= target && target < child_end {
            if child_cst.kind == repeat_group_kind {
              // Transparent: drill into RepeatGroup keeping real parent
              return drill_children(child_cst.children, parent, pos, target)
            } else {
              let child = SyntaxNode::new(child_cst, Some(parent), pos)
              return Some(
                drill_children(child.cst.children, child, child.offset, target).unwrap_or(
                  child,
                ),
              )
            }
          }
          pos = child_end
        }
        CstElement::Token(tok) => pos = pos + tok.text_len()
      }
    }
    None
  }
  drill_children(self.cst.children, self, self.offset, offset).unwrap_or(self)
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

///|
/// Find the token(s) at a byte offset.
///
/// Returns `Single` when `offset` falls strictly inside a token's span.
/// Also returns `Single` when `offset` exactly hits a zero-width token
/// (`start == end == offset`), commonly used by parser error recovery.
/// Returns `Between` when `offset` sits exactly on the boundary between two
/// adjacent tokens (`left.end() == offset == right.start()`).
/// Returns `None` when no token covers the offset.
///
/// Performs an inlined DFS with early exit on strict interior match —
/// no intermediate allocation.
pub fn SyntaxNode::token_at_offset(
  self : SyntaxNode,
  offset : Int,
) -> TokenAtOffset {
  let mut left : SyntaxToken? = None
  let mut right : SyntaxToken? = None
  let mut found : TokenAtOffset? = None
  fn scan(node : SyntaxNode) -> Unit {
    if found is Some(_) {
      return
    }
    let mut pos = node.offset
    for elem in node.cst.children {
      if found is Some(_) {
        break
      }
      match elem {
        CstElement::Token(tok) => {
          let syn = SyntaxToken::new(tok, pos)
          if syn.start() == offset && syn.end() == offset {
            found = Some(Single(syn))
            break
          }
          if syn.start() < offset && offset < syn.end() {
            found = Some(Single(syn))
            break
          }
          if syn.end() == offset {
            left = Some(syn)
          }
          if syn.start() == offset {
            right = Some(syn)
          }
          pos = pos + tok.text_len()
        }
        CstElement::Node(child_cst) => {
          scan(SyntaxNode::new(child_cst, None, pos))
          pos = pos + child_cst.text_len
        }
      }
    }
  }
  scan(self)
  match found {
    Some(r) => r
    None =>
      match (left, right) {
        (Some(l), Some(r)) => Between(l, r)
        (Some(l), None) => Single(l) // cursor at end of last token
        (None, Some(r)) => Single(r) // cursor at start of first token
        _ => TokenAtOffset::None
      }
  }
}
