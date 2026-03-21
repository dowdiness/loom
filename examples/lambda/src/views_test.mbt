///|
// Tests for typed SyntaxNode view types.

///|
test "LambdaExprView::cast returns Some for LambdaExpr nodes" {
  let (cst, _) = parse_cst("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  // SourceFile wraps LambdaExpr; find the LambdaExpr child
  let lambda_child = syn.children()[0]
  inspect(LambdaExprView::cast(lambda_child) is Some(_), content="true")
}

///|
test "LambdaExprView::cast returns None for non-lambda nodes" {
  let (cst, _) = parse_cst("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let int_child = syn.children()[0]
  inspect(LambdaExprView::cast(int_child) is None, content="true")
}

///|
test "LambdaExprView::param returns bound name" {
  let (cst, _) = parse_cst("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LambdaExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  inspect(view.param(), content="x")
}

///|
test "LambdaExprView::body returns Some for well-formed lambda" {
  let (cst, _) = parse_cst("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LambdaExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  inspect(view.body() is Some(_), content="true")
}

///|
test "IntLiteralView::value returns parsed integer" {
  let (cst, _) = parse_cst("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match IntLiteralView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected IntLiteral")
  }
  inspect(view.value(), content="Some(42)")
}

///|
test "VarRefView::name returns identifier text" {
  let (cst, _) = parse_cst("myVar") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match VarRefView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected VarRef")
  }
  inspect(view.name(), content="myVar")
}

///|
test "AppExprView::cast returns Some for application" {
  let (cst, _) = parse_cst("f x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match AppExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected AppExpr")
  }
  inspect(view.func() is Some(_), content="true")
  inspect(view.arg() is Some(_), content="true")
}

///|
/// AppExprView::args returns all arguments for chained application `f x y z`.
/// The grammar produces a flat AppExpr with N node-children; args() must
/// expose all of them, not just the first.
test "AppExprView::args returns all args for chained application" {
  let (cst, _) = parse_cst("f x y z") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match AppExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected AppExpr")
  }
  // 3 args: x, y, z
  inspect(view.args().length(), content="3")
}

///|
/// BinaryExprView::operands and ops return the full flat sequence for `a + b - c`.
test "BinaryExprView::operands and ops return full flat sequence" {
  let (cst, _) = parse_cst("a + b - c") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match BinaryExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected BinaryExpr")
  }
  inspect(view.operands().length(), content="3")
  inspect(view.ops().length(), content="2")
}

///|
test "LetDefView::name returns binding name" {
  let (cst, _) = parse_cst("let x = 1\nx") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LetDefView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LetDef")
  }
  inspect(view.name(), content="x")
}

///|
test "SyntaxNode::to_json produces valid JSON string" {
  let (cst, _) = parse_cst("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let j = syn.to_json()
  let s = j.to_string()
  inspect(s.contains("\"kind\""), content="true")
}

///|
test "LambdaExprView::to_json includes param and body keys" {
  let (cst, _) = parse_cst("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = match LambdaExprView::cast(syn.children()[0]) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  let s = view.to_json().to_string()
  inspect(s.contains("\"param\""), content="true")
  inspect(s.contains("\"body\""), content="true")
}

///|
test "LetDefView with params" {
  let (cst, _) = parse_cst("let f(x, y) = x + y") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let let_defs = tree
    .children()
    .filter(child =>
      @syntax.SyntaxKind::from_raw(child.kind()) == @syntax.LetDef
    )
  let def = LetDefView::cast(let_defs[0]).unwrap()
  inspect(def.name(), content="f")
  inspect(not(def.params().is_empty()), content="true")
  inspect(
    def.init().map(fn(n) { @syntax.SyntaxKind::from_raw(n.kind()) }),
    content="Some(BinaryExpr)",
  )
}

///|
test "LetDefView without params unchanged" {
  let (cst, _) = parse_cst("let x = 42") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let let_defs = tree
    .children()
    .filter(child =>
      @syntax.SyntaxKind::from_raw(child.kind()) == @syntax.LetDef
    )
  let def = LetDefView::cast(let_defs[0]).unwrap()
  inspect(def.name(), content="x")
  inspect(def.params().is_empty(), content="true")
  inspect(
    def.init().map(fn(n) { @syntax.SyntaxKind::from_raw(n.kind()) }),
    content="Some(IntLiteral)",
  )
}

///|
test "syntax_node_to_term: integer" {
  let (cst, _) = parse_cst("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(syn)
  inspect(
    term,
    content=(
      #|Int(42)
    ),
  )
}

///|
test "syntax_node_to_term: lambda" {
  let (cst, _) = parse_cst("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(syn)
  inspect(
    term,
    content=(
      #|Lam("x", Var("x"))
    ),
  )
}

///|
test "syntax_node_to_term: let binding" {
  let (cst, _) = parse_cst("let x = 1\nx") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(syn)
  inspect(
    term,
    content=(
      #|Module([("x", Int(1))], Var("x"))
    ),
  )
}
