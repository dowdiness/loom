// Unified Parser[Ast] tests: correctness of the reactive surface
// (source → syntax_tree/ast/diagnostics Derived views) and parity with direct
// parse_cst_to_ast_node output. Covers both update paths: `set_source`
// (full reparse) and `apply_edit` (CST-node-level reuse).

// ── Step-based error recovery ────────────────────────────────────────────────

///|
/// "@invalid" no longer triggers a lex error — step-based lexer recovers "@"
/// as an error token. `syntax_tree()` is always the recovered tree because tokenization
/// recovered; the error surfaces through diagnostics.
test "Parser: step-based lexer recovers invalid chars without lex error" {
  let parser = @loom.new_parser("@invalid", @lambda.lambda_grammar)
  ignore(parser.syntax_tree().read_or_abort())
}

///|
/// With step-based recovery, "@invalid" parses into a tree with errors.
/// The Ast should not be a fatal-tokenization Term — the parser got tokens and
/// produced a tree.
test "Parser: step-based recovery produces parse tree not ErrorNode" {
  let parser = @loom.new_parser("@invalid", @lambda.lambda_grammar)
  let term = parser.ast().read_or_abort()
  inspect(
    match term {
      @ast.Term::Error(msg) => !msg.contains("lex error")
      _ => true
    },
    content="true",
  )
}

///|
/// Diagnostics from step-based recovery are not fatal tokenization errors.
test "Parser: step-based recovery diagnostics are not fatal lex errors" {
  let parser = @loom.new_parser("@invalid", @lambda.lambda_grammar)
  let diags = parser.diagnostics().read_or_abort().format()
  inspect(diags.length() > 0, content="true")
  // No "tokenization:" prefix — recovery produced a tree instead.
  inspect(diags[0].contains("tokenization: "), content="false")
}

// ── Parse-error path (lex succeeds, parser reports errors) ───────────────────

///|
test "Parser: parse error still publishes syntax_tree" {
  let parser = @loom.new_parser("λx.", @lambda.lambda_grammar)
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "Parser: parse error produces non-empty diagnostics" {
  let parser = @loom.new_parser("λx.", @lambda.lambda_grammar)
  assert_eq(parser.diagnostics().read_or_abort().length() > 0, true)
}

// ── Happy path ───────────────────────────────────────────────────────────────

///|
test "Parser: valid input - integer addition" {
  let parser = @loom.new_parser("1 + 2", @lambda.lambda_grammar)
  inspect(@ast.print_term(parser.ast().read_or_abort()), content="(1 + 2)")
}

///|
test "Parser: valid input - lambda expression" {
  let parser = @loom.new_parser("λx.x", @lambda.lambda_grammar)
  match parser.ast().read_or_abort() {
    @ast.Term::Lam("x", _) => ()
    other => abort("expected Lam(x,...), got: " + other.to_string())
  }
}

///|
test "Parser: valid input - syntax_tree exists" {
  let parser = @loom.new_parser("λf.λx.f x", @lambda.lambda_grammar)
  ignore(parser.syntax_tree().read_or_abort())
}

// ── Mutation: set_source ─────────────────────────────────────────────────────

///|
test "Parser: set_source updates ast" {
  let parser = @loom.new_parser("1", @lambda.lambda_grammar)
  let rt = parser.runtime()
  let t1 = parser.ast().read_or_abort()
  parser.set_source("2")
  let t2 = parser.ast().read_or_abort()
  inspect(@ast.print_term(t1), content="1")
  inspect(@ast.print_term(t2), content="2")
}

///|
test "Parser: set_source same value preserves ast (Eq)" {
  let source = "λf.λx.f x"
  let parser = @loom.new_parser(source, @lambda.lambda_grammar)
  let rt = parser.runtime()
  let t1 = parser.ast().read_or_abort()
  parser.set_source(source)
  let t2 = parser.ast().read_or_abort()
  // Term::Eq is structural; same source must produce equal trees even when
  // `set_source` short-circuits (no reparse) on identity.
  assert_eq(t1, t2)
}

///|
test "Parser: set_source from error-recovery input to valid" {
  let parser = @loom.new_parser("@invalid", @lambda.lambda_grammar)
  let rt = parser.runtime()
  ignore(parser.syntax_tree().read_or_abort())
  parser.set_source("1 + 2")
  ignore(parser.syntax_tree().read_or_abort())
  inspect(@ast.print_term(parser.ast().read_or_abort()), content="(1 + 2)")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
}

// ── Mutation: apply_edit ─────────────────────────────────────────────────────

///|
/// apply_edit is the CST-reuse path (engine.edit). End-to-end coverage that
/// an edit flows through all four published views in one batch.
test "Parser: apply_edit updates source, ast, diagnostics" {
  let parser = @loom.new_parser("1 + 2", @lambda.lambda_grammar)
  let rt = parser.runtime()
  inspect(@ast.print_term(parser.ast().read_or_abort()), content="(1 + 2)")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  // Replace "1 + 2" (length 5) with "3 + 4" (length 5).
  parser.apply_edit(@core.Edit::new(0, 5, 5), "3 + 4")
  inspect(parser.source().read_or_abort(), content="3 + 4")
  inspect(@ast.print_term(parser.ast().read_or_abort()), content="(3 + 4)")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
}

///|
/// apply_edit recovering from an error state — exercises the incremental
/// path even when the previous tree has error nodes.
test "Parser: apply_edit from error state to valid" {
  let parser = @loom.new_parser("λx.", @lambda.lambda_grammar)
  let rt = parser.runtime()
  assert_eq(parser.diagnostics().read_or_abort().length() > 0, true)
  // Append "x" — "λx." (length 3) → "λx.x" (edit appends one char at offset 3).
  parser.apply_edit(@core.Edit::new(3, 0, 1), "λx.x")
  inspect(parser.source().read_or_abort(), content="λx.x")
  match parser.ast().read_or_abort() {
    @ast.Term::Lam("x", _) => ()
    other => abort("expected Lam(x,...), got: " + other.to_string())
  }
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
}

// ── Parity with direct parse ──────────────────────────────────────────────────

///|
/// Cross-checks Parser[Ast] (reactive surface over the imperative engine)
/// against parse() (direct, pipeline-free parse) on a set of valid inputs.
/// The reactive layer must not change AST semantics vs the baseline parser.
/// Error-recovery inputs are tested separately via the lex/parse error tests.
test "Parser: parity with parse" {
  let sources : Array[String] = [
    "λx.x      +                   1   ", "λx.x λy.y + x", "if true then 1 else 4",
    "λa.λb.λc. if c then a b else 124321 - 31 + a c", "10 - 3 + 1",
  ]
  for source in sources {
    let parser = @loom.new_parser(source, @lambda.lambda_grammar)
    let direct = parse(source) catch {
      _ => abort("unexpected parse error in valid source: " + source)
    }
    inspect(
      @ast.print_term(parser.ast().read_or_abort()),
      content=@ast.print_term(direct),
    )
  }
}

///|
/// Term::Eq is structural (CstNode-based), not reference equality.
/// Two separately computed terms from the same source must be Eq-equal
/// even though they are produced by distinct computation epochs.
/// This verifies that Derived backdating + the node interner correctly
/// identify unchanged trees across computation epochs.
test "Parser: Term Eq holds after round-trip source change" {
  let parser = @loom.new_parser("λx.x", lambda_grammar)
  let rt = parser.runtime()
  let t1 = parser.ast().read_or_abort()
  parser.set_source("y") // change — triggers recomputation
  let _ = parser.ast().read_or_abort() // force the new computation epoch
  parser.set_source("λx.x") // change back — triggers another recomputation
  let t3 = parser.ast().read_or_abort()
  // t1 and t3 are separately computed but from the same source:
  // same token sequence → same interned CstNode → Term::Eq returns true.
  inspect(t1 == t3, content="true")
}
