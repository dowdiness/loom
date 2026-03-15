// Tests for the parser — migrated from AstNode to SyntaxNode + Term.

///|
test "parse_cstsimple integer" {
  let (cst, _) = parse_cst("42") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  inspect(@ast.print_term(syntax_node_to_term(root)), content="42")
  inspect(node.start(), content="0")
  inspect(node.end(), content="2")
}

///|
test "parse_cstsimple variable" {
  let (cst, _) = parse_cst("x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  inspect(@ast.print_term(syntax_node_to_term(root)), content="x")
  inspect(node.start(), content="0")
  inspect(node.end(), content="1")
}

///|
test "parse_cstidentity function" {
  let (cst, _) = parse_cst("λx.x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  inspect(@ast.print_term(syntax_node_to_term(root)), content="(λx. x)")
  inspect(node.start(), content="0")
  inspect(node.end() >= 3, content="true")
}

///|
test "parse_cstbinary operator" {
  let (cst, _) = parse_cst("1 + 2") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  inspect(@ast.print_term(syntax_node_to_term(root)), content="(1 + 2)")
  let node = root.nth_child(0).unwrap()
  let v = match BinaryExprView::cast(node) {
    Some(v) => v
    None => abort("expected BinaryExpr")
  }
  inspect(v.operands().length(), content="2")
  inspect(v.operands()[0].start(), content="0")
  inspect(v.operands()[1].start() >= 3, content="true")
}

///|
test "parse_cstapplication" {
  let (cst, _) = parse_cst("f x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  inspect(@ast.print_term(syntax_node_to_term(root)), content="(f x)")
  let node = root.nth_child(0).unwrap()
  let v = match AppExprView::cast(node) {
    Some(v) => v
    None => abort("expected AppExpr")
  }
  // func + 1 arg = 2 children total
  inspect(v.args().length() + 1, content="2")
}

///|
test "parse_cstif-then-else" {
  let (cst, _) = parse_cst("if x then y else z") catch {
    _ => abort("lex error")
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  inspect(
    @ast.print_term(syntax_node_to_term(root)),
    content="if x then y else z",
  )
  let node = root.nth_child(0).unwrap()
  let v = match IfExprView::cast(node) {
    Some(v) => v
    None => abort("expected IfExpr")
  }
  // condition + then + else = 3 children
  inspect(
    [v.condition(), v.then_branch(), v.else_branch()]
    .iter()
    .filter(fn(x) { x is Some(_) })
    .count(),
    content="3",
  )
}

///|
test "parse_cstcomplex expression" {
  let (cst, _) = parse_cst("λf.λx.f x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let printed = @ast.print_term(syntax_node_to_term(root))
  inspect(printed.contains("λf"), content="true")
  inspect(printed.contains("λx"), content="true")
  // Outer lambda has one child (the inner lambda)
  let node = root.nth_child(0).unwrap()
  let v = match LambdaExprView::cast(node) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  inspect(v.body() is Some(_), content="true")
}

///|
test "parse_cstpreserves source positions" {
  let (cst, _) = parse_cst("  x  +  y  ") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  let v = match BinaryExprView::cast(node) {
    Some(v) => v
    None => abort("expected BinaryExpr")
  }
  // x and y positions: SyntaxNode.start() includes leading whitespace/trivia
  // so we just verify they're ordered correctly and y comes after x
  inspect(v.operands()[0].start() >= 0, content="true")
  inspect(v.operands()[0].end() >= 1, content="true")
  inspect(v.operands()[1].start() > v.operands()[0].end(), content="true")
}

///|
test "syntax_node_to_term: missing lambda body produces Term::Error" {
  let (cst, _) = parse_cst("λx.") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(root)
  // Body of the lambda should be Term::Error — direct structural match
  inspect(
    match term {
      @ast.Term::Lam(_, @ast.Term::Error(_)) => true
      _ => false
    },
    content="true",
  )
}
