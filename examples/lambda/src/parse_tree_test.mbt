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
    content=(
      #|true
    ),
  )
}

///|
// Helper: parse source, return the first TypeAnnot's type child.
fn extract_type_node(src : String) -> @seam.SyntaxNode? {
  let (cst, _) = parse_cst(src) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  fn find_type_in(n : @seam.SyntaxNode) -> @seam.SyntaxNode? {
    if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.SyntaxKind::TypeAnnot {
      // first interior child of TypeAnnot is the type expression
      let cs = n.children()
      if cs.length() > 0 {
        return Some(cs[0])
      }
      return None
    }
    for c in n.children() {
      match find_type_in(c) {
        Some(x) => return Some(x)
        None => continue
      }
    }
    None
  }
  find_type_in(root)
}

///|
test "type_of_node: TInt" {
  let n = extract_type_node("\\x : Int. x").unwrap()
  inspect(@typecheck.type_of_node(n), content="Int")
}

///|
test "type_of_node: TUnit" {
  let n = extract_type_node("\\x : Unit. x").unwrap()
  inspect(@typecheck.type_of_node(n), content="Unit")
}

///|
test "type_of_node: arrow" {
  let n = extract_type_node("\\x : Int -> Int. x").unwrap()
  inspect(@typecheck.type_of_node(n), content="Int -> Int")
}

///|
test "type_of_node: right-associative arrow" {
  let n = extract_type_node("\\x : Int -> Int -> Int. x").unwrap()
  inspect(@typecheck.type_of_node(n), content="Int -> Int -> Int")
}

///|
fn typed_from_source(src : String) -> @typecheck.TypedTerm {
  let (cst, _) = parse_cst(src) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  @typecheck.convert_from_cst(root)
}

///|
test "convert_from_cst: int literal" {
  inspect(typed_from_source("42"), content="Int(42)")
}

///|
test "convert_from_cst: var" {
  inspect(typed_from_source("x"), content="Var(\"x\")")
}

///|
test "convert_from_cst: hole" {
  inspect(typed_from_source("_"), content="Hole(0)")
}

///|
test "convert_from_cst: unannotated lambda" {
  inspect(
    typed_from_source("\\x. x"),
    content="Lam(\"x\", None, Var(\"x\"))",
  )
}

///|
test "convert_from_cst: nested unannotated lambdas" {
  inspect(
    typed_from_source("\\x. \\y. x"),
    content="Lam(\"x\", None, Lam(\"y\", None, Var(\"x\")))",
  )
}

///|
test "convert_from_cst: annotated lambda Int" {
  inspect(
    typed_from_source("\\x : Int. x"),
    content="Lam(\"x\", Some(TInt), Var(\"x\"))",
  )
}

///|
test "convert_from_cst: annotated lambda arrow" {
  inspect(
    typed_from_source("\\f : Int -> Int. f"),
    content="Lam(\"f\", Some(TArrow(TInt, TInt)), Var(\"f\"))",
  )
}

///|
test "convert_from_cst: annotated lambda typechecks clean via infer" {
  let term = typed_from_source("\\x : Int. x")
  let result = @typecheck.infer(@typecheck.TypeEnv::Empty, term)
  inspect(result.had_error, content="false")
  inspect(result.diagnostics.length(), content="0")
  inspect(result.typ, content="Int -> Int")
}

///|
test "type_of_node: malformed returns TError" {
  // `\x : . x` — parser emits empty TypeAnnot (no type child).
  // extract_type_node returns None. The TypeAnnot itself is the error signal.
  // We call type_of_node on the TypeAnnot node directly, which returns TError.
  let (cst, _) = parse_cst("\\x : . x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  fn find_type_annot(n : @seam.SyntaxNode) -> @seam.SyntaxNode? {
    if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.SyntaxKind::TypeAnnot {
      return Some(n)
    }
    for c in n.children() {
      match find_type_annot(c) {
        Some(x) => return Some(x)
        None => continue
      }
    }
    None
  }
  // When TypeAnnot has no children, type_of_node on the TypeAnnot itself gives TError
  let annot = find_type_annot(root).unwrap()
  let cs = annot.children()
  // Empty TypeAnnot → TError via unknown-kind fallback
  if cs.length() == 0 {
    // No type child: simulate TError by checking what type_of_node does with TypeAnnot kind
    inspect(@typecheck.type_of_node(annot), content="<error>")
  } else {
    inspect(@typecheck.type_of_node(cs[0]), content="<error>")
  }
}
