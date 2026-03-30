///|
/// Monoid catamorphism — folds children with `combine` without allocating
/// an intermediate `Array[R]`.
///
/// Each leaf is mapped by `on_token`. For interior nodes, child results are
/// accumulated left-to-right via `combine`, starting from `empty`.
pub fn[R] GreenNode::fold(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  combine : (R, R) -> R,
  empty : R,
) -> R {
  match self {
    Leaf(kind, text) => on_token(kind, text)
    Branch(_, children) =>
      for child in children; acc = empty {
        continue combine(acc, child.fold(on_token, combine, empty))
      } nobreak {
        acc
      }
  }
}
