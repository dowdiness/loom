///|
/// CPS variant of `transform` — avoids allocating `Array[R]` for children.
///
/// Instead of collecting child results into an array, `on_children` receives
/// a callback-based stream: `each_child` calls `emit` once per child result.
/// The caller decides whether to accumulate into an array, fold inline, etc.
pub fn[R] GreenNode::transform_cps(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  on_children : (SyntaxKind, ((R) -> Unit) -> Unit) -> R,
) -> R {
  match self {
    Leaf(kind, text) => on_token(kind, text)
    Branch(kind, children) =>
      on_children(kind, fn(emit) {
        for child in children {
          emit(child.transform_cps(on_token, on_children))
        }
      })
  }
}
