// ReactiveParser tests: correctness of the generic two-memo pipeline
// (Signal → CstStage → Ast) and parity with direct parse_cst_to_ast_node output.

// ── Step-based error recovery ────────────────────────────────────────────────

///|
/// "@invalid" no longer triggers LexError — step-based lexer recovers "@" as
/// an error token. is_lex_error is false because tokenization succeeded.
test "ReactiveParser: step-based lexer recovers invalid chars without lex error" {
  let db = @loom.new_reactive_parser("@invalid", @lambda.lambda_grammar)
  inspect(db.cst().is_lex_error, content="false")
}

///|
/// With step-based recovery, "@invalid" parses into a tree (with errors)
/// rather than routing through on_lex_error. The root should be the normal
/// grammar root, not ErrorNode.
test "ReactiveParser: step-based recovery produces parse tree not ErrorNode" {
  let db = @loom.new_reactive_parser("@invalid", @lambda.lambda_grammar)
  let kind = @syntax.SyntaxKind::from_raw(db.term().kind())
  // Should NOT be ErrorNode — the parser got tokens and produced a tree
  inspect(kind != @syntax.ErrorNode, content="true")
}

///|
/// Diagnostics from step-based recovery are parser-level (not "tokenization: ").
test "ReactiveParser: step-based recovery diagnostics are parser-level" {
  let db = @loom.new_reactive_parser("@invalid", @lambda.lambda_grammar)
  let diags = db.diagnostics()
  assert_eq(diags.length() > 0, true)
  // No "tokenization:" prefix — errors come from parser, not lexer
  inspect(diags[0].contains("tokenization: "), content="false")
}

// ── Parse-error path (lex succeeds, parser reports errors) ───────────────────

///|
test "ReactiveParser: parse error does not set is_lex_error" {
  let db = @loom.new_reactive_parser("λx.", @lambda.lambda_grammar)
  inspect(db.cst().is_lex_error, content="false")
}

///|
test "ReactiveParser: parse error produces non-empty diagnostics" {
  let db = @loom.new_reactive_parser("λx.", @lambda.lambda_grammar)
  assert_eq(db.diagnostics().length() > 0, true)
}

// ── Happy path ───────────────────────────────────────────────────────────────

///|
test "ReactiveParser: valid input - integer addition" {
  let db = @loom.new_reactive_parser("1 + 2", @lambda.lambda_grammar)
  inspect(@ast.print_term(syntax_node_to_term(db.term())), content="(1 + 2)")
}

///|
test "ReactiveParser: valid input - lambda expression" {
  let db = @loom.new_reactive_parser("λx.x", @lambda.lambda_grammar)
  match syntax_node_to_term(db.term()) {
    @ast.Term::Lam("x", _) => ()
    other => abort("expected Lam(x,...), got: " + other.to_string())
  }
}

///|
test "ReactiveParser: valid input - is_lex_error false" {
  let db = @loom.new_reactive_parser("λf.λx.f x", @lambda.lambda_grammar)
  inspect(db.cst().is_lex_error, content="false")
}

// ── Mutation ─────────────────────────────────────────────────────────────────

///|
test "ReactiveParser: set_source updates term" {
  let db = @loom.new_reactive_parser("1", @lambda.lambda_grammar)
  let t1 = db.term()
  db.set_source("2")
  let t2 = db.term()
  inspect(@ast.print_term(syntax_node_to_term(t1)), content="1")
  inspect(@ast.print_term(syntax_node_to_term(t2)), content="2")
}

///|
test "ReactiveParser: set_source same value preserves term (Eq)" {
  let source = "λf.λx.f x"
  let db = @loom.new_reactive_parser(source, @lambda.lambda_grammar)
  let t1 = db.term()
  db.set_source(source)
  let t2 = db.term()
  // SyntaxNode::Eq is structure-only; same source must produce equal trees
  assert_eq(t1, t2)
}

///|
test "ReactiveParser: set_source from error-recovery input to valid" {
  let db = @loom.new_reactive_parser("@invalid", @lambda.lambda_grammar)
  inspect(db.cst().is_lex_error, content="false")
  db.set_source("1 + 2")
  inspect(db.cst().is_lex_error, content="false")
}

// ── Parity with direct parse ──────────────────────────────────────────────────

///|
/// Cross-checks ReactiveParser (two-memo pipeline) against parse()
/// (direct, pipeline-free parse) on a set of valid inputs.
/// The pipeline must not change AST semantics vs the baseline parser.
/// Error-recovery inputs are tested separately via the lex/parse error path tests.
test "ReactiveParser: parity with parse" {
  let sources : Array[String] = [
    "λx.x      +                   1   ", "λx.x λy.y + x", "if true then 1 else 4",
    "λa.λb.λc. if c then a b else 124321 - 31 + a c", "10 - 3 + 1",
  ]
  for source in sources {
    let db = @loom.new_reactive_parser(source, @lambda.lambda_grammar)
    let direct = parse(source) catch {
      _ => abort("unexpected parse error in valid source: " + source)
    }
    inspect(
      @ast.print_term(syntax_node_to_term(db.term())),
      content=@ast.print_term(direct),
    )
  }
}

///|
/// SyntaxNode::Eq is structural (CstNode-based), not reference equality.
/// Two separately computed SyntaxNodes from the same source must be Eq-equal
/// even though they are produced by distinct Memo computations.
/// This verifies that the Memo's backdating mechanism correctly identifies
/// unchanged trees across computation epochs.
test "ReactiveParser: SyntaxNode Eq holds after round-trip source change" {
  let db = @loom.new_reactive_parser("λx.x", lambda_grammar)
  let t1 = db.term()
  db.set_source("y") // change to something different — triggers recomputation
  let _ = db.term() // force the new computation epoch
  db.set_source("λx.x") // change back — triggers another recomputation
  let t3 = db.term()
  // t1 and t3 are separately computed but from the same source:
  // same token sequence → same interned CstNode → SyntaxNode::Eq returns true
  inspect(t1 == t3, content="true")
}
