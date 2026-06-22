// Error-recovery CST parity against A, driven by the reified lambda grammar.
// The bespoke `error_recovery_grammar` is gone; these exercise the atom-rule
// `ErrorUntil` residue (missing-RHS / incomplete-binary recovery) the probe
// reproduces from A's parse_atom `_` fallthrough.

///|
test "task7: missing name 'let = 1' CST matches A" {
  let source = "let = 1"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task7: missing value 'let x =' CST matches A" {
  let source = "let x ="
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task7: incomplete binary 'let x = 1 +' CST matches A" {
  let source = "let x = 1 +"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
