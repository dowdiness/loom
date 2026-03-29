///|
test "error recovery: trailing comma in object" {
  let (cst, diagnostics) = try! parse_cst("{\"a\": 1,}")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"a\": 1,}".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: trailing comma in array" {
  let (cst, diagnostics) = try! parse_cst("[1,]")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "[1,]".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing colon" {
  let (cst, diagnostics) = try! parse_cst("{\"key\" 42}")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"key\" 42}".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing closing brace" {
  let (cst, diagnostics) = try! parse_cst("{\"a\": 1")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"a\": 1".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: empty input" {
  let (cst, diagnostics) = try! parse_cst("")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end(), content="0")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing closing bracket" {
  let (cst, diagnostics) = try! parse_cst("[1, 2")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "[1, 2".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}
