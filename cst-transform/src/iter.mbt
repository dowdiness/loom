///|
/// Depth-first pre-order iterator over all nodes in a `GreenNode` tree.
///
/// Yields each node (both leaves and branches) before descending into children.
/// Uses an explicit stack to produce one element per call to the returned thunk.
pub fn GreenNode::iter(self : GreenNode) -> Iter[GreenNode] {
  let stack : Array[GreenNode] = [self]
  Iter::new(() => {
    if stack.is_empty() {
      return None
    }
    let current = stack.pop().unwrap()
    match current {
      Branch(_, children) => {
        let mut i = children.length() - 1
        while i >= 0 {
          stack.push(children[i])
          i = i - 1
        }
      }
      Leaf(_, _) => ()
    }
    Some(current)
  })
}
