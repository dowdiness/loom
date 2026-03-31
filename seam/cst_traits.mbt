// cst_traits.mbt — Trait-based static dispatch for CST traversal.
//
// MoonBit monomorphizes trait method calls and unboxes single-element tuple
// structs. Folder achieves ~1.0x vs hand-written when leaf work is non-trivial
// (e.g., TextLen). TransformFolder has ~1.6x overhead due to missing trait
// method body inlining (fixed per-element call frame cost, independent of
// the wrapper type). See cst-transform/REPORT.md and
// docs/performance/2026-03-31-map-specialization.md.

///|
/// Monoid fold over leaves. Branches contribute `fold_empty()`.
///
/// Use single-element tuple struct newtypes (e.g., `struct TextLen(Int)`)
/// as the `Self` type — the compiler guarantees unboxing. Near 1.0x vs
/// hand-written when leaf work is non-trivial (e.g., `text.length()`).
pub(open) trait Folder {
  fold_token(CstToken) -> Self
  fold_combine(Self, Self) -> Self
  fold_empty() -> Self
}

///|
/// Fused transform+fold. Branches contribute `tf_init(kind)`.
///
/// Like `Folder`, but branches have a value — `tf_init(kind)` is the
/// initial accumulator for each branch, and `tf_child(acc, child)`
/// folds each child result into it. ~1.6x overhead due to extra trait
/// calls per element (tf_init + tf_child); will improve when MoonBit
/// adds trait method body inlining.
pub(open) trait TransformFolder {
  tf_token(CstToken) -> Self
  tf_init(RawKind) -> Self
  tf_child(Self, Self) -> Self
}

///|
/// Statically-dispatched monoid fold. No closure allocation.
pub fn[R : Folder] CstElement::accept_fold(self : CstElement) -> R {
  match self {
    Token(token) => R::fold_token(token)
    Node({ children, .. }) =>
      for child in children; acc = (R::fold_empty() : R) {
        continue R::fold_combine(acc, child.accept_fold())
      } nobreak {
        acc
      }
  }
}

///|
/// Statically-dispatched fused transform+fold. No closure allocation.
pub fn[R : TransformFolder] CstElement::accept_transform_fold(
  self : CstElement,
) -> R {
  match self {
    Token(token) => R::tf_token(token)
    Node({ kind, children, .. }) =>
      for child in children; acc = (R::tf_init(kind) : R) {
        continue R::tf_child(acc, child.accept_transform_fold())
      } nobreak {
        acc
      }
  }
}

// ── Concrete implementations ──────────────────────────────────────────

///|
/// Sum of all token text lengths. Validates against `CstNode.text_len`.
pub(all) struct TextLen(Int) derive(Show)

///|
pub impl Folder for TextLen with fold_token(token) {
  TextLen(token.text.length())
}

///|
pub impl Folder for TextLen with fold_combine(self, other) {
  TextLen(self.0 + other.0)
}

///|
pub impl Folder for TextLen with fold_empty() {
  TextLen(0)
}

///|
/// Count of all elements (tokens + branches). Branches count as 1.
pub(all) struct NodeCount(Int) derive(Show)

///|
pub impl TransformFolder for NodeCount with tf_token(_token) {
  NodeCount(1)
}

///|
pub impl TransformFolder for NodeCount with tf_init(_kind) {
  NodeCount(1)
}

///|
pub impl TransformFolder for NodeCount with tf_child(acc, child) {
  NodeCount(acc.0 + child.0)
}
