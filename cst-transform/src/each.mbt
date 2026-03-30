///|
/// Callback-based depth-first pre-order traversal.
///
/// Calls `f` for every node in the tree. Returns `true` if traversal completed,
/// `false` if `f` returned `false` to request early termination.
/// This avoids all overhead of `Iter` (no stack allocation, no closure wrapping).
pub fn GreenNode::each(self : GreenNode, f : (GreenNode) -> Bool) -> Bool {
  if not(f(self)) {
    return false
  }
  match self {
    Leaf(_, _) => true
    Branch(_, children) => {
      for child in children {
        if not(child.each(f)) {
          return false
        }
      }
      true
    }
  }
}
