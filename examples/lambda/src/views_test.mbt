///|
// Tests for typed SyntaxNode view types.

///|
test "LambdaExprView::cast returns Some for LambdaExpr nodes" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  // SourceFile wraps LambdaExpr; find the LambdaExpr child
  let lambda_child = syn.children()[0]
  inspect(LambdaExprView::cast(lambda_child) is Some(_), content="true")
}

///|
test "LambdaExprView::cast returns None for non-lambda nodes" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let int_child = syn.children()[0]
  inspect(LambdaExprView::cast(int_child) is None, content="true")
}

///|
test "LambdaExprView::param returns bound name" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LambdaExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  inspect(view.param(), content="x")
}

///|
test "LambdaExprView::body returns Some for well-formed lambda" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LambdaExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  inspect(view.body() is Some(_), content="true")
}

///|
test "IntLiteralView::value returns parsed integer" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match IntLiteralView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected IntLiteral")
  }
  inspect(view.value(), content="Some(42)")
}

///|
test "VarRefView::name returns identifier text" {
  let (cst, _) = parse_cst_recover("myVar") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match VarRefView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected VarRef")
  }
  inspect(view.name(), content="myVar")
}

///|
test "AppExprView::cast returns Some for application" {
  let (cst, _) = parse_cst_recover("f x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match AppExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected AppExpr")
  }
  inspect(view.func() is Some(_), content="true")
  inspect(view.arg() is Some(_), content="true")
}

///|
test "LetExprView::name returns binding name" {
  let (cst, _) = parse_cst_recover("let x = 1 in x") catch {
    _ => abort("lex error")
  }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LetExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LetExpr")
  }
  inspect(view.name(), content="x")
}

///|
test "SyntaxNode::to_json produces valid JSON string" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let j = syn.to_json()
  let s = j.to_string()
  inspect(s.contains("\"kind\""), content="true")
}

///|
test "LambdaExprView::to_json includes param and body keys" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LambdaExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  let s = view.to_json().to_string()
  inspect(s.contains("\"param\""), content="true")
  inspect(s.contains("\"body\""), content="true")
}
