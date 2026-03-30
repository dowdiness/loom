///|
/// Language-independent node kind (equivalent to rowan's RawSyntaxKind).
/// Each language defines its own enum and converts to/from RawKind via to_raw()/from_raw().
pub(all) struct RawKind(Int) derive(Eq, Show, Hash, Compare, Debug)

///|
/// Reserved RawKind for transparent repeat-group nodes.
/// SyntaxNode methods flatten these — consumers see flat sibling lists.
pub let repeat_group_kind : RawKind = RawKind(-1)

///|
/// A leaf token in the CST.
///
/// ## Invariants
///
/// - `hash` is a stable structural hash computed from `kind` and `text`
///   at construction time by `CstToken::new`. It is used as the fast-path
///   for `Eq` and as the `Hash` trait output (see stability guarantees on
///   the `Eq` and `Hash` impls below).
/// - `hash`, `kind`, and `text` are frozen after construction. Never mutate
///   these fields directly; doing so invalidates the equality and hash semantics.
pub(all) struct CstToken {
  kind : RawKind
  text : String
  hash : Int
} derive(Show, Debug)

///|
/// Create a CstToken. Hash is computed from kind and text.
pub fn CstToken::new(kind : RawKind, text : String) -> CstToken {
  let RawKind(k) = kind
  let h = combine_hash(k, string_hash(text))
  { kind, text, hash: h }
}

///|
/// Number of bytes in this token's text (`text.length()`).
pub fn CstToken::text_len(self : CstToken) -> Int {
  self.text.length()
}

///|
/// **Stability guarantee:** Two `CstToken`s are equal iff they have the
/// same `kind` and `text`. The cached `hash` is compared first as a fast
/// rejection path; a hash match does NOT skip the kind/text comparison.
/// This behavior is stable across versions.
///
/// ## Why `physical_equal` comes first
///
/// Tokens are deduplicated by the `Interner`: all tokens with the same
/// `(kind, text)` share one canonical heap object. When the node interner
/// later compares two `CstNode`s that were built from interned tokens, the
/// token children are already the *same* canonical reference.
/// `physical_equal` turns that O(len) string comparison into O(1).
///
/// Without this fast-path, deeply nested trees (e.g. 320-deep let chains)
/// suffered O(n²) total equality cost because every `CstNode::Eq` call
/// recursively compared all descendant tokens by value.
/// See ADR `docs/decisions/2026-03-14-physical-equal-interner.md`.
pub impl Eq for CstToken with equal(self, other) {
  if physical_equal(self, other) {
    return true
  }
  if self.hash != other.hash {
    return false
  }
  self.kind == other.kind && self.text == other.text
}

///|
/// **Stability guarantee:** The `Hash` output is the cached structural hash
/// (`combine_hash(RawKind.inner, string_hash(text))`). This value is stable
/// as long as `combine_hash` and `string_hash` are stable.
pub impl Hash for CstToken with hash_combine(self, hasher) {
  hasher.combine_int(self.hash)
}

///|
pub(all) enum CstElement {
  Token(CstToken)
  Node(CstNode)
} derive(Show, Debug)

///|
/// Total byte length of this element's text.
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
pub impl Eq for CstElement with equal(self, other) {
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
pub impl Hash for CstElement with hash_combine(self, hasher) {
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
/// - `hash` is a stable structural content hash derived recursively from
///   `kind` and every child's hash. Two `CstNode`s are structurally equal
///   iff they have the same `kind`, same number of children, and pairwise-
///   equal children. The `Eq` impl uses `hash` as a fast rejection path
///   (see stability guarantee on `Eq` below).
///
/// - `text_len` is the total byte length of all leaf token text under this
///   node, computed as the sum of `child.text_len()` at construction time.
///
/// - `token_count` is the non-trivia leaf token count (see field doc below).
pub(all) struct CstNode {
  kind : RawKind
  children : Array[CstElement]
  text_len : Int
  hash : Int
  /// Non-trivia leaf token count. Equals the number of leaf tokens whose kind
  /// is NOT equal to `trivia_kind` (when provided to `CstNode::new`).
  /// Equals the total leaf token count when no `trivia_kind` is given.
  /// Used by the incremental parser to advance `position` (whitespace-free
  /// token index) without an O(subtree) traversal on every reuse.
  token_count : Int
  /// True if this node or any descendant has an error or incomplete kind.
  /// Computed at construction time via the optional `error_kind`/`incomplete_kind`
  /// parameters. When those are not provided, defaults to `false`.
  /// Used by the incremental parser to skip O(subtree) error span collection
  /// for healthy reused nodes.
  has_any_error : Bool
} derive(Show, Debug)

///|
/// Create a CstNode. text_len, hash, and token_count are computed from children.
///
/// `trivia_kind`: when provided, leaf tokens with this kind are excluded from
/// `token_count`.  Pass `Some(whitespace_raw_kind)` from the language layer to
/// get a non-whitespace token count.  Pass nothing (or `None`) for a
/// language-agnostic total leaf token count.
pub fn CstNode::new(
  kind : RawKind,
  children : Array[CstElement],
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode {
  let RawKind(k) = kind
  let mut text_len = 0
  let mut h = k
  let mut token_count = 0
  let mut has_any_error = false
  match error_kind {
    Some(ek) => if kind == ek { has_any_error = true }
    None => ()
  }
  if !has_any_error {
    match incomplete_kind {
      Some(ik) => if kind == ik { has_any_error = true }
      None => ()
    }
  }
  for child in children {
    text_len = text_len + child.text_len()
    h = combine_hash(h, child_hash(child))
    match child {
      Token(t) => {
        match trivia_kind {
          Some(ws) => if t.kind != ws { token_count = token_count + 1 }
          None => token_count = token_count + 1
        }
        if !has_any_error {
          match error_kind {
            Some(ek) => if t.kind == ek { has_any_error = true }
            None => ()
          }
        }
        if !has_any_error {
          match incomplete_kind {
            Some(ik) => if t.kind == ik { has_any_error = true }
            None => ()
          }
        }
      }
      Node(n) => {
        token_count = token_count + n.token_count
        if !has_any_error && n.has_any_error {
          has_any_error = true
        }
      }
    }
  }
  let final_hash = if has_any_error { combine_hash(h, 1) } else { h }
  { kind, children, text_len, hash: final_hash, token_count, has_any_error }
}

///|
/// Create a new CstNode with one child replaced. Pure function — original unchanged.
/// Delegates to CstNode::new() for correct metadata recomputation.
pub fn CstNode::with_replaced_child(
  self : CstNode,
  index : Int,
  new_child : CstElement,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode {
  let new_children = self.children.copy()
  new_children[index] = new_child
  CstNode::new(
    self.kind,
    new_children,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
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
/// Accessor for the `kind` field (equivalent to `self.kind`).
pub fn CstNode::kind(self : CstNode) -> RawKind {
  self.kind
}

///|
/// **Stability guarantee:** Two `CstNode`s are structurally equal iff they
/// have the same `kind`, same number of children, and pairwise-equal children
/// (per `CstElement::Eq`). The cached `hash` is compared first as a fast
/// rejection path; a hash match does NOT bypass the deep structural check.
/// This behavior is stable across versions.
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
pub impl Eq for CstNode with equal(self, other) {
  if physical_equal(self, other) {
    return true
  }
  if self.hash != other.hash {
    return false
  }
  if self.kind != other.kind ||
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
/// **Stability guarantee:** The `Hash` output is the cached structural content
/// hash, derived recursively from `kind` and each child's variant-tagged hash
/// via `combine_hash`. Stable as long as `combine_hash` is stable.
pub impl Hash for CstNode with hash_combine(self, hasher) {
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
/// **Prefer `has_any_error`** when the tree was built with `error_kind`/
/// `incomplete_kind` parameters — the cached field is O(1) vs O(n) traversal.
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
