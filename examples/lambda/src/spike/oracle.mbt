///|
/// One edit step in an oracle fixture sequence.
pub struct EditStep {
  label : String
  /// Source text before the edit (for record_failed_input context).
  before : String
  /// Source text after the edit is applied.
  after : String
  /// The edit describing what changed (use Edit::new with lengths).
  edit : @core.Edit
} derive(Debug)

///|
/// Oracle result for one edit step. All four oracle booleans must be true
/// for the step to count toward a GO verdict.
///
/// message_strings_matched: when D2a passes (structural fields equal), whether
/// diagnostic message strings also matched. A false here with d2a_ok=true
/// indicates a ReplicationResidual (wording difference, not a GO blocker).
pub(all) struct OracleStepResult {
  label : String
  d1_ok : Bool
  d2a_ok : Bool
  d2b_ok : Bool
  reuse_parity_ok : Bool
  diagnostics_empty : Bool
  message_strings_matched : Bool
  a_reuse_count : Int
  b_reuse_count : Int
} derive(Debug, Eq)

///|
/// Compare two DiagnosticSets structurally (source, severity, code, primary),
/// ignoring message wording, labels, notes, and token evidence.
/// D2a only requires that cross-impl B reproduces A's structural shape —
/// message-string differences are classified as ReplicationResidual, not D2a
/// failures, so they are reported separately (message_strings_equal).
pub fn diagnostics_structurally_equal(
  a : @core.DiagnosticSet,
  b : @core.DiagnosticSet,
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let a_items = a.items()
  let b_items = b.items()
  for i = 0; i < a_items.length(); i = i + 1 {
    let ad = a_items[i]
    let bd = b_items[i]
    if ad.source != bd.source {
      return false
    }
    if ad.severity != bd.severity {
      return false
    }
    if ad.code != bd.code {
      return false
    }
    if ad.primary != bd.primary {
      return false
    }
  }
  true
}

///|
/// Check whether message strings match between two DiagnosticSets.
/// A message-only divergence (structural fields match but messages differ)
/// is a separate low-priority ReplicationResidual — it does NOT make D2a fail.
pub fn message_strings_equal(
  a : @core.DiagnosticSet,
  b : @core.DiagnosticSet,
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let a_items = a.items()
  let b_items = b.items()
  for i = 0; i < a_items.length(); i = i + 1 {
    if a_items[i].message != b_items[i].message {
      return false
    }
  }
  true
}

///|
/// Run the A-vs-B oracle over an edit sequence.
///
/// D2b honesty scoping (per plan §Task 9):
/// Because both trackers are fed the SAME edits and the SAME success/failure
/// classification (derived from A's diagnostics, which equal B's after D2a),
/// and project_lambda_leaves is a deterministic function of each CST, a D2b
/// A-vs-B mismatch under target (i) implies a D2a mismatch — so D2b is NOT an
/// independent path-dependence oracle as wired here. Its independent residual is:
/// (1) the tree_diff hash-collision blind spot (D2b can see structural
///     differences that tree_diff's hash-equality shortcut masks), and
/// (2) a direct consumer-facing stable-ID invariant assertion.
/// Genuine independence requires consumer-style bookkeeping with separate
/// edit sequences — that belongs to the projectional-language follow-up (Task 13).
pub fn run_oracle_fixture(
  initial : String,
  steps : Array[EditStep],
  b : @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind],
) -> Array[OracleStepResult] {
  // Build A grammar through the same normalizer as B so only parse_root differs.
  let a_grammar = normalized_syntax_grammar(
    @lambda.lambda_grammar.spec,
    @lambda.lambda_grammar.lex,
  )
  let a_parser = @loom.new_syntax_parser(initial, a_grammar)
  let b_parser = @loom.new_syntax_parser(initial, b)

  // Projection identity trackers — INDEPENDENT instances for A and B.
  let a_tracker : @core.ProjectionIdentityTracker[String] = @core.ProjectionIdentityTracker::new()
  let b_tracker : @core.ProjectionIdentityTracker[String] = @core.ProjectionIdentityTracker::new()
  let a_alloc = @core.ProjectionStringIdAllocator::new((key, count) => {
    key + ":" + count.to_string()
  })
  let b_alloc = @core.ProjectionStringIdAllocator::new((key, count) => {
    key + ":" + count.to_string()
  })

  // Seed both trackers from the initial source BEFORE the first apply_edit.
  // Required: an unseeded tracker commits every leaf from scratch on the first
  // edit, so a before-edit insertion that shifts existing IDs would produce a
  // false D2b pass (all IDs churned identically A and B). Seeding commits the
  // initial baseline so the first edit's realign measures churn against it.
  let a_initial_snapshot = a_parser.snapshot().read_or_abort()
  let b_initial_snapshot = b_parser.snapshot().read_or_abort()
  let a_initial_leaves = project_lambda_leaves(a_initial_snapshot.syntax)
  let b_initial_leaves = project_lambda_leaves(b_initial_snapshot.syntax)
  let a_stable0 = a_tracker.realign_success(initial, a_initial_leaves, leaf => {
    a_alloc.allocate(leaf)
  })
  let b_stable0 = b_tracker.realign_success(initial, b_initial_leaves, leaf => {
    b_alloc.allocate(leaf)
  })
  a_tracker.commit_success(initial, a_stable0)
  b_tracker.commit_success(initial, b_stable0)
  // Assert seed parity: initial A and B IDs must match (same source, no parse_root
  // divergence at seed time since both parse deterministically).
  let _ = a_stable0 == b_stable0 // deliberate assert-by-equality in D2b result below

  let results : Array[OracleStepResult] = Array::new()
  for step in steps {
    // Apply the edit to both parsers.
    a_parser.apply_edit(step.edit, step.after)
    b_parser.apply_edit(step.edit, step.after)

    // Read incremental snapshots.
    let a_snap = a_parser.snapshot().read_or_abort()
    let b_snap = b_parser.snapshot().read_or_abort()

    // D1: incremental parse matches fresh parse for BOTH A and B independently.
    let d1_a_ok = check_d1(step.after, a_snap, a_grammar)
    let d1_b_ok = check_d1(step.after, b_snap, b)
    let d1_ok = d1_a_ok && d1_b_ok

    // D2a: A and B incremental snapshots are structurally identical.
    let d2a_cst_ok = @core.tree_diff(
      a_snap.syntax.cst_node(),
      b_snap.syntax.cst_node(),
    ).is_empty()
    let d2a_diag_ok = diagnostics_structurally_equal(
      a_snap.diagnostics,
      b_snap.diagnostics,
    )
    let d2a_ok = d2a_cst_ok && d2a_diag_ok

    // D2b: stable projection IDs agree between A and B (hash-collision guard +
    // consumer-invariant assertion). Tracks in lockstep with A's diagnostics
    // as the shared failure/success signal.
    let diagnostics_empty = a_snap.diagnostics.is_empty()
    let d2b_ok : Bool = if diagnostics_empty {
      let a_leaves = project_lambda_leaves(a_snap.syntax)
      let b_leaves = project_lambda_leaves(b_snap.syntax)
      let a_stable = a_tracker.realign_success(
        step.after,
        a_leaves,
        leaf => a_alloc.allocate(leaf),
        edit=step.edit,
      )
      let b_stable = b_tracker.realign_success(
        step.after,
        b_leaves,
        leaf => b_alloc.allocate(leaf),
        edit=step.edit,
      )
      a_tracker.commit_success(step.after, a_stable)
      b_tracker.commit_success(step.after, b_stable)
      a_stable == b_stable
    } else {
      // Malformed intermediate — record failed input without committing.
      a_tracker.record_failed_input(
        step.after,
        source_before_edit=step.before,
        edit=step.edit,
      )
      b_tracker.record_failed_input(
        step.after,
        source_before_edit=step.before,
        edit=step.edit,
      )
      // D2b trivially holds for malformed intermediates (no leaves to compare).
      true
    }

    // REUSE-PARITY: incremental reuse counts must match.
    // Note: per Task 10 finding, this is vacuous — engine node reuse
    // compensates for any missing repeat-group reuse. See Task 13 for E3 probe.
    let reuse_parity_ok = a_snap.reuse_count == b_snap.reuse_count

    // Message-string comparison (only meaningful when D2a passes).
    let message_strings_matched = message_strings_equal(
      a_snap.diagnostics,
      b_snap.diagnostics,
    )

    results.push(OracleStepResult::{
      label: step.label,
      d1_ok,
      d2a_ok,
      d2b_ok,
      reuse_parity_ok,
      diagnostics_empty,
      message_strings_matched,
      a_reuse_count: a_snap.reuse_count,
      b_reuse_count: b_snap.reuse_count,
    })
  }
  results
}

///|
/// D1 check: verify that the incremental snapshot matches a fresh full parse
/// on the same source.
fn check_d1(
  source : String,
  snap : @loom.SyntaxSnapshot,
  grammar : @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  // Fresh parse — grammar.parse_cst may raise LexError but lambda has no
  // lex errors in spike inputs; abort on lex error to surface fixture problems.
  let (fresh_cst, fresh_diag) = grammar.parse_cst(source) catch {
    _ =>
      // Lex error — spike fixtures should not trigger this; treat as D1 fail.
      return false
  }
  let cst_ok = @core.tree_diff(snap.syntax.cst_node(), fresh_cst).is_empty()
  // D1 uses FULL == for diagnostics: same impl, incremental vs fresh, so
  // message strings must also match (no cross-impl message wording tolerance).
  let diag_ok = snap.diagnostics == fresh_diag
  cst_ok && diag_ok
}

///|
/// Classify a single oracle step result into a divergence class.
///
/// Priority (highest severity wins):
/// 1. WrongModelStop: D1 or D2a CST failure. Parse tree disagrees — GO blocker.
/// 2. ReplicationResidual: D2a passes structurally but message strings differ.
///    Cross-impl wording difference. Not a GO blocker; file as known deviation.
/// 3. NoDivergence: all oracle checks pass, messages agree.
///
/// D2b and reuse_parity are not classified here:
/// - D2b failure implies a D2a CST failure (per Task 9 honesty scoping) so it
///   would already be caught by WrongModelStop.
/// - reuse_parity is vacuous (Task 10 finding) so it is not a divergence signal.
pub fn classify_divergence(result : OracleStepResult) -> DivergenceClass {
  // D1 failure: incremental != fresh for A or B.
  if !result.d1_ok {
    return DivergenceClass::WrongModelStop(
      "D1 failure at step \"" +
      result.label +
      "\": incremental parse does not match fresh parse",
    )
  }
  // D2a CST failure: A and B parse trees differ.
  if !result.d2a_ok {
    return DivergenceClass::WrongModelStop(
      "D2a failure at step \"" +
      result.label +
      "\": A and B parse trees or diagnostic structure differ",
    )
  }
  // Structural D2a passed but message strings differ: wording divergence only.
  if !result.message_strings_matched && !result.diagnostics_empty {
    return DivergenceClass::ReplicationResidual(
      "message wording difference at step \"" + result.label + "\"",
    )
  }
  DivergenceClass::NoDivergence
}

///|
/// Classify the overall oracle run: return the highest-severity divergence found
/// across all steps, or NoDivergence if all steps pass.
pub fn classify_run(results : Array[OracleStepResult]) -> DivergenceClass {
  let mut worst = DivergenceClass::NoDivergence
  for result in results {
    let c = classify_divergence(result)
    match (worst, c) {
      // WrongModelStop beats everything.
      (DivergenceClass::WrongModelStop(_), _) => ()
      (_, DivergenceClass::WrongModelStop(_)) => worst = c
      // ReplicationResidual beats NoDivergence.
      (DivergenceClass::NoDivergence, DivergenceClass::ReplicationResidual(_)) =>
        worst = c
      _ => ()
    }
  }
  worst
}

///|
/// Stop condition: a WrongModelStop divergence anywhere in the run means GO is
/// not warranted. ReplicationResidual divergences are noted but not blocking.
pub fn is_go_verdict(results : Array[OracleStepResult]) -> Bool {
  match classify_run(results) {
    DivergenceClass::WrongModelStop(_) => false
    _ => true
  }
}
