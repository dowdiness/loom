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
///   @until(RBrace): Semicolon ≠ RBrace → ctx.error("expected 'RBrace'") → diag 1.
///     skip_until: consumes Semicolon inside ErrorNode (0 diags from tree structure).
///     RBrace found → stop.
///   Expect(RBrace) succeeds. Expect(EOF) succeeds with no diag (fixed: EOF not emitted).
///   Total: 1 diagnostic.
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

  // 1 from @until's ctx.error (skip_until's ErrorNode is structural, no diagnostic)
  inspect(diags.length(), content="1")
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
///     skip_until: consumes 3 Numbers inside ErrorNode (0 diags from structure).
///     RBrace found → stop.
///   Expect(EOF) succeeds with no diag (fixed: EOF not emitted).
///   Total: 1 diagnostic.
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

  // 1 from @until's ctx.error (skip_until's ErrorNode is structural, no diagnostic)
  inspect(diags.length(), content="1")
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
///     skip_until: consumes Colon+Semicolon inside ErrorNode (0 diags from structure).
///     RBrace found → stop.
///   Expect(EOF) succeeds with no diag (fixed: EOF not emitted).
///   Total: 2 diagnostics.
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

  // 1 from Semicolon! EmitOr, 1 from @until's ctx.error
  inspect(diags.length(), content="2")
}

///|
/// ── Demonstrable CSS parses ──
///
/// These tests show what real CSS-like input the parser handles.
/// All use `@grammar.interpret(css_grammar_ir)` from #loom.rule annotations.
///
/// What is NOT parseable (not token variants):
///   .class, #id, 10px, rgb(...), *, >, +, ~, @media, quotes, url()
///   — these need lexer patterns and grammar rules beyond the subset.
///
/// Each test reports (tokens, diagnostics) to show the parse outcome.

///|
/// Single rule, single declaration. All diagnostics eliminated:
/// @until spares RBrace (fixed #636), expect(EOF) is no-op (fixed).
/// div { color: red; } → 8 tokens, 0 diagnostics.
test "demo: single rule, single declaration" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)
  let tokens = [
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.Ident),
    tok(@token.Colon),
    tok(@token.Ident),
    tok(@token.Semicolon),
    tok(@token.RBrace),
    tok(@token.EOF),
  ]
  let (_tree, diags) = @core.parse_with(
    "div { color: red; }",
    spec,
    _source => tokens,
    parse,
  )
  inspect(tokens.length(), content="8")
  inspect(diags.is_empty(), content="true")
}

///|
/// Single rule, two declarations. All diagnostics eliminated:
/// @until spares RBrace (fixed #636), expect(EOF) is no-op (fixed).
/// div { color: red; margin: 0; } → 12 tokens, 0 diagnostics.
test "demo: single rule, two declarations" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)
  let tokens = [
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.Ident),
    tok(@token.Colon),
    tok(@token.Ident),
    tok(@token.Semicolon),
    tok(@token.Ident),
    tok(@token.Colon),
    tok(@token.Number),
    tok(@token.Semicolon),
    tok(@token.RBrace),
    tok(@token.EOF),
  ]
  let (_tree, diags) = @core.parse_with(
    "div { color: red; margin: 0; }",
    spec,
    _source => tokens,
    parse,
  )
  inspect(tokens.length(), content="12")
  inspect(diags.is_empty(), content="true")
}

///|
/// Two rules, one declaration each. All diagnostics eliminated:
/// @until spares both RBraces (fixed #636), expect(EOF) is no-op (fixed).
/// div { color: red; } span { margin: 0; } → 15 tokens, 0 diagnostics.
test "demo: two rules" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)
  let tokens = [
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.Ident),
    tok(@token.Colon),
    tok(@token.Ident),
    tok(@token.Semicolon),
    tok(@token.RBrace),
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.Ident),
    tok(@token.Colon),
    tok(@token.Number),
    tok(@token.Semicolon),
    tok(@token.RBrace),
    tok(@token.EOF),
  ]
  let (_tree, diags) = @core.parse_with(
    "div { color: red; } span { margin: 0; }",
    spec,
    _source => tokens,
    parse,
  )
  inspect(tokens.length(), content="15")
  inspect(diags.is_empty(), content="true")
}

///|
/// Empty rule body. All diagnostics eliminated:
/// @until spares RBrace (fixed #636), expect(EOF) is no-op (fixed).
/// div { } → 4 tokens, 0 diagnostics.
test "demo: empty rule body" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)
  let tokens = [
    tok(@token.Ident),
    tok(@token.LBrace),
    tok(@token.RBrace),
    tok(@token.EOF),
  ]
  let (_tree, diags) = @core.parse_with(
    "div { }",
    spec,
    _source => tokens,
    parse,
  )
  inspect(tokens.length(), content="4")
  inspect(diags.is_empty(), content="true")
}

///|
/// ── Real CSS source text parsing ──
///
/// A minimal hand-written lexer tokenizes actual CSS strings so we can
/// test the parser on source text rather than pre-built token arrays.
/// The lexer is NOT generated by loomgen — it's a hand-written demo helper
/// for the token subset (Ident, Number, : ; { }, Whitespace, Error, EOF).

///|
/// Minimal CSS lexer: tokenize source text into TokenInfo array.
/// Handles: identifiers, numbers, : ; { }, whitespace, error on other chars.
fn css_lex(source : String) -> Array[@core.TokenInfo[@token.Token]] {
  let toks : Array[@core.TokenInfo[@token.Token]] = []
  let mut i = 0
  let len = source.length()
  while i < len {
    let c = source[i]
    // Whitespace
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      let start = i
      i = i + 1
      while i < len {
        let n = source[i]
        if n == ' ' || n == '\t' || n == '\n' || n == '\r' {
          i = i + 1
        } else {
          break
        }
      }
      toks.push(@core.TokenInfo::new(@token.Whitespace, i - start))
    }
    // Digit -> Number
    if c >= '0' && c <= '9' {
      let start = i
      i = i + 1
      while i < len && source[i] >= '0' && source[i] <= '9' {
        i = i + 1
      }
      toks.push(@core.TokenInfo::new(@token.Number, i - start))
    }
    // Letter or underscore or hyphen -> Ident
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '-' {
      let start = i
      i = i + 1
      while i < len {
        let n = source[i]
        if (n >= 'a' && n <= 'z') ||
          (n >= 'A' && n <= 'Z') ||
          (n >= '0' && n <= '9') ||
          n == '_' ||
          n == '-' {
          i = i + 1
        } else {
          break
        }
      }
      toks.push(@core.TokenInfo::new(@token.Ident, i - start))
    }
    // Punctuators
    if c == ':' {
      i = i + 1
      toks.push(@core.TokenInfo::new(@token.Colon, 1))
    }
    if c == ';' {
      i = i + 1
      toks.push(@core.TokenInfo::new(@token.Semicolon, 1))
    }
    if c == '{' {
      i = i + 1
      toks.push(@core.TokenInfo::new(@token.LBrace, 1))
    }
    if c == '}' {
      i = i + 1
      toks.push(@core.TokenInfo::new(@token.RBrace, 1))
    }
    // Dot, hash, star — consume as error (not in grammar token set)
    if c == '.' || c == '#' || c == '*' || c == '>' || c == '+' || c == ',' {
      i = i + 1
      toks.push(@core.TokenInfo::new(@token.Error("Unexpected"), 1))
    }
    // Other unrecognized chars: advance by 1 to avoid infinite loop.
    // Reached only if NONE of the above matched.
    if !(c == ' ' || c == '\t' || c == '\n' || c == '\r') &&
      !(c >= '0' && c <= '9') &&
      !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '-') &&
      !(c == ':') &&
      !(c == ';') &&
      !(c == '{') &&
      !(c == '}') &&
      !(c == '.' || c == '#' || c == '*' || c == '>' || c == '+' || c == ',') {
      i = i + 1
      toks.push(@core.TokenInfo::new(@token.Error("Unexpected"), 1))
    }
  }
  toks.push(@core.TokenInfo::new(@token.EOF, 0))
  toks
}

///|
/// Real CSS: two rules with bare ident selectors (no . or #).
/// Both @until(RBrace) and expect(EOF) diagnostic sources are fixed.
/// body { color: red; margin: 0; }
/// h1   { font-size: 16; }
test "real-css: multi-rule style block" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)
  let source = "body { color: red; margin: 0; }\nh1 { font-size: 16; }"
  let toks = css_lex(source)
  let (_tree, diags) = @core.parse_with(source, spec, _source => toks, parse)
  inspect(diags.is_empty(), content="true")
}

///|
/// Real CSS: empty rule body. Both diagnostic sources fixed.
/// div { }
test "real-css: empty rule" {
  let parse = @grammar.interpret(css_grammar_ir)
  let spec = make_css_spec(parse)
  let source = "div { }"
  let toks = css_lex(source)
  let (_tree, diags) = @core.parse_with(source, spec, _source => toks, parse)
  inspect(diags.is_empty(), content="true")
}
