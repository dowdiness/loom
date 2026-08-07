///|
/// Language-independent node kind (equivalent to rowan's RawSyntaxKind).
/// Each language defines its own enum and converts to/from RawKind via to_raw()/from_raw().
pub(all) struct RawKind(Int) derive(Eq, Hash, Compare, Debug)

///|
pub impl Show for RawKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Reserved RawKind for transparent repeat-group nodes.
/// SyntaxNode methods flatten these — consumers see flat sibling lists.
pub let repeat_group_kind : RawKind = RawKind(-1)

///|
/// A leaf token in the CST.
///
/// ## Invariants
///
/// - `source`, `start`, and `end` identify this token's text as a span into a
///   source string. The constructor records the incoming `StringView` directly,
///   so lexing can build tokens without copying substrings.
/// - `source_backed` distinguishes lexer/source tokens from parser-synthetic
///   placeholders. Token equality and hashing include this provenance so node
///   interning cannot collapse parser placeholders with lexer tokens.
/// - `hash` is a stable structural hash computed from `kind` and `text()`
///   at construction time by `CstToken::CstToken`. It is used as the fast-path
///   for `Eq` and as the `Hash` trait output (see stability guarantees on
///   the `Eq` and `Hash` impls below).
/// - `hash`, `kind`, `source`, `start`, `end`, and `source_backed` are frozen
///   after construction. Package internals must never mutate these fields after
///   construction; doing so invalidates the equality and hash semantics.
pub struct CstToken {
  kind : RawKind
  priv source : String
  priv start : Int
  priv end : Int
  priv hash : Int
  priv source_backed : Bool
} derive(Debug(ignore=[String]))

///|
/// Create a CstToken. Hash is computed from kind and text.
#alias(new, deprecated="Use CstToken::CstToken(kind, text) instead")
pub fn CstToken::CstToken(kind : RawKind, text : StringView) -> CstToken {
  let RawKind(k) = kind
  let h = combine_hash(combine_hash(k, string_hash(text)), 1)
  let start = text.start_offset()
  {
    kind,
    source: text.data(),
    start,
    end: start + text.length(),
    hash: h,
    source_backed: true,
  }
}

///|
fn CstToken::synthetic_zero_width(kind : RawKind) -> CstToken {
  let text = ""
  let RawKind(k) = kind
  let h = combine_hash(combine_hash(k, string_hash(text)), 0)
  { kind, source: text, start: 0, end: 0, hash: h, source_backed: false }
}

///|
/// Return true when this token came from a source-backed lexer span rather
/// than a parser-synthetic placeholder.
///
/// STABLE TOKEN-PROVENANCE API (#226): this is the supported way to distinguish
/// lexer/source tokens from parser-inserted zero-width recovery placeholders.
/// The predicate does not expose backing-source ownership; use `text()` for
/// token content, and use structural `SyntaxToken` offsets when you need a
/// token's position in a tree.
pub fn CstToken::is_source_backed(self : CstToken) -> Bool {
  self.source_backed
}

///|
/// Return this token's text as a zero-copy view into `source`.
pub fn CstToken::text(self : CstToken) -> StringView {
  self.source.view(start_offset=self.start, end_offset=self.end)
}

///|
/// Return the backing source string that owns this token's text span.
///
/// UNSTABLE/UNSAFE API (#186): this exposes storage identity, not token
/// content. Prefer `text()` for token content and `start_offset()` /
/// `end_offset()` for span coordinates. This hook exists for parser-internal
/// source-retention checks and may change before seam stabilization.
#alias(source, deprecated="Use CstToken::text() for token content; backing-source identity is unstable. Use unsafe_backing_source only for white-box source-retention checks")
pub fn CstToken::unsafe_backing_source(self : CstToken) -> String {
  self.source
}

///|
/// Start offset of this token's text within `source`.
pub fn CstToken::start_offset(self : CstToken) -> Int {
  self.start
}

///|
/// Exclusive end offset of this token's text within `source`.
pub fn CstToken::end_offset(self : CstToken) -> Int {
  self.end
}

///|
/// Number of UTF-16 code units in this token's text span.
pub fn CstToken::text_len(self : CstToken) -> Int {
  self.end - self.start
}

///|
/// **Stability guarantee:** Two `CstToken`s are equal iff they have the same
/// `kind`, same `text()`, and same source-backed/synthetic provenance. The
/// cached `hash` is compared first as a fast rejection path; a hash match does
/// NOT skip the kind/text/provenance comparison.
/// This behavior is stable across versions.
///
/// ## Why `physical_equal` comes first
///
/// When callers use the `Interner`, all tokens with the same `(kind, text)`
/// share one canonical heap object. When the node interner
/// later compares two `CstNode`s that were built from interned tokens, the
/// token children are already the *same* canonical reference.
/// `physical_equal` turns that O(len) string comparison into O(1).
///
/// Without this fast-path, deeply nested trees (e.g. 320-deep let chains)
/// suffered O(n²) total equality cost because every `CstNode::Eq` call
/// recursively compared all descendant tokens by value.
/// See ADR `docs/decisions/2026-03-14-physical-equal-interner.md`.
pub impl Eq for CstToken with fn equal(self, other) {
  if physical_equal(self, other) {
    return true
  }
  if self.hash != other.hash {
    return false
  }
  self.kind == other.kind &&
  self.source_backed == other.source_backed &&
  self.text() == other.text()
}

///|
/// **Stability guarantee:** The `Hash` output is the cached structural hash
/// (`combine_hash(combine_hash(RawKind.inner, string_hash(text())), provenance)`).
/// This value is stable as long as `combine_hash` and `string_hash` are stable.
pub impl Hash for CstToken with fn hash_combine(self, hasher) {
  hasher.combine_int(self.hash)
}

///|
pub(all) enum CstElement {
  Token(CstToken)
  Node(CstNode)
} derive(Debug)

///|
/// Total UTF-16 code-unit length of this element's text.
pub fn CstElement::text_len(self : CstElement) -> Int {
  match self {
    Token(t) => t.text_len()
    Node(n) => n.text_len
  }
}

///|
/// The kind of the contained token or node.
pub fn CstElement::kind(self : CstElement) -> RawKind {
  match self {
    Token(t) => t.kind
    Node(n) => n.kind
  }
}

///|
pub impl Eq for CstElement with fn equal(self, other) {
  match (self, other) {
    (Token(a), Token(b)) => a == b
    (Node(a), Node(b)) => a == b
    _ => false
  }
}

///|
/// Include a variant tag to reduce cross-variant collisions.
/// This is intentionally different from child_hash():
/// - child_hash() is used only for internal cached structural hashing in CstNode::new
/// - Hash trait output adds a variant tag for safer external hash-table usage
pub impl Hash for CstElement with fn hash_combine(self, hasher) {
  let h = match self {
    Token(t) => combine_hash(1, t.hash)
    Node(n) => combine_hash(2, n.hash)
  }
  hasher.combine_int(h)
}

///|
/// An interior node in the CST.
///
/// ## Invariants
///
/// - `children` is frozen after construction. Mutating it externally
///   invalidates the cached `text_len`, `hash`, and `token_count` fields,
///   which are all computed once in `CstNode::new` and never recomputed.
///   Treat `children` as a read-only sequence.
///
/// - `hash` is a private cached collection hash derived from the metadata
///   policy, `kind`, error state, and every child. Its numeric value is not a
///   persistent fingerprint. The `Eq` impl uses it only as a fast rejection
///   path.
///
/// - `text_len` is the total UTF-16 code-unit length of all leaf token text
///   under this node, computed as the sum of `child.text_len()` at construction time.
///
/// - `token_count` is the non-trivia leaf token count (see field doc below).
pub struct CstNode {
  priv kind : RawKind
  priv children : Array[CstElement]
  priv text_len : Int
  priv hash : Int
  /// Non-trivia leaf token count. Equals the number of leaf tokens whose kind
  /// is not classified as trivia by this node's metadata policy.
  /// Used by the incremental parser to advance `position` (whitespace-free
  /// token index) without an O(subtree) traversal on every reuse.
  priv token_count : Int
  /// True if this node or any descendant has an error or incomplete kind.
  /// Computed at construction time from the policy's role-distinct error and
  /// incomplete kinds.
  /// Used by the incremental parser to skip O(subtree) error span collection
  /// for healthy reused nodes.
  priv has_any_error : Bool
  priv policy : CstMetadataPolicy
} derive(Debug(ignore=[CstMetadataPolicy]))

///|
/// Create a classified CstNode.
///
/// The child array is copied before it is retained. Every node child must use
/// an equivalent metadata policy.
pub fn CstNode::new(
  kind : RawKind,
  children : Array[CstElement],
  policy~ : CstMetadataPolicy,
) -> CstNode raise Failure {
  CstNode::new_owned(kind, children.copy(), policy~)
}

///|
/// Create a language-agnostic CstNode using the canonical unclassified policy.
pub fn CstNode::new_unclassified(
  kind : RawKind,
  children : Array[CstElement],
) -> CstNode raise Failure {
  CstNode::new(kind, children, policy=CstMetadataPolicy::unclassified())
}

///|
/// Construct from a package-owned child array without copying it.
///
/// Exclusive array ownership does not imply policy compatibility, so this path
/// performs the same child-policy validation as public construction.
fn CstNode::new_owned(
  kind : RawKind,
  children : Array[CstElement],
  policy~ : CstMetadataPolicy,
) -> CstNode raise Failure {
  let RawKind(k) = kind
  let is_unclassified = physical_equal(
    policy,
    CstMetadataPolicy::unclassified(),
  )
  let mut text_len = 0
  let mut h = combine_hash(policy.semantic_hash, k)
  let mut token_count = 0
  let mut has_any_error = if is_unclassified {
    false
  } else {
    policy.is_error_signal(kind)
  }
  for child in children {
    text_len = text_len + child.text_len()
    h = combine_hash(h, child_hash(child))
    match child {
      Token(t) => {
        if is_unclassified || !policy.is_trivia(t.kind) {
          token_count = token_count + 1
        }
        if !is_unclassified && !has_any_error && policy.is_error_signal(t.kind) {
          has_any_error = true
        }
      }
      Node(n) => {
        if !physical_equal(n.policy, policy) && !policy_equal(n.policy, policy) {
          fail("CstNode: child metadata policy mismatch")
        }
        token_count = token_count + n.token_count
        if !has_any_error && n.has_any_error {
          has_any_error = true
        }
      }
    }
  }
  let final_hash = if has_any_error { combine_hash(h, 1) } else { h }
  {
    kind,
    children,
    text_len,
    hash: final_hash,
    token_count,
    has_any_error,
    policy,
  }
}

///|
/// Create a new CstNode with one child replaced. Pure function — original unchanged.
/// Reuses the receiver policy and recomputes cached metadata.
pub fn CstNode::with_replaced_child(
  self : CstNode,
  index : Int,
  new_child : CstElement,
) -> CstNode raise Failure {
  let new_children = self.children.copy()
  new_children[index] = new_child
  CstNode::new_owned(self.kind, new_children, policy=self.policy)
}

///|
/// Return `new_root` after verifying that it belongs to the receiver's
/// metadata domain. Pure function — both nodes remain unchanged.
///
/// This is the root-level counterpart of `with_replaced_child`: it lets
/// reconstruction code preserve the receiver policy without exposing that
/// policy as public state.
pub fn CstNode::with_replaced_root(
  self : CstNode,
  new_root : CstNode,
) -> CstNode raise Failure {
  guard policy_equal(self.policy, new_root.policy) else {
    fail("CstNode::with_replaced_root: metadata policy mismatch")
  }
  new_root
}

///|
/// Variant-tagged child hash, aligned with `CstElement::Hash`.
/// Reduces cross-variant collisions: a Token and Node with identical raw
/// hashes will not produce the same contribution to the parent's cached hash.
fn child_hash(elem : CstElement) -> Int {
  match elem {
    Token(t) => combine_hash(1, t.hash)
    Node(n) => combine_hash(2, n.hash)
  }
}

///|
/// Language-agnostic node kind.
pub fn CstNode::kind(self : CstNode) -> RawKind {
  self.kind
}

///|
/// Total UTF-16 code-unit length of this node's token text.
pub fn CstNode::text_len(self : CstNode) -> Int {
  self.text_len
}

///|
/// Number of non-trivia leaf tokens under this node.
pub fn CstNode::token_count(self : CstNode) -> Int {
  self.token_count
}

///|
/// Whether this node contains an error or incomplete signal.
pub fn CstNode::has_any_error(self : CstNode) -> Bool {
  self.has_any_error
}

///|
/// Direct children as a read-only view.
pub fn CstNode::children(self : CstNode) -> ArrayView[CstElement] {
  self.children[:]
}

///|
/// Two `CstNode`s are equal iff they have semantically equivalent metadata
/// policies, the same `kind`, and pairwise-equal children. The cached hash is
/// compared first as a rejection path; a hash match never bypasses policy and
/// structural checks.
///
/// ## Why `physical_equal` comes first
///
/// `build_tree_fully_interned` constructs trees bottom-up: children are
/// interned via `NodeInterner` *before* their parent is built. When the
/// parent is then interned, its children are already canonical references
/// from the interner. The HashMap calls this `Eq` to confirm a hash-bucket
/// match. Without `physical_equal`, each child comparison recurses into its
/// own children, producing O(subtree) work per node.
///
/// For a right-recursive grammar (e.g. `let x = 0 in <body>`) with depth n,
/// the outermost node's equality walks all n levels. Summing over all nodes:
///   O(1) + O(2) + ... + O(n) = O(n²)
///
/// With `physical_equal`, interned children short-circuit in O(1), so each
/// node comparison costs O(children_count) — constant for fixed grammars.
/// Total cost drops from O(n²) to O(n).
///
/// Measured: 320-let chain initial parse went from 3.72ms to 662µs (5.6x).
/// See ADR `docs/decisions/2026-03-14-physical-equal-interner.md`.
pub impl Eq for CstNode with fn equal(self, other) {
  if physical_equal(self, other) {
    return true
  }
  if self.hash != other.hash {
    return false
  }
  if !policy_equal(self.policy, other.policy) ||
    self.kind != other.kind ||
    self.has_any_error != other.has_any_error ||
    self.children.length() != other.children.length() {
    return false
  }
  for i = 0; i < self.children.length(); i = i + 1 {
    if self.children[i] != other.children[i] {
      return false
    }
  }
  true
}

///|
/// Supply the cached structural hash to collection implementations.
///
/// The numeric contribution is not a persistent fingerprint and may change
/// between Loom versions.
pub impl Hash for CstNode with fn hash_combine(self, hasher) {
  hasher.combine_int(self.hash)
}

///|
/// First non-trivia token in this subtree (depth-first, left-to-right).
/// `is_trivia` classifies tokens to skip (e.g. whitespace).
/// Returns None when the subtree contains no non-trivia tokens.
pub fn CstNode::first_token(
  self : CstNode,
  is_trivia : (RawKind) -> Bool,
) -> CstToken? {
  for child in self.children {
    match child {
      CstElement::Token(t) => if !is_trivia(t.kind) { return Some(t) }
      CstElement::Node(n) =>
        match n.first_token(is_trivia) {
          Some(_) as found => return found
          None => ()
        }
    }
  }
  None
}

///|
/// Check if this concrete syntax tree contains any error nodes or error tokens.
/// error_node_kind and error_token_kind are language-specific RawKind values.
///
/// **Prefer `has_any_error()`** when querying the construction policy's error
/// roles; the cached value is O(1). Use this method for different query kinds.
pub fn CstNode::has_errors(
  self : CstNode,
  error_node_kind : RawKind,
  error_token_kind : RawKind,
) -> Bool {
  if self.kind == error_node_kind {
    return true
  }
  for elem in self.children {
    match elem {
      Token(t) => if t.kind == error_token_kind { return true }
      Node(n) =>
        if n.has_errors(error_node_kind, error_token_kind) {
          return true
        }
    }
  }
  false
}
