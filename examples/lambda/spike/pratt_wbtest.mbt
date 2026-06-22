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

///|
/// A's `parse_binary_op` consumes soft newlines before a binary operator
/// (`consume_soft_newlines_before_binary_operator`, gated on an operator
/// following), so `let x = 1\n+ 2` is one BinaryExpr spanning the newline.
/// B's PrattBinary must match it for D2a parity.
test "pratt: binary spans a soft newline before the operator matching A" {
  let source = "let x = 1\n+ 2"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
