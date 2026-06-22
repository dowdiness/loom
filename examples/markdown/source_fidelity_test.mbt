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
fn assert_source_fidelity(source : String) -> Unit raise {
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(collect_leaf_texts(syntax) == source, content="true")
}

///|
test "source fidelity: heading" {
  assert_source_fidelity("# Hello\n")
}

///|
test "source fidelity: paragraph with bold" {
  assert_source_fidelity("Hello **bold** world\n")
}

///|
test "source fidelity: code block" {
  assert_source_fidelity("```python\nx = 1\n```\n")
}

///|
test "source fidelity: mixed document" {
  assert_source_fidelity(
    "# Title\n\nText here\n\n- item one\n- item two\n\n```\ncode\n```\n",
  )
}

///|
test "source fidelity: list" {
  assert_source_fidelity("- one\n- two\n")
}

///|
test "source fidelity: link with balanced parentheses" {
  assert_source_fidelity("[wiki](page_(C).html)\n")
}
