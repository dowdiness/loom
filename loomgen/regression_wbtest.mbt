///|
/// End-to-end regression harness for the full loomgen pipeline.
///
/// Exercises the complete generation workflow (parse → registry → build kinds →
/// emit) against the combined token+term fixture and the canonical lambda seed.
/// This is NOT a unit test — individual functions have their own wbtests.
/// This catches regressions in the integrated pipeline: annotation parsing, kind
/// derivation, role classification, cross-enum collision detection, and emit
/// formatting all running together.
///
/// Typecheck + integration test verification is handled by
/// scripts/loomgen_regression_check.sh (runs moon check + moon test on the
/// regenerated lambda example).
///
/// CWD convention: run tests from the `loomgen/` package directory.
///   cd loomgen && moon test --target native
/// Fixture paths are relative to the package directory. The seed file is
/// referenced via `../` since the canonical syntax_kind.mbt lives in
/// examples/lambda/. The existing wbtests follow the same convention.

///|
fn read_regression_fixture(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => abort("cannot read " + path)
  }
}

///|
/// Run the full loomgen pipeline against the lambda fixture, seeded from the
/// canonical syntax_kind.mbt. Returns (token_impls_output, syntax_kind_output).
fn run_regression_pipeline() -> (String, String) {
  // Seed registry from canonical output for stable raw numbers
  let seed_src = read_regression_fixture(
    "../examples/lambda/syntax/syntax_kind.mbt",
  )
  let pairs = extract_raw_pairs(seed_src)
  let registry = RawKindRegistry::new()
  registry.seed(pairs)

  // Parse annotated enums
  let fixture = read_regression_fixture("fixtures/term_kind.mbt")
  let annotated = match parse_annotations(fixture) {
    Ok(a) => a
    Err(m) => abort("annotation parse failed: " + m)
  }
  let te = match annotated.token_enum {
    Some(e) => e
    None => abort("no #loom.token enum in fixture")
  }

  // Build kind entries
  let result = match build_kinds(te, registry, annotated.term_enum) {
    Ok(r) => r
    Err(_) => abort("build_kinds failed")
  }

  // Emit both outputs
  let token_impls = emit_token_impls(te, result.kinds)
  let syntax_kind = emit_syntax_kind(
    result.kinds,
    result.term_kinds,
    result.trivia_set,
    result.error_set,
    result.error_node_name,
    [],
  )
  (token_impls, syntax_kind)
}

///|
/// Show for the Error(String) variant must use the `msg` binding and produce
/// the `"<error: "` prefix for error message display.
test "regression: Show Error includes msg binding and error prefix" {
  let (token_impls, _) = run_regression_pipeline()
  // Pattern: `Error(msg) => "<error: " + msg + ">"`
  inspect(
    token_impls.contains("Error(msg) => \"<error: \" + msg + \">\""),
    content="true",
  )
}

///|
/// ToRawKind raw numbers must match the seeded canonical values from
/// examples/lambda/syntax/syntax_kind.mbt. Using classic regression guards:
/// - Whitespace => 11 (trivia)
/// - ErrorToken => 12 (error)
/// - EofToken => 13 (eof)
/// - FnKeyword => 43 (non-sequential outlier)
/// - IdentToken => 9 (ident)
/// - IntToken => 10 (literal with kind_override)
test "regression: ToRawKind matches seeded raw numbers for token_impls" {
  let (token_impls, _) = run_regression_pipeline()
  inspect(token_impls.contains("Whitespace => 11"), content="true")
  inspect(token_impls.contains("Error(_) => 12"), content="true")
  inspect(token_impls.contains("EOF => 13"), content="true")
  inspect(token_impls.contains("Fn => 43"), content="true")
  inspect(token_impls.contains("Identifier => 9"), content="true")
  inspect(token_impls.contains("Integer => 10"), content="true")
}

///|
/// ToRawKind raw numbers for SyntaxKind (combined token + term) must match.
test "regression: ToRawKind matches seeded raw numbers for syntax_kind" {
  let (_, syntax_kind) = run_regression_pipeline()
  // Token kinds
  inspect(syntax_kind.contains("FnKeyword => 43"), content="true")
  inspect(syntax_kind.contains("IntToken => 10"), content="true")
  inspect(syntax_kind.contains("ErrorToken => 12"), content="true")
  // Term kinds
  inspect(syntax_kind.contains("ErrorNode => 21"), content="true")
  inspect(syntax_kind.contains("LambdaExpr => 14"), content="true")
  inspect(syntax_kind.contains("SourceFile => 22"), content="true")
}

///|
/// IsTrivia on token_impls must return true ONLY for the trivia variant
/// (Whitespace) and false for everything else — especially Delimiter (Newline).
test "regression: IsTrivia true only for Whitespace in token_impls" {
  let (token_impls, _) = run_regression_pipeline()
  // Whitespace is trivia — must return true
  inspect(token_impls.contains("Whitespace => true"), content="true")
  // Everything else is false
  inspect(token_impls.contains("_ => false"), content="true")
  // Newline is a Delimiter (not Trivia) — must not match as trivia
  inspect(token_impls.contains("Newline => true"), content="false")
}

///|
/// IsTrivia on SyntaxKind must return true only for WhitespaceToken.
/// The fixture has exactly one trivia kind, so the generated form is the
/// single-line `self == WhitespaceToken` (not a multi-arm match).
test "regression: IsTrivia true only for WhitespaceToken in syntax_kind" {
  let (_, syntax_kind) = run_regression_pipeline()
  // Positive: WhitespaceToken is the trivia kind
  inspect(syntax_kind.contains("self == WhitespaceToken"), content="true")
  // Negative: NewlineToken is a Delimiter — must NOT be classified as trivia.
  // A regression producing `self == WhitespaceToken || self == NewlineToken`
  // would be caught by this assertion.
  inspect(syntax_kind.contains("self == NewlineToken"), content="false")
}

///|
/// IsError on SyntaxKind must return true only for ErrorToken.
test "regression: IsError true only for ErrorToken in syntax_kind" {
  let (_, syntax_kind) = run_regression_pipeline()
  // Positive: ErrorToken is classified as is_error
  inspect(syntax_kind.contains("self == ErrorToken"), content="true")
  // Negative: ErrorNode (a term variant) must NOT be classified as is_error.
  // A regression producing `self == ErrorToken || self == ErrorNode` would
  // cause this assertion to fail since `self == ErrorNode` only appears in
  // the IsError impl when ErrorNode is misclassified. It does not appear in
  // ToRawKind (`ErrorNode => 21`), FromRawKind (`_ => ErrorNode`), or the
  // enum declaration (bare `ErrorNode` by itself).
  inspect(syntax_kind.contains("self == ErrorNode"), content="false")
}

///|
/// FromRawKind fallback must use ErrorNode (the term error variant)
/// when the fixture has a #loom.errornode annotation.
test "regression: FromRawKind falls back to ErrorNode" {
  let (_, syntax_kind) = run_regression_pipeline()
  inspect(syntax_kind.contains("_ => ErrorNode"), content="true")
}

///|
/// Cross-enum collision check: no token kind name collides with a term kind name.
/// The fixture has 27 token kinds and 17 term kinds with disjoint names, so the
/// total SyntaxKind variant count should be 27 + 17 = 44.
test "regression: no token/term kind name collision" {
  let (_, syntax_kind) = run_regression_pipeline()
  // Every kind appears as a SyntaxKind variant (one per line between enum { and })
  // Count distinct `  Name` lines between the enum header and closing brace.
  // Conservative: verify both LambdaToken (first token) and LambdaExpr (first term)
  // appear, confirming both sets are present.
  inspect(syntax_kind.contains("  LambdaToken"), content="true")
  inspect(syntax_kind.contains("  LambdaExpr"), content="true")
  inspect(syntax_kind.contains("  ErrorNode"), content="true")
  inspect(syntax_kind.contains("  WhitespaceToken"), content="true")
  // Newline is a Delimiter in the token enum and has no term-level conflict
  inspect(syntax_kind.contains("  NewlineToken"), content="true")
}

///|
/// Construct an inline fixture with a deliberate token/term name collision
/// and verify build_kinds rejects it.
/// Token `A` (#loom.punct("a")) derives kind name `AToken`.
/// Term `AToken` (#loom.leaf) derives kind name `AToken` (leaf uses variant
/// name as-is). This collision must be caught by build_kinds.
test "regression: token/term kind name collision is rejected" {
  let src =
    #|#loom.token
    #|pub(all) enum CollidingToken {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum CollidingTerm {
    #|  #loom.root
    #|  Start
    #|  #loom.leaf
    #|  AToken
    #|} derive(Eq)
  let annotated = match parse_annotations(src) {
    Ok(a) => a
    Err(m) => abort("parse failed: " + m)
  }
  let te = match annotated.token_enum {
    Some(e) => e
    None => abort("no token enum")
  }
  let registry = RawKindRegistry::new()
  match build_kinds(te, registry, annotated.term_enum) {
    Err(_) => () // expected — token kind "AToken" conflicts with term "AToken"
    Ok(_) => abort("expected name collision error")
  }
}
