///|
/// Fused transform+fold: avoids `Array[R]` allocation entirely.
///
/// Like `transform`, recursively processes children bottom-up. But instead of
/// collecting child results into an `Array[R]`, it folds them inline using
/// `on_node(kind, accumulator, child_result) -> accumulator`.
///
/// This eliminates the main overhead source in `transform` (one Array allocation
/// per branch node) while preserving access to the branch's `SyntaxKind`.
pub fn[R] transform_fold(
  node : GreenNode,
  on_token : (TokenKind, String) -> R,
  init : (SyntaxKind) -> R,
  on_child : (SyntaxKind, R, R) -> R,
) -> R {
  match node {
    Leaf(kind, text) => on_token(kind, text)
    Branch(kind, children) => {
      let mut acc = init(kind)
      for child in children {
        acc = on_child(
          kind,
          acc,
          transform_fold(child, on_token, init, on_child),
        )
      }
      acc
    }
  }
}
