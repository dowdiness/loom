// Pratt application/binary parity against A, driven by the reified lambda
// grammar (`build_b_syntax_grammar`). The bespoke `minimal_expr_ir` is gone;
// the full grammar parses a bare top-level expression through the same
// PrattApp/PrattBinary rules, so the CST parity assertion is unchanged.

///|
test "pratt: application produces AppExpr matching A" {
  let source = "f y"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "pratt: binary produces BinaryExpr matching A" {
  let source = "a + b - c"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
