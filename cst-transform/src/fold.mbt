///|
/// Monoid catamorphism — folds children with `combine` without allocating
/// an intermediate `Array[R]`.
///
/// Each leaf is mapped by `on_token`. For interior nodes, child results are
/// accumulated left-to-right via `combine`, starting from `empty`.
pub fn[R] fold(
  node : GreenNode,
  on_token : (TokenKind, String) -> R,
  combine : (R, R) -> R,
  empty : R,
) -> R {
  match node {
    Leaf(kind, text) => on_token(kind, text)
    Branch(_, children) => {
      let mut acc = empty
      for child in children {
        acc = combine(acc, fold(child, on_token, combine, empty))
      }
      acc
    }
  }
}
