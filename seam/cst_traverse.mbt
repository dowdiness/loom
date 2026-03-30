// cst_traverse.mbt — Closure-based traversal methods for CstElement.
//
// Ported from cst-transform/ research module. See cst-transform/REPORT.md
// for performance characteristics.

///|
/// Bottom-up structure-preserving transformation.
///
/// Leaves are mapped by `on_token`; interior nodes by `on_node` which
/// receives the node's kind and an `Array[R]` of already-transformed children.
pub fn[R] CstElement::transform(
  self : CstElement,
  on_token : (CstToken) -> R,
  on_node : (RawKind, Array[R]) -> R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) => {
      let results = Array::new(capacity=node.children.length())
      for child in node.children {
        results.push(child.transform(on_token, on_node))
      }
      on_node(node.kind, results)
    }
  }
}

///|
/// Monoid catamorphism — folds leaf results with `combine` without
/// allocating an intermediate `Array[R]`.
///
/// **Warning:** `empty` is shared by reference. Use only value-type
/// accumulators (Int, String). For Array collection, use `transform` instead.
pub fn[R] CstElement::fold(
  self : CstElement,
  on_token : (CstToken) -> R,
  combine : (R, R) -> R,
  empty : R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) =>
      for child in node.children; acc = empty {
        continue combine(acc, child.fold(on_token, combine, empty))
      } nobreak {
        acc
      }
  }
}
