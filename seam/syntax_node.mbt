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
  self.cst.text().to_owned()
}

///|
/// Zero-copy view of this token's text.
pub fn SyntaxToken::text_view(self : SyntaxToken) -> StringView {
  self.cst.text()
}

///|
/// Show: compact form — "SyntaxToken@[start,end)"
pub impl Show for SyntaxToken with fn output(self, logger) {
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
} derive(Debug)

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
} derive(Debug)

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
/// A `SyntaxNode` pairs an immutable `CstNode` with the absolute UTF-16
/// code-unit `offset` of its start in the source. Unlike `CstNode`,
/// `SyntaxNode` values are created on demand and are not cached or shared.
///
/// **Invariant:** `offset + cst.text_len` is the exclusive end offset.
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
/// Create a root SyntaxNode from a CstNode at a given UTF-16 code-unit offset,
/// no parent.
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
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Token(t) => Some(t)
      // Recursive find-map: a token-free child yields None and is skipped,
      // so scanning falls through to the next sibling.
      Node(n) => n.first_token()
    }
  })
  .head()
}

///|
/// Absolute UTF-16 code-unit offset of this node's start in the source.
pub fn SyntaxNode::start(self : SyntaxNode) -> Int {
  self.offset
}

///|
/// Exclusive UTF-16 code-unit offset of this node's end in the source (`start + text_len`).
pub fn SyntaxNode::end(self : SyntaxNode) -> Int {
  self.offset + self.cst.text_len
}

///|
/// The language-agnostic kind of the underlying `CstNode`.
pub fn SyntaxNode::kind(self : SyntaxNode) -> RawKind {
  self.cst.kind
}

///|
/// Covered source text of this node: the concatenation of every token's text
/// in this subtree, in source order (trivia included).
///
/// Reconstructed from the tokens themselves, so it never needs the original
/// source string and works for synthetic (non-source-backed) tokens too.
/// Allocates a fresh `String` per call; `text().length()` equals
/// `end() - start()`.
pub fn SyntaxNode::text(self : SyntaxNode) -> String {
  CstElement::Node(self.cst)
  .iter()
  .filter_map(element => {
    match element {
      Token(token) => Some(token.text())
      // iter() is depth-first; a node's tokens arrive on their own
      Node(_) => None
    }
  })
  .join("")
}

///|
/// Show: compact form — "SyntaxNode@[start,end)"
pub impl Show for SyntaxNode with fn output(self, logger) {
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
/// Interior-node children starting from index `start` (0-indexed, tokens skipped).
/// Like `children()` but skips the first `start` node children.
/// Negative `start` is treated as 0.
pub fn SyntaxNode::children_from(
  self : SyntaxNode,
  start : Int,
) -> Array[SyntaxNode] {
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Node(n) => Some(n)
      Token(_) => None
    }
  })
  .drop(if start < 0 { 0 } else { start })
  .collect()
}

///|
/// Iterator over all direct visible children as positioned `SyntaxElement`s,
/// preserving source order.
///
/// `RepeatGroup` nodes are transparent: their children are yielded as direct
/// visible children of `self`, and the `RepeatGroup` wrapper itself is skipped.
/// Non-repeat child nodes are yielded without recursively traversing into them.
///
/// The iterator is single-pass. Request a fresh iterator from the node when you
/// need to traverse the visible children again.
pub fn SyntaxNode::direct_elements_iter(
  self : SyntaxNode,
) -> Iter[SyntaxElement] {
  let iter = self.cst.direct_elements_iter()
  let mut pos = self.offset
  Iter::new(() => {
    match iter.next() {
      Some(CstElement::Node(child)) => {
        let elem = SyntaxElement::Node(SyntaxNode::new(child, Some(self), pos))
        pos = pos + child.text_len
        Some(elem)
      }
      Some(CstElement::Token(tok)) => {
        let elem = SyntaxElement::Token(SyntaxToken::new(tok, pos))
        pos = pos + tok.text_len()
        Some(elem)
      }
      None => None
    }
  })
}

///|
/// All direct children as `SyntaxElement`s, preserving token order.
pub fn SyntaxNode::all_children(self : SyntaxNode) -> Array[SyntaxElement] {
  self.direct_elements_iter().collect()
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
  for elem in self.direct_elements_iter() {
    match elem {
      Node(n) => nodes.push(n)
      Token(t) => {
        let keep = match trivia_kind {
          Some(tk) => t.kind() != tk
          None => true
        }
        if keep {
          tokens.push(t)
        }
      }
    }
  }
  (nodes, tokens)
}

///|
/// How one direct element affects separator grouping: a separator token opens
/// the next group, any other (non-trivia) element joins the current group.
priv enum GroupOp {
  StartGroup
  AppendElement(SyntaxElement)
}

///|
/// Classify one direct element for `direct_elements_grouped_by`: separator
/// tokens become `StartGroup`, filtered trivia becomes `None`, everything
/// else is `AppendElement`. Separator classification wins over trivia when
/// the two kinds collide.
fn element_to_group_op(
  elem : SyntaxElement,
  separator : RawKind,
  trivia_kind : RawKind?,
) -> GroupOp? {
  match elem {
    Token(t) if t.kind() == separator => Some(StartGroup)
    Token(t) if trivia_kind is Some(k) && t.kind() == k => None
    _ => Some(AppendElement(elem))
  }
}

///|
/// Apply one grouping operation to the builder state.
fn apply_group_op(groups : Array[Array[SyntaxElement]], op : GroupOp) -> Unit {
  match op {
    StartGroup => groups.push([])
    AppendElement(elem) => groups[groups.length() - 1].push(elem)
  }
}

///|
/// Split direct children into element groups delimited by `separator` tokens.
///
/// N separator tokens always yield N+1 groups; empty groups are preserved
/// (leading, trailing, and doubled separators), so element-slot boundaries
/// are never silently dropped. Separator tokens themselves appear in no
/// group, and only *tokens* of the separator kind split — nodes sharing the
/// raw kind do not. When `trivia_kind` is provided, tokens of that kind are
/// excluded from groups (same convention as `nodes_and_tokens`).
///
/// `RepeatGroup` nodes are transparent: their children are grouped as direct
/// visible children of `self`.
pub fn SyntaxNode::direct_elements_grouped_by(
  self : SyntaxNode,
  separator : RawKind,
  trivia_kind? : RawKind? = None,
) -> Array[Array[SyntaxElement]] {
  // Builder state: groups grows append-only while streaming the element iter.
  let groups : Array[Array[SyntaxElement]] = [[]]
  for elem in self.direct_elements_iter() {
    match element_to_group_op(elem, separator, trivia_kind) {
      Some(op) => apply_group_op(groups, op)
      None => ()
    }
  }
  groups
}

///|
/// Direct leaf tokens only (child nodes are skipped).
///
/// `RepeatGroup` nodes are transparent: their token children are reported as
/// direct visible children of `self`. Other interior nodes are not searched.
pub fn SyntaxNode::tokens(self : SyntaxNode) -> Array[SyntaxToken] {
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Token(t) => Some(t)
      Node(_) => None
    }
  })
  .collect()
}

///|
/// Direct child nodes whose kind matches `kind`, in source order.
///
/// `RepeatGroup` nodes are transparent: their node children are reported as
/// direct visible children of `self`. Other interior nodes are not searched.
pub fn SyntaxNode::direct_children_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> Array[SyntaxNode] {
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Node(n) => if n.kind() == kind { Some(n) } else { None }
      Token(_) => None
    }
  })
  .collect()
}

///|
/// First direct token child matching `kind`, with its absolute offset.
///
/// Alias with an explicit name for projection code that validates concrete
/// argument shape. Equivalent to `find_token(kind)`.
pub fn SyntaxNode::direct_token_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxToken? {
  self.find_token(kind)
}

///|
/// True when this node has at least one direct token child matching `kind`.
///
/// Uses the same direct visible-child semantics as `direct_token_of_kind`:
/// `RepeatGroup` nodes are transparent, and other interior nodes are not
/// searched.
pub fn SyntaxNode::has_direct_token_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> Bool {
  self.direct_token_of_kind(kind) is Some(_)
}

///|
/// All direct token children matching `kind`, in source order.
///
/// Alias with an explicit name for projection code that validates concrete
/// argument shape. Equivalent to `tokens_of_kind(kind)`.
pub fn SyntaxNode::direct_tokens_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> Array[SyntaxToken] {
  self.tokens_of_kind(kind)
}

///|
/// First direct token child matching `kind`, with its absolute offset.
///
/// `RepeatGroup` nodes are transparent: their token children are considered
/// direct visible children of `self`. Other interior nodes are not searched.
pub fn SyntaxNode::find_token(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxToken? {
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Token(t) => if t.kind() == kind { Some(t) } else { None }
      Node(_) => None
    }
  })
  .head()
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
///
/// `RepeatGroup` nodes are transparent: their token children are considered
/// direct visible children of `self`. Other interior nodes are not searched.
pub fn SyntaxNode::tokens_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> Array[SyntaxToken] {
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Token(t) => if t.kind() == kind { Some(t) } else { None }
      Node(_) => None
    }
  })
  .collect()
}

///|
/// Tight UTF-16 code-unit span of this node, skipping leading and trailing trivia tokens.
///
/// Pass `trivia_kind` to identify whitespace/comment tokens to skip.
/// Interior `CstNode` children are never treated as trivia.
pub fn SyntaxNode::tight_span(
  self : SyntaxNode,
  trivia_kind? : RawKind? = None,
) -> (Int, Int) {
  self
  .direct_elements_iter()
  .filter(elem => {
    match elem {
      Token(t) => trivia_kind.map_or_else(() => true, kind => t.kind() != kind)
      Node(_) => true
    }
  })
  .fold(init=(None : (Int, Int)?), (range, e) => {
    match range {
      None => Some((e.start(), e.end()))
      Some((s, _)) => Some((s, e.end()))
    }
  })
  .unwrap_or((self.offset, self.offset))
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
/// Derived[SyntaxNode] correctly skips recomputation when only positions shift
/// (e.g. after inserting a leading space) but the tree structure is unchanged.
pub impl Eq for SyntaxNode with fn equal(self, other : SyntaxNode) -> Bool {
  self.cst == other.cst
}

///|
/// Generic JSON serialization of a SyntaxNode.
/// Produces: { "kind": <raw int>, "start": <int>, "end": <int>, "children": [...] }
/// Tokens appear as: { "kind": <raw int>, "text": <string>, "start": <int>, "end": <int> }
/// For typed semantic JSON, use the view types in your language package instead.
pub impl ToJson for SyntaxNode with fn to_json(self) -> Json {
  let RawKind(k) = self.cst.kind
  let children_json : Array[Json] = self
    .direct_elements_iter()
    .map(elem => {
      match elem {
        Node(n) => n.to_json()
        Token(t) => {
          let RawKind(tk) = t.kind()
          (
            {
              "kind": (tk : Int),
              "text": t.text(),
              "start": (t.start() : Int),
              "end": (t.end() : Int),
            } : Json)
        }
      }
    })
    .collect()
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
  guard n >= 0 else { None }
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Node(node) => Some(node)
      Token(_) => None
    }
  })
  .drop(n)
  .head()
}

///|
/// First interior-node child whose kind matches `kind`, or None.
pub fn SyntaxNode::child_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxNode? {
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      Node(n) => if n.kind() == kind { Some(n) } else { None }
      Token(_) => None
    }
  })
  .head()
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
  self
  .direct_elements_iter()
  .filter_map(elem => {
    match elem {
      // Children tile the span disjointly, so at most one node covers offset;
      // zero-width children (start == end) never cover.
      Node(n) =>
        if n.start() <= offset && offset < n.end() {
          Some(n)
        } else {
          None
        }
      Token(_) => None
    }
  })
  .head()
  .map_or_else(() => self, child => child.find_at(offset))
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
/// Push `children` onto `stack` in reverse source order, pairing each with
/// its absolute offset. Offsets are derived right-to-left from the parent's
/// exclusive `end`, so no forward prefix-sum pass or temporary array is
/// needed.
fn push_positioned_reversed(
  stack : Array[(CstElement, Int)],
  children : Array[CstElement],
  end : Int,
) -> Unit {
  let mut pos = end
  for i = children.length() - 1; i >= 0; i = i - 1 {
    let elem = children[i]
    pos = pos -
      (match elem {
        CstElement::Token(tok) => tok.text_len()
        CstElement::Node(n) => n.text_len
      })
    stack.push((elem, pos))
  }
}

///|
/// Lazy iterator over every token in this subtree, positioned, in source
/// order (trivia included). The subtree-deep complement of
/// `direct_elements_iter`.
///
/// Uses an explicit stack (same approach as `CstElement::iter`) so each
/// pull is O(1) amortized regardless of tree depth — a recursive
/// `flat_map` formulation benchmarked 11-25x slower on this hot path.
pub fn SyntaxNode::deep_tokens_iter(self : SyntaxNode) -> Iter[SyntaxToken] {
  let stack : Array[(CstElement, Int)] = []
  push_positioned_reversed(stack, self.cst.children, self.end())
  Iter::new(() => {
    for ;; {
      match stack.pop() {
        None => return None
        Some((CstElement::Token(tok), off)) =>
          return Some(SyntaxToken::new(tok, off))
        Some((CstElement::Node(n), off)) =>
          push_positioned_reversed(stack, n.children, off + n.text_len)
      }
    }
  })
}

///|
/// Find the token(s) at a UTF-16 code-unit offset.
///
/// Returns `Single` when `offset` falls strictly inside a token's span.
/// Also returns `Single` when `offset` exactly hits a zero-width token
/// (`start == end == offset`), commonly used by parser error recovery.
/// Returns `Between` when `offset` sits exactly on the boundary between two
/// adjacent tokens (`left.end() == offset == right.start()`).
/// Returns `None` when no token covers the offset.
///
/// Performs an inlined DFS with early exit on strict interior match —
/// no intermediate allocation. Deliberately imperative: a declarative
/// two-pass formulation over `deep_tokens_iter` benchmarked 2.4-6.8x
/// slower (see syntax_node_bench_wbtest.mbt, which guards this path).
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
