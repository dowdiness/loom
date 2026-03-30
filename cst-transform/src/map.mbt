///|
/// Structure-preserving map: transforms a `GreenNode` into another `GreenNode`.
///
/// Applies `f` bottom-up: children are recursively mapped first, then `f` is
/// applied to the reconstructed node (leaf or branch with new children).
pub fn map(node : GreenNode, f : (GreenNode) -> GreenNode) -> GreenNode {
  match node {
    Leaf(_, _) => f(node)
    Branch(kind, children) => {
      let new_children = Array::new(capacity=children.length())
      for child in children {
        new_children.push(map(child, f))
      }
      f(Branch(kind, new_children))
    }
  }
}
