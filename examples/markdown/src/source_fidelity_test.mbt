///|
/// Collect the text of all leaf tokens in a CST (depth-first) via SyntaxNode.
fn collect_leaf_texts(node : @seam.SyntaxNode) -> String {
  let parts : Array[String] = []
  fn walk(n : @seam.SyntaxNode) -> Unit {
    for elem in n.all_children() {
      match elem {
        @seam.SyntaxElement::Token(t) => parts.push(t.text())
        @seam.SyntaxElement::Node(child) => walk(child)
      }
    }
  }

  walk(node)
  parts.join("")
}

///|
test "source fidelity: heading" {
  let source = "# Hello\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(collect_leaf_texts(syntax) == source, content="true")
}

///|
test "source fidelity: paragraph with bold" {
  let source = "Hello **bold** world\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(collect_leaf_texts(syntax) == source, content="true")
}

///|
test "source fidelity: code block" {
  let source = "```python\nx = 1\n```\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(collect_leaf_texts(syntax) == source, content="true")
}

///|
test "source fidelity: mixed document" {
  let source = "# Title\n\nText here\n\n- item one\n- item two\n\n```\ncode\n```\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(collect_leaf_texts(syntax) == source, content="true")
}
