///|
/// Structure-preserving map: transforms a `GreenNode` into another `GreenNode`.
///
/// Applies `f` bottom-up: children are recursively mapped first, then `f` is
/// applied to the reconstructed node (leaf or branch with new children).
pub fn GreenNode::map(
  self : GreenNode,
  f : (GreenNode) -> GreenNode,
) -> GreenNode {
  match self {
    Leaf(_, _) => f(self)
    Branch(kind, children) => {
      let new_children = Array::new(capacity=children.length())
      for child in children {
        new_children.push(child.map(f))
      }
      f(Branch(kind, new_children))
    }
  }
}
