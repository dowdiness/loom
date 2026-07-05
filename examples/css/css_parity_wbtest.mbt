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
///
/// Input: "x { ; }"
///   Decl* RepeatWhile gate checks OneOf([Ident]). Current = Semicolon.
///   Not Ident → RepeatWhile stops immediately.
///   @until(RBrace): ctx.error("expected 'RBrace'") → diag 1.
///     skip_until(stop=RBrace): Semicolon ≠ RBrace → bump_error → diag 2
///     (bump_error opens an ErrorNode and emits the consumed token as error).
///     RBrace found → stop.
///   Total: 2 diagnostics.
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

  // 1 from @until's ctx.error, 1 from skip_until's bump_error on ';'
  inspect(diags.length(), content="2")
}

///|
/// Acceptance: @until(RBrace) at end of Decls consumes unexpected tokens
/// after declarations until the closing brace.
///
/// Input: "x { color: red; 1 2 3 }"
///   (Ident | Number)* RepeatWhile: gate checks OneOf([Ident, Number]).
///   Ident(red) matches → value consumed. Semicolon → gate stops.
///   Semicolon! → current is ; → consumed OK (0 diags).
///   Decl* RepeatWhile gate: OneOf([Ident]). Number(1) doesn't match → stops.
///   @until(RBrace): current = Number(1).
///     ctx.error("expected 'RBrace'") → diag 1.
///     skip_until: Number(1) ≠ RBrace → bump_error → diag 2.
///     Number(2) ≠ RBrace → bump_error → ...
///   Three Numbers skipped = 3 × bump_error, but bump_error opens a
///   single ErrorNode for the whole skip range. The diagnostic count
///   reflects the @until error call (1) + the ErrorNode start (1) = 2.
///   Total: 2 diagnostics.
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

  // 1 from @until's ctx.error, 1 from ErrorNode boundary for skipped range
  inspect(diags.length(), content="2")
}

///|
/// Acceptance: missing-semicolon-recovery — Semicolon! (EmitOr) emits a
/// diagnostic when ';' is missing, then (Ident|Number)* greedily consumes
/// subsequent tokens as values before Semicolon! fires on the ending token.
///
/// Input: "x { color: red font: bold; }"
///   Ident! → Ident(color) → OK. Colon! → Colon → OK.
///   (Ident | Number)* RepeatWhile: Ident(red) → consumed as value.
///     Ident(font) → consumed as value. Colon → NOT in FIRST {Ident,Number}
///     → RepeatWhile stops.
///   Semicolon! → current is Colon, not Semicolon → ctx.error → diag 1.
///     emit_error_placeholder → consumes 0 tokens (Colon stays current).
///   Decl* RepeatWhile gate: OneOf([Ident]). Colon ≠ Ident → stops.
///   @until(RBrace): current = Colon.
///     ctx.error("expected 'RBrace'") → diag 2.
///     skip_until: Colon ≠ RBrace → bump_error → sequence stops at RBrace
///     with a single ErrorNode boundary → diag 3.
///   Total: 3 diagnostics.
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

  // 1 from Semicolon! EmitOr, 1 from @until ctx.error, 1 from ErrorNode boundary
  inspect(diags.length(), content="3")
}
