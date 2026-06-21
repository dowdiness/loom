///|
/// Helper: build a synthetic OracleStepResult for classifier tests.
/// OracleStepResult is pub(all) so construction works from blackbox tests.
fn make_result(
  d1_ok : Bool,
  d2a_ok : Bool,
  message_strings_matched : Bool,
  diagnostics_empty : Bool,
) -> OracleStepResult {
  OracleStepResult::{
    label: "test",
    d1_ok,
    d2a_ok,
    d2b_ok: true,
    reuse_parity_ok: true,
    diagnostics_empty,
    message_strings_matched,
    a_reuse_count: 0,
    b_reuse_count: 0,
  }
}

///|
test "classifier: all pass → NoDivergence" {
  let r = make_result(true, true, true, true)
  inspect(classify_divergence(r), content="NoDivergence")
}

///|
test "classifier: D1 fail → WrongModelStop" {
  let r = make_result(false, true, true, true)
  match classify_divergence(r) {
    DivergenceClass::WrongModelStop(msg) =>
      inspect(msg.contains("D1 failure"), content="true")
    other => inspect(other, content="expected WrongModelStop")
  }
}

///|
test "classifier: D2a fail → WrongModelStop" {
  let r = make_result(true, false, true, false)
  match classify_divergence(r) {
    DivergenceClass::WrongModelStop(msg) =>
      inspect(msg.contains("D2a failure"), content="true")
    other => inspect(other, content="expected WrongModelStop")
  }
}

///|
test "classifier: message strings differ + non-empty diagnostics → ReplicationResidual" {
  let r = make_result(true, true, false, false)
  match classify_divergence(r) {
    DivergenceClass::ReplicationResidual(msg) =>
      inspect(msg.contains("message wording"), content="true")
    other => inspect(other, content="expected ReplicationResidual")
  }
}

///|
test "classifier: message strings differ + empty diagnostics → NoDivergence" {
  // When diagnostics are empty, message string comparison is irrelevant.
  let r = make_result(true, true, false, true)
  inspect(classify_divergence(r), content="NoDivergence")
}

///|
test "classifier: D2b fail with D1/D2a pass → WrongModelStop (not NoDivergence)" {
  // P1 regression: D2b=false must not fall through to NoDivergence even when
  // D1 and D2a both pass. This is the hash-collision blind-spot case: tree_diff
  // returns empty on equal CstNode.hash, but leaf extraction sees the difference.
  let r = OracleStepResult::{
    label: "hash-collision-guard",
    d1_ok: true,
    d2a_ok: true,
    d2b_ok: false,
    reuse_parity_ok: true,
    diagnostics_empty: true,
    message_strings_matched: true,
    a_reuse_count: 0,
    b_reuse_count: 0,
  }
  match classify_divergence(r) {
    DivergenceClass::WrongModelStop(msg) =>
      inspect(msg.contains("D2b failure"), content="true")
    other => inspect(other, content="expected WrongModelStop")
  }
}

///|
test "classifier: seed parity failure (label seed:initial, d2b_ok=false) → WrongModelStop" {
  // P2 regression: the synthetic seed result pushed by run_oracle_fixture when
  // a_stable0 != b_stable0 must propagate as a WrongModelStop through
  // classify_run and is_go_verdict.
  let r = OracleStepResult::{
    label: "seed:initial",
    d1_ok: true,
    d2a_ok: true,
    d2b_ok: false,
    reuse_parity_ok: true,
    diagnostics_empty: true,
    message_strings_matched: true,
    a_reuse_count: 0,
    b_reuse_count: 0,
  }
  match classify_divergence(r) {
    DivergenceClass::WrongModelStop(_) => inspect(true, content="true")
    other => inspect(other, content="expected WrongModelStop")
  }
}

///|
test "classify_run: all NoDivergence → NoDivergence" {
  let results = [
    make_result(true, true, true, true),
    make_result(true, true, true, false),
  ]
  inspect(classify_run(results), content="NoDivergence")
}

///|
test "classify_run: one WrongModelStop dominates" {
  let results = [
    make_result(true, true, true, true),
    make_result(false, true, true, true),
    make_result(true, true, false, false),
  ]
  match classify_run(results) {
    DivergenceClass::WrongModelStop(_) => inspect(true, content="true")
    other => inspect(other, content="expected WrongModelStop")
  }
}

///|
test "classify_run: ReplicationResidual beats NoDivergence" {
  let results = [
    make_result(true, true, true, true),
    make_result(true, true, false, false),
  ]
  match classify_run(results) {
    DivergenceClass::ReplicationResidual(_) => inspect(true, content="true")
    other => inspect(other, content="expected ReplicationResidual")
  }
}

///|
test "is_go_verdict: combined fixture → true (no WrongModelStop)" {
  let (initial, steps) = combined_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  inspect(is_go_verdict(results), content="true")
}

///|
test "classify_run: combined fixture → ReplicationResidual (message wording)" {
  // B produces structurally identical diagnostics (D2a passes) but different
  // error message wording on malformed inputs. This is a ReplicationResidual
  // finding, not a WrongModelStop — D1 and D2a structural checks still pass.
  let (initial, steps) = combined_fixture()
  let b = build_b_syntax_grammar()
  let results = run_oracle_fixture(initial, steps, b)
  match classify_run(results) {
    DivergenceClass::ReplicationResidual(_) => inspect(true, content="true")
    other => inspect(other, content="expected ReplicationResidual")
  }
}
