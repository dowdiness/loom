///|
/// Depth-first pre-order iterator over all nodes in a `GreenNode` tree.
///
/// Yields each node (both leaves and branches) before descending into children.
/// Uses an explicit stack to produce one element per call to the returned thunk.
pub fn iter(node : GreenNode) -> Iter[GreenNode] {
  let stack : Array[GreenNode] = [node]
  Iter::new(fn() {
    if stack.is_empty() {
      return None
    }
    let current = stack.pop().unwrap()
    match current {
      Branch(_, children) => {
        // Push children in reverse order so leftmost is popped first
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
