///|
// Helpers — build minimal CstNode trees for testing.
fn leaf(kind : Int, text : String) -> @seam.CstNode {
  let tok = @seam.CstToken::new(@seam.RawKind(kind), text)
  @seam.CstNode::new(@seam.RawKind(kind), [@seam.CstElement::Token(tok)])
}

///|
test "tree_diff: identical nodes — empty result" {
  let node = leaf(1, "x")
  let result = tree_diff(node, node)
  inspect(result.length(), content="0")
}

///|
test "tree_diff: same-kind same-count — leaf text change produces one Edit" {
  let old = leaf(1, "x")
  let new = leaf(1, "y")
  let result = tree_diff(old, new)
  inspect(result.length(), content="1")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="1")
  inspect(result[0].new_len, content="1")
}

///|
test "tree_diff: kind mismatch — whole-node Edit" {
  let old = leaf(1, "x")
  let new = leaf(2, "x")
  let result = tree_diff(old, new)
  inspect(result.length(), content="1")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="1")
  inspect(result[0].new_len, content="1")
}

///|
test "tree_diff: unchanged left child, changed right child" {
  // Build: Node(kind=10, [Node(kind=1,"a"), Node(kind=1,"b")])
  // vs     Node(kind=10, [Node(kind=1,"a"), Node(kind=1,"z")])
  let a = leaf(1, "a")
  let b_old = leaf(1, "b")
  let b_new = leaf(1, "z")
  let old_root = @seam.CstNode::new(@seam.RawKind(10), [
    @seam.CstElement::Node(a),
    @seam.CstElement::Node(b_old),
  ])
  let new_root = @seam.CstNode::new(@seam.RawKind(10), [
    @seam.CstElement::Node(a),
    @seam.CstElement::Node(b_new),
  ])
  let result = tree_diff(old_root, new_root)
  // Only the second child changed, starting at offset 1 (after "a")
  inspect(result.length(), content="1")
  inspect(result[0].start, content="1")
  inspect(result[0].old_len, content="1")
  inspect(result[0].new_len, content="1")
}
