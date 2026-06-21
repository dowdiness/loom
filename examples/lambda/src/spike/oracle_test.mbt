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
