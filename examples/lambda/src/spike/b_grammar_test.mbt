test "B grammar smoke: let x = 1 parses with no diagnostics" {
  let grammar = build_b_syntax_grammar()
  let (_, diagnostics) = grammar.parse_cst("let x = 1")
  inspect(diagnostics.is_empty(), content="true")
}

test "B grammar smoke: two let definitions" {
  let grammar = build_b_syntax_grammar()
  let source = "let x = 1\nlet y = x + 2"
  let (_, diagnostics) = grammar.parse_cst(source)
  inspect(diagnostics.is_empty(), content="true")
}

test "B grammar smoke: integer literal atom" {
  let grammar = build_b_syntax_grammar()
  let (_, diagnostics) = grammar.parse_cst("42")
  inspect(diagnostics.is_empty(), content="true")
}

test "B grammar smoke: binary expression" {
  let grammar = build_b_syntax_grammar()
  let (_, diagnostics) = grammar.parse_cst("1 + 2 - 3")
  inspect(diagnostics.is_empty(), content="true")
}
