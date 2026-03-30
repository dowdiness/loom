///|
/// Callback-based depth-first pre-order traversal.
///
/// Calls `f` for every node in the tree. Returns `true` if traversal completed,
/// `false` if `f` returned `false` to request early termination.
/// This avoids all overhead of `Iter` (no stack allocation, no closure wrapping).
pub fn each(node : GreenNode, f : (GreenNode) -> Bool) -> Bool {
  if not(f(node)) {
    return false
  }
  match node {
    Leaf(_, _) => true
    Branch(_, children) => {
      for child in children {
        if not(each(child, f)) {
          return false
        }
      }
      true
    }
  }
}
