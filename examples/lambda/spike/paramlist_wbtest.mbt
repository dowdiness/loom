// Parameter-list CST parity against A, driven by the reified lambda grammar.
// The bespoke `fn_grammar` is gone; these exercise the `WrapIfNext` + comma-loop
// reduction of the old ManualParamList hatch (single/two params, trailing comma).

///|
fn paramlist_source_id() -> @core.SourceId {
  @core.SourceId::SourceId("lambda-spike-paramlist")
}

///|
test "task6: fn with single param matches A" {
  let source = "fn f(x) { 1 }"
  let (a_cst, _) = @lambda.parse_cst(paramlist_source_id(), source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(paramlist_source_id(), source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task6: fn with two params matches A" {
  let source = "fn f(x, y) { 1 }"
  let (a_cst, _) = @lambda.parse_cst(paramlist_source_id(), source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(paramlist_source_id(), source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task6: fn with trailing comma matches A CST (error in both)" {
  let source = "fn f(x,) { 1 }"
  let (a_cst, a_diag) = @lambda.parse_cst(paramlist_source_id(), source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, b_diag) = b_grammar.parse_cst(paramlist_source_id(), source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
  // Both parsers should emit a "Trailing comma" diagnostic
  inspect(a_diag.items().length() > 0, content="true")
  inspect(b_diag.items().length() > 0, content="true")
}
