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
