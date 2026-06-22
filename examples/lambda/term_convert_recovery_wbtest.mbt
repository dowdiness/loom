// Tests that parse recovery produces Error terms instead of silently
// coercing malformed input to Int(0) or fabricating a Plus operator.

///|
test "recovery: int literal overflow yields Error term" {
  // parse_int overflows on 20+ digit integers, so IntLiteralView::value
  // returns None. Recovery should emit Error, not Int(0).
  let (cst, _) = parse_cst("99999999999999999999") catch {
    _ => abort("lex error")
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(root)
  match term {
    @ast.Term::Error(msg) => inspect(msg, content="invalid integer literal")
    other => fail("expected Error term, got \{other}")
  }
}

///|
test "recovery: valid int literal still produces Int" {
  let (cst, _) = parse_cst("42") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax_node_to_term(root), content="Int(42)")
}
