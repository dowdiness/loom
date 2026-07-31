///|
fn b_grammar_test_source_id() -> @core.SourceId {
  @core.SourceId::SourceId("lambda-spike-b-grammar-test")
}

///|
test "B grammar smoke: let x = 1 parses with no diagnostics" {
  let grammar = build_b_syntax_grammar()
  let (_, diagnostics) = grammar.parse_cst(
    b_grammar_test_source_id(),
    "let x = 1",
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "B grammar smoke: two let definitions" {
  let grammar = build_b_syntax_grammar()
  let source = "let x = 1\nlet y = x + 2"
  let (_, diagnostics) = grammar.parse_cst(b_grammar_test_source_id(), source)
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "B grammar smoke: integer literal atom" {
  let grammar = build_b_syntax_grammar()
  let (_, diagnostics) = grammar.parse_cst(b_grammar_test_source_id(), "42")
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "B grammar smoke: binary expression" {
  let grammar = build_b_syntax_grammar()
  let (_, diagnostics) = grammar.parse_cst(
    b_grammar_test_source_id(),
    "1 + 2 - 3",
  )
  inspect(diagnostics.is_empty(), content="true")
}
