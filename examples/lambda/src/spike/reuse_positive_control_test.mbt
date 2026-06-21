///|
/// Task 10 — REUSE-PARITY positive control and finding.
///
/// Finding (E2, spike result): reuse_count tracks BOTH engine-level node reuse
/// (ctx.node() fast-path) AND grammar-level repeat-group reuse
/// (try_reuse_repeat_group). When repeat-group reuse is disabled, the engine's
/// ctx.node() mechanism fires instead for the same unchanged subtrees — yielding
/// the same reuse_count. Therefore REUSE-PARITY (a_reuse_count == b_reuse_count)
/// is vacuously satisfied for all fixtures tested, including crippled-B.
///
/// This makes REUSE-PARITY a non-meaningful safety oracle for this spike: it
/// measures that both parsers find the same unchanged subtrees (which is correct
/// because they parse the same source), not that the repeat-group optimization
/// was applied. The relevant question — whether B achieves the same throughput
/// as A — belongs to Task 13 (E3 benchmarking), not to the reuse_count oracle.
test "positive control: crippled B passes ALL oracles including reuse-parity" {
  // Crippled B disables try_reuse_repeat_group but the engine still reuses
  // unchanged subtrees via ctx.node(). Both A and B end up with reuse_count = 1
  // for an edit to the second of two definitions.
  let (initial, steps) = top_level_reuse_fixture()
  let b_crippled = build_b_syntax_grammar(cripple_reuse=true)
  let results = run_oracle_fixture(initial, steps, b_crippled)
  for result in results {
    inspect(result.d1_ok, content="true")
    inspect(result.d2a_ok, content="true")
    inspect(result.d2b_ok, content="true")
    // Finding: reuse_parity_ok is true even for crippled B because
    // engine-level node reuse compensates for missing repeat-group reuse.
    // REUSE-PARITY (reuse_count equality) is a vacuous oracle for this spike.
    inspect(result.reuse_parity_ok, content="true")
  }
}

///|
test "positive control: counts in detail for first edit step" {
  // Document actual reuse counts so the finding is machine-verifiable.
  let (initial, steps) = top_level_reuse_fixture()
  let b = build_b_syntax_grammar()
  let b_crippled = build_b_syntax_grammar(cripple_reuse=true)
  let normal_results = run_oracle_fixture(initial, steps, b)
  let crippled_results = run_oracle_fixture(initial, steps, b_crippled)
  let step0_normal = normal_results[0]
  let step0_crippled = crippled_results[0]
  // Both normal and crippled B get reuse_count = 1 on the first edit step
  // (unchanged first definition reused via engine node-level mechanism).
  inspect(step0_normal.a_reuse_count, content="1")
  inspect(step0_normal.b_reuse_count, content="1")
  inspect(step0_crippled.a_reuse_count, content="1")
  inspect(step0_crippled.b_reuse_count, content="1")
  // Reuse counts are equal regardless of cripple_reuse flag.
  inspect(step0_normal.reuse_parity_ok, content="true")
  inspect(step0_crippled.reuse_parity_ok, content="true")
}

///|
test "positive control: normal B passes all checks" {
  // Verify un-crippled B also satisfies all oracles (baseline sanity).
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
