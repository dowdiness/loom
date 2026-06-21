///|
fn has_key(leaves : Array[@core.ProjectionLeaf], key : String) -> Bool {
  for l in leaves {
    if l.key == key {
      return true
    }
  }
  false
}

///|
test "project_lambda_leaves emits var and int leaves" {
  let source = "let x = 1\nlet y = x"
  let (cst, _) = @lambda.parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let leaves = project_lambda_leaves(syntax)
  inspect(has_key(leaves, "var:x"), content="true")
  inspect(has_key(leaves, "int:1"), content="true")
}
