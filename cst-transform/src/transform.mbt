///|
/// Structure-preserving transformation (hylo_rose equivalent).
///
/// Recursively transforms a `GreenNode` bottom-up: leaves are mapped by
/// `on_token`, interior nodes by `on_node` which receives the already-
/// transformed children as `Array[R]`.
pub fn[R] transform(
  node : GreenNode,
  on_token : (TokenKind, String) -> R,
  on_node : (SyntaxKind, Array[R]) -> R,
) -> R {
  match node {
    Leaf(kind, text) => on_token(kind, text)
    Branch(kind, children) => {
      let results = Array::new(capacity=children.length())
      for child in children {
        results.push(transform(child, on_token, on_node))
      }
      on_node(kind, results)
    }
  }
}
