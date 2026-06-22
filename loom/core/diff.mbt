///|
/// Walk two CST trees simultaneously, appending Edit records for changed regions.
/// Uses CstNode.hash as an O(1) skip key: equal hashes mean structurally
/// identical subtrees, skipping the subtree without recursion.
fn diff_nodes(
  old : @seam.CstNode,
  new : @seam.CstNode,
  old_pos : Int,
  result : Array[Edit],
) -> Unit {
  // Hash fast-path: equal hashes almost certainly mean structurally identical
  if old.hash == new.hash {
    return
  }
  // Kind or child-count mismatch: emit one Edit for the whole pair
  if old.kind != new.kind || old.children.length() != new.children.length() {
    result.push(Edit::new(old_pos, old.text_len, new.text_len))
    return
  }
  // Same kind and child count: walk children pairwise
  let mut pos = old_pos
  for i = 0; i < old.children.length(); i = i + 1 {
    let old_child = old.children[i]
    let new_child = new.children[i]
    match (old_child, new_child) {
      (@seam.CstElement::Node(o), @seam.CstElement::Node(n)) =>
        diff_nodes(o, n, pos, result)
      (@seam.CstElement::Token(o), @seam.CstElement::Token(n)) =>
        if o != n {
          result.push(Edit::new(pos, o.text_len(), n.text_len()))
        }
      _ =>
        // Node vs Token mismatch: emit one Edit
        result.push(Edit::new(pos, old_child.text_len(), new_child.text_len()))
    }
    pos = pos + old_child.text_len()
  }
}

///|
/// Compute Edit records describing what changed between two parse trees.
/// Uses CstNode.hash as a fast-path heuristic: equal hashes skip the subtree
/// (small collision risk; acceptable for CRDT merge verification).
///
/// Positions are in the old document coordinate space. An empty Array means
/// both trees are structurally identical (verified up to hash collisions).
/// Multiple edits require coordinate adjustment before sequential parser.edit()
/// calls — use tree_diff primarily for convergence checks (assert empty diff).
pub fn tree_diff(old : @seam.CstNode, new : @seam.CstNode) -> Array[Edit] {
  let result : Array[Edit] = []
  diff_nodes(old, new, 0, result)
  result
}
