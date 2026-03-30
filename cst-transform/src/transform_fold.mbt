///|
/// Fused transform+fold: avoids `Array[R]` allocation entirely.
///
/// Like `transform`, recursively processes children bottom-up. But instead of
/// collecting child results into an `Array[R]`, it folds them inline using
/// `on_child(kind, accumulator, child_result) -> accumulator`.
///
/// This eliminates the main overhead source in `transform` (one Array allocation
/// per branch node) while preserving access to the branch's `SyntaxKind`.
pub fn[R] GreenNode::transform_fold(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  init : (SyntaxKind) -> R,
  on_child : (SyntaxKind, R, R) -> R,
) -> R {
  match self {
    Leaf(kind, text) => on_token(kind, text)
    Branch(kind, children) =>
      for child in children; acc = init(kind) {
        continue on_child(
            kind,
            acc,
            child.transform_fold(on_token, init, on_child),
          )
      } nobreak {
        acc
      }
  }
}
