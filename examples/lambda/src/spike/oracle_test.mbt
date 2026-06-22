///|
test "oracle: let def fixture passes all checks" {
  let (initial, steps) = let_def_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
    inspect(result.reuse_parity_ok, content="true")
  }
}

///|
test "oracle: top-level reuse fixture passes all checks" {
  let (initial, steps) = top_level_reuse_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
    inspect(result.reuse_parity_ok, content="true")
  }
}

///|
test "oracle: app/bop Pratt fixture passes all checks" {
  let (initial, steps) = app_bop_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
    inspect(result.reuse_parity_ok, content="true")
  }
}

///|
test "oracle: error recovery fixture — malformed then recovery" {
  let (initial, steps) = error_recovery_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  inspect(results.length(), content="2")
  // Step 0: malformed — diagnostics non-empty, D2b trivially passes.
  let malformed = results[0]
  inspect(malformed.diagnostics_empty, content="false")
  inspect(malformed.d1_ok, content="true")
  inspect(malformed.d2a_ok, content="true")
  inspect(malformed.d2b_ok, content="true")
  // Step 1: recovery — all checks pass.
  let recovered = results[1]
  inspect(recovered.diagnostics_empty, content="true")
  inspect(recovered.d1_ok, content="true")
  inspect(recovered.d2a_ok, content="true")
  inspect(recovered.d2b_ok, content="true")
  inspect(recovered.reuse_parity_ok, content="true")
}

///|
test "oracle: combined fixture — all oracle checks" {
  let (initial, steps) = combined_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
  }
}

///|
test "oracle: soft newline before = passes D2a (P3 regression)" {
  // Without spike_expect consuming soft newlines, B sees Newline and emits
  // a missing-= placeholder instead of consuming the newline and matching =.
  // A passes the edit via lambda_expect → D2a fails unless fixed.
  let (initial, steps) = soft_newline_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
  }
}

///|
test "oracle: soft newline before RHS expression passes D2a (P2)" {
  // `let x =\n1` — A's parse_expression_with_mode calls
  // consume_soft_newlines_before_expression before parse_binary_op, so the
  // newline is consumed and 1 is parsed as the RHS. B must do the same via
  // consume_while_emit_if after spike_expect(Eq); without it B emits an error
  // placeholder for the newline and 1 becomes a dangling trailing expression.
  let (initial, steps) = rhs_newline_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
  }
}

///|
test "oracle: let with param list diagnostic matches A (P2)" {
  // `let f(x) = 1` — A records the 'let declarations do not take parameter
  // lists' diagnostic before expecting =. Without the LeftParen guard in B,
  // B skips that diagnostic and D2a diverges on diagnostic count.
  let (initial, steps) = let_param_list_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
  }
}

///|
test "oracle: block with nested let definition matches A (D2a)" {
  // fn f(x) { \n let y = 1 \n y \n } — A's parse_block_expr loops over
  // definitions before the trailing expression; without the ManualDefinition
  // fix B would leave 'let' unconsumed, emit a missing '}', and diverge.
  let source = "fn f(x) {\nlet y = 1\ny\n}"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "oracle: block with fn nested definition matches A (D2a)" {
  // fn outer(x) { \n fn inner(y) { y } \n inner x \n }
  let source = "fn outer(x) {\nfn inner(y) { y }\ninner x\n}"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "oracle: top-level newline-application forms AppExpr matching A (P2 D2a)" {
  // `f\nx` at the top level: A's parse_expression_with_mode(ctx, true) calls
  // consume_soft_newlines_before_application_atom so the newline is consumed
  // and `f` and `x` are wrapped in an AppExpr.
  // B must produce the same CST via ManualNewlineAppExpr.
  let source = "f\nx"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "oracle: let body newline does NOT form AppExpr (P2 D2a boundary)" {
  // `let x = 1\ny` — A uses allow_newline_application=false for let bodies,
  // so the newline separates `1` (let value) from `y` (top-level trailing expr).
  // B's PrattApp + ManualNewlineAppExpr must reproduce this.
  let source = "let x = 1\ny"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "oracle: block trailing newline-application forms AppExpr matching A (P2 D2a)" {
  // `fn f(x) { f\nx }` — the trailing expression inside the block uses
  // allow_newline_application=true in A; `f\nx` should be an AppExpr.
  let source = "fn f(x) { f\nx }"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// Task 9: the headline re-validation. Every boolean is freshly derived against
/// the reified `@grammar` IR (B rebuilt from compile() inside run_reified_ir_oracle),
/// so no PASS is inherited from the closure spike.
test "reified grammar IR passes D1 D2a D2b oracle or records residue" {
  let result = run_reified_ir_oracle()
  inspect(result.d1_passed, content="true")
  inspect(result.d2a_passed, content="true")
  inspect(result.d2b_passed, content="true")
  match result.divergence {
    DivergenceClass::NoDivergence => ()
    DivergenceClass::ReplicationResidual(_) => ()
    DivergenceClass::WrongModelStop(message) => fail(message)
  }
}

///|
/// Watch-item for finding #1 (ExpectSkip at EOF, spec §5.3): "let x = 1" → "let x"
/// leaves `=`/RHS missing with NO preceding newline at EOF. A's lambda_expect and
/// B's ExpectSkip must agree on the missing-`=` diagnostic + placeholder.
test "watch-item: ExpectSkip missing = at EOF holds A/B parity (finding #1)" {
  let (initial, steps) = expect_skip_eof_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
  }
}

///|
/// Watch-item for finding #4 (block delimiter, spec §5.3): dropping the newline
/// between two block expressions must make A and B's RequireSep(Newline) agree on
/// the "expected delimiter" diagnostic appearing then clearing.
test "watch-item: block delimiter drop/restore holds A/B parity (finding #4)" {
  let (initial, steps) = block_delimiter_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
  }
}

///|
test "oracle: missing block delimiter emits same diagnostic count as A (P2 D2a)" {
  // `fn f() { let x = 1 let y = 2\ny }` — no newline between block definitions.
  // A emits "Expected ';' or newline between definitions"; B must do the same.
  let source = "fn f() { let x = 1 let y = 2\ny }"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  let b_grammar = build_b_syntax_grammar()
  let (b_cst, b_diag) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
  inspect(a_diag.items().length() == b_diag.items().length(), content="true")
  inspect(a_diag.items().length() > 0, content="true")
}
