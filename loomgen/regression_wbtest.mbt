///|
/// End-to-end regression harness for the full loomgen pipeline.
///
/// Exercises the complete generation workflow (parse → registry → build kinds →
/// emit) against the lambda example's token and term kind sources (split into
/// separate files per issue #563). This is NOT a unit test — individual functions
/// have their own wbtests. This catches regressions in the integrated pipeline:
/// annotation parsing, kind derivation, role classification, cross-enum collision
/// detection, and emit formatting all running together.
///
/// Typecheck + integration test verification (regenerate lambda from source,
/// run moon check + moon test) is handled by scripts/loomgen_regression_check.sh
/// in the canopy monorepo (parent repository, not the loom submodule).
///

///|
/// Read a fixture file, trying an alternate path when the primary doesn't
/// resolve (supports running from both `loomgen/` and workspace root `loom/`).
fn read_fallback_fixture(path : String, alt : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ =>
      @fs.read_file_to_string(alt) catch {
        _ => abort("cannot read " + path + " nor " + alt)
      }
  }
}

///|
fn run_regression_pipeline() -> (String, String) {
  // Seed registry from canonical output for stable raw numbers
  let seed_src = read_fallback_fixture(
    "../examples/lambda/syntax/syntax_kind.mbt", "examples/lambda/syntax/syntax_kind.mbt",
  )
  let pairs = extract_raw_pairs(seed_src)
  let registry = RawKindRegistry::new()
  registry.seed(pairs)

  // Parse token and term enums from their separate source files
  let token_src = read_fallback_fixture(
    "../examples/lambda/token/token.mbt", "examples/lambda/token/token.mbt",
  )
  let term_src = read_fallback_fixture(
    "../examples/lambda/meta/term_kind.mbt", "examples/lambda/meta/term_kind.mbt",
  )
  let annotated_token = match parse_annotations(token_src) {
    Ok(a) => a
    Err(m) => abort("token annotation parse failed: " + m)
  }
  let annotated_term = match parse_annotations(term_src) {
    Ok(a) => a
    Err(m) => abort("term annotation parse failed: " + m)
  }
  // Reject #loom.token in the term file (mirrors load_term_enum validation, main.mbt:598)
  if annotated_term.token_enum is Some(_) {
    abort("term file must not contain a #loom.token enum")
  }
  let te = match annotated_token.token_enum {
    Some(e) => e
    None => abort("no #loom.token enum in token.mbt")
  }
  let term_enum = match annotated_term.term_enum {
    Some(e) => e
    None => abort("no #loom.term enum in term_kind.mbt")
  }

  // Build kind entries
  let result = match build_kinds(te, registry, Some(term_enum)) {
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

///|
/// When an annotation has invalid arguments (e.g. `#loom.literal(42)` with an
/// integer instead of a string), the error must say "invalid arguments" not
/// "missing a #loom.* annotation".
test "invalid annotation arguments produce specific error" {
  let src =
    #|#loom.token
    #|pub(all) enum BadAnnotationToken {
    #|  #loom.literal(42)
    #|  BadArg
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
  match parse_annotations(src) {
    Err(msg) if msg.contains("invalid arguments") => () // expected
    Err(msg) => abort("unexpected error: " + msg)
    Ok(_) => abort("expected error for invalid annotation args")
  }
}

///|
/// `emit_lexer_skeleton` with the three modes from the lexmode fixture must
/// produce the expected skeleton output. Mode order must match `LexMode` enum
/// output: Leaf, Inline, LineStart.
test "emit_lexer_skeleton produces correct dispatch skeleton" {
  let modes : Array[String] = ["Leaf", "Inline", "LineStart"]
  let output = emit_lexer_skeleton(modes, "Token", "@core")
  inspect(
    output,
    content=read_fallback_fixture(
      "fixtures/lexer_skeleton_fixture.g.mbt", "loomgen/fixtures/lexer_skeleton_fixture.g.mbt",
    ),
  )
}

///|
test "emit_lexer_skeleton_with_line_delegates delegates line modes, stubs others" {
  // Inline is not a line mode, so it keeps the aborting stub; LineStart
  // delegates to the generated helper.
  let output = emit_lexer_skeleton_with_line_delegates(
    ["Inline", "LineStart"],
    ["LineStart"],
    "Token",
    "@core",
  )
  inspect(
    output.contains("generated_lex_line_start(source, pos)"),
    content="true",
  )
  inspect(
    output.contains("abort(\"lex_inline not implemented\")"),
    content="true",
  )
  inspect(
    output.contains("abort(\"lex_line_start not implemented\")"),
    content="false",
  )
}

///|
test "integrate_line_lexer_skeleton migrates only exact stubs and is idempotent" {
  // Base skeleton with the exact historical aborting stubs for Inline and
  // LineStart.
  let base = emit_lexer_skeleton(["Inline", "LineStart"], "Token", "@core")
  // Replace the exact lex_inline stub with a handwritten custom body.
  let custom_inline = "fn lex_inline(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
    "  // user override\n" +
    "  lex_inline_custom(source, pos)\n" +
    "}"
  let existing = base.replace(
    old="fn lex_inline(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n  abort(\"lex_inline not implemented\")\n}",
    new=custom_inline,
  )
  inspect(existing.contains("// user override"), content="true")
  inspect(
    existing.contains("abort(\"lex_line_start not implemented\")"),
    content="true",
  )
  // Only the exact LineStart stub is migrated; the custom lex_inline is preserved.
  let migrated = integrate_line_lexer_skeleton(
    existing,
    ["LineStart"],
    "Token",
    "@core",
  )
  inspect(
    migrated.contains("generated_lex_line_start(source, pos)"),
    content="true",
  )
  inspect(
    migrated.contains("abort(\"lex_line_start not implemented\")"),
    content="false",
  )
  inspect(migrated.contains("// user override"), content="true")
  inspect(
    migrated.contains("generated_lex_inline(source, pos)"),
    content="false",
  )

  // `String::replace` is first-occurrence-only and each unique mode's stub
  // appears once, so migration applies the delegate exactly once per mode.
  inspect(
    migrated.split("generated_lex_line_start(source, pos)").length() - 1,
    content="1",
  )
  // A second pass must be a no-op (deterministic, idempotent).
  let migrated2 = integrate_line_lexer_skeleton(
    migrated,
    ["LineStart"],
    "Token",
    "@core",
  )
  inspect(migrated2 == migrated, content="true")
}

///|
test "integrate_line_lexer_skeleton preserves custom requested line-mode body" {
  // A requested line mode whose skeleton function is a handwritten
  // (non-canonical) override must stay byte-for-byte identical: the exact stub
  // is absent, so no delegate is written for it.
  let base = emit_lexer_skeleton(["Inline", "LineStart"], "Token", "@core")
  let custom_line_start = "fn lex_line_start(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
    "  // user override for line start\n" +
    "  lex_line_start_custom(source, pos)\n" +
    "}"
  let existing = base.replace(
    old="fn lex_line_start(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n  abort(\"lex_line_start not implemented\")\n}",
    new=custom_line_start,
  )
  let ls_before = existing.find("fn lex_line_start")
  guard ls_before is Some(s) else {
    fail("expected lex_line_start in existing")
  }
  let block_before = extract_fn_block(existing, s)
  let migrated = integrate_line_lexer_skeleton(
    existing,
    ["LineStart"],
    "Token",
    "@core",
  )
  let ls_after = migrated.find("fn lex_line_start")
  guard ls_after is Some(t) else { fail("expected lex_line_start in migrated") }
  let block_after = extract_fn_block(migrated, t)
  // The custom requested-mode function is preserved byte-for-byte.
  inspect(block_before == block_after, content="true")
  inspect(migrated.contains("generated_lex_line_start"), content="false")
}

///|
test "property: line skeleton migration is exact, idempotent, and order-independent" {
  let seeds : Array[Int] = @quickcheck.samples(96)
  for seed in seeds {
    let suffix = seed.to_string().replace(old="-", new="neg")
    let line_mode = "LineMode" + suffix
    let other_mode = "InlineMode" + suffix
    let modes = [line_mode, other_mode]
    let base = emit_lexer_skeleton(modes, "Token", "@core")
    let line_fn = mode_to_fn_name(line_mode)
    let other_fn = mode_to_fn_name(other_mode)
    let custom_body = "fn " +
      line_fn +
      "(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
      "  custom_" +
      suffix +
      "(source, pos)\n" +
      "}"
    let exact_stub = "fn " +
      line_fn +
      "(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
      "  abort(\"" +
      line_fn +
      " not implemented\")\n" +
      "}"
    let other_stub = "fn " +
      other_fn +
      "(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
      "  abort(\"" +
      other_fn +
      " not implemented\")\n" +
      "}"
    let line_delegate = "fn " +
      line_fn +
      "(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
      "  " +
      generated_line_lexer_fn_name(line_mode) +
      "(source, pos)\n" +
      "}"
    let handwritten = base.replace(old=exact_stub, new=custom_body)
    inspect(
      integrate_line_lexer_skeleton(handwritten, [line_mode], "Token", "@core") ==
      handwritten,
      content="true",
    )
    let one_byte_mutation = exact_stub.replace(
      old="not implemented",
      new="not implemented!",
    )
    let near_canonical = base.replace(old=exact_stub, new=one_byte_mutation)
    inspect(
      integrate_line_lexer_skeleton(
        near_canonical,
        [line_mode],
        "Token",
        "@core",
      ) ==
      near_canonical,
      content="true",
    )

    let migrated = integrate_line_lexer_skeleton(
      base,
      [line_mode],
      "Token",
      "@core",
    )
    inspect(
      migrated == base.replace(old=exact_stub, new=line_delegate),
      content="true",
    )
    inspect(migrated.contains(other_stub), content="true")
    inspect(
      integrate_line_lexer_skeleton(migrated, [line_mode], "Token", "@core") ==
      migrated,
      content="true",
    )

    let forward = integrate_line_lexer_skeleton(
      base,
      [line_mode, other_mode],
      "Token",
      "@core",
    )
    let reverse = integrate_line_lexer_skeleton(
      base,
      [other_mode, line_mode],
      "Token",
      "@core",
    )
    let other_delegate = "fn " +
      other_fn +
      "(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
      "  " +
      generated_line_lexer_fn_name(other_mode) +
      "(source, pos)\n" +
      "}"
    let expected_both = base
      .replace(old=exact_stub, new=line_delegate)
      .replace(old=other_stub, new=other_delegate)
    inspect(forward == expected_both, content="true")
    inspect(reverse == expected_both, content="true")
  }
}

///|
test "build_line_lexer_regression_outputs regenerates the combined fixture" {
  let source = read_fallback_fixture(
    "../fixtures/line_lexer_regression/src/line_lexer_src.mbt", "fixtures/line_lexer_regression/src/line_lexer_src.mbt",
  )
  let skeleton = read_fallback_fixture(
    "../fixtures/line_lexer_regression/lexer_skeleton.g.mbt", "fixtures/line_lexer_regression/lexer_skeleton.g.mbt",
  )
  match
    build_line_lexer_regression_outputs(source, "line_lexer_src.mbt", skeleton) {
    Ok((line_lexer, integrated_skeleton)) => {
      inspect(
        line_lexer.contains("fn generated_lex_line_start"),
        content="true",
      )
      inspect(
        integrated_skeleton.contains("generated_lex_line_start(source, pos)"),
        content="true",
      )
      inspect(
        integrated_skeleton.contains("handwritten fallback"),
        content="true",
      )
    }
    Err(msg) => fail("expected line lexer fixture output: " + msg)
  }
}

///|
test "regenerate_line_lexer_regression_fixture reports unreadable source" {
  match
    regenerate_line_lexer_regression_fixture(
      "missing-line-lexer-source.mbt", "unused-line-lexer.g.mbt", "unused-lexer-skeleton.g.mbt",
    ) {
    Err(msg) =>
      inspect(msg.contains("missing-line-lexer-source.mbt"), content="true")
    Ok(_) => fail("expected missing fixture source to fail regeneration")
  }
}

///|
test "write_line_lexer_job reports an unwritable helper path" {
  match
    write_line_lexer_job(
      Some(
        (
          "missing-line-lexer-output/line_lexer.g.mbt",
          "generated",
          ["LineStart"],
        ),
      ),
    ) {
    Err(msg) =>
      inspect(
        msg.contains("missing-line-lexer-output/line_lexer.g.mbt"),
        content="true",
      )
    Ok(_) => fail("expected unwritable line lexer output to fail")
  }
}
