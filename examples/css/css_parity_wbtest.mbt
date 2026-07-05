///|
/// Acceptance tests: exercise ~ (Emit), ! (EmitOr), @until (ErrorUntil) in
/// realistic CSS declaration-list scenarios. All use the loomgen-generated
/// GrammarIr from #loom.rule annotations.

///|
/// Create a TokenInfo for a given token with placeholder length 1.
fn tok(t : @token.Token) -> @core.TokenInfo[@token.Token] {
  @core.TokenInfo::new(
    t,
    match t {
      @token.EOF => 0
      _ => 1
    },
  )
}

///|
/// Acceptance: Ident! (EmitOr) at start of declaration recovers a missing
/// property name, and Colon! recovers a missing colon, producing appropriate
/// diagnostics without aborting the parse.
test "acceptance: missing-property-name recovers via EmitOr" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)

  let tokens = [
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.Semicolon),
    tok(@token.RBrace),
    tok(@token.EOF),
  ]

  let (_tree, diags) = @core.parse_with(
    "x { ; }",
    spec,
    _source => tokens,
    parse,
  )

  // Parse completes without crash — Ident! and Colon! produce placeholder
  // tokens instead of aborting.
  inspect(diags.length() > 0, content="true")
}

///|
/// Acceptance: @until(RBrace) at end of Decls consumes unexpected tokens
/// after declarations until the closing brace.
test "acceptance: @until recovers from garbage after declarations" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)

  let tokens = [
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.Ident), // color
    tok(@token.Colon),
    tok(@token.Ident), // red
    tok(@token.Semicolon),
    tok(@token.Number),
    tok(@token.Number),
    tok(@token.Number),
    tok(@token.RBrace),
    tok(@token.EOF),
  ]

  let (_tree, diags) = @core.parse_with(
    "x { color: red; 1 2 3 }",
    spec,
    _source => tokens,
    parse,
  )

  inspect(diags.length() > 0, content="true")
}

///|
/// Acceptance: missing-semicolon-recovery — Semicolon! (EmitOr) emits a
/// diagnostic when ';' is missing, then (Ident|Number)* greedily consumes
/// subsequent tokens as values before Semicolon! fires on the ending token.
test "acceptance: missing-semicolon-recovery continues to next declaration" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)

  let tokens = [
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.Ident), // color
    tok(@token.Colon),
    tok(@token.Ident), // red
    tok(@token.Ident), // font (consumed as value)
    tok(@token.Colon), // consumed as value
    tok(@token.Ident), // bold (consumed as value)
    tok(@token.Semicolon),
    tok(@token.RBrace),
    tok(@token.EOF),
  ]

  let (_tree, diags) = @core.parse_with(
    "x { color: red font: bold; }",
    spec,
    _source => tokens,
    parse,
  )

  // Parse completes — Semicolon! recovers via EmitOr placeholder.
  inspect(diags.length() > 0, content="true")
}
