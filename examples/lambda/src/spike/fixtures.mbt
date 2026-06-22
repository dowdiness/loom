///|
/// Fixture: single LetDef edit — change RHS value.
/// Edits "let x = 1" → "let x = 42".
pub fn let_def_fixture() -> (String, Array[EditStep]) {
  let initial = "let x = 1"
  let steps = [
    // Replace "1" (len 1) with "42" (len 2) at offset 8.
    EditStep::{
      label: "change int literal 1→42",
      before: "let x = 1",
      after: "let x = 42",
      edit: @core.Edit::new(8, 1, 2),
    },
    // Replace "42" (len 2) with "0" (len 1) at offset 8.
    EditStep::{
      label: "change int literal 42→0",
      before: "let x = 42",
      after: "let x = 0",
      edit: @core.Edit::new(8, 2, 1),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: two top-level LetDef definitions with edit to second definition.
/// Key for reuse-parity: edit to second def should reuse the first.
pub fn top_level_reuse_fixture() -> (String, Array[EditStep]) {
  let initial = "let x = 1\nlet y = 2"
  let steps = [
    // Edit second definition: replace "2" (len 1) with "99" (len 2) at offset 18.
    EditStep::{
      label: "edit second let def",
      before: "let x = 1\nlet y = 2",
      after: "let x = 1\nlet y = 99",
      edit: @core.Edit::new(18, 1, 2),
    },
    // Edit second definition again: replace "99" (len 2) with "3" (len 1) at offset 18.
    EditStep::{
      label: "edit second let def again",
      before: "let x = 1\nlet y = 99",
      after: "let x = 1\nlet y = 3",
      edit: @core.Edit::new(18, 2, 1),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: Pratt application.
pub fn app_bop_fixture() -> (String, Array[EditStep]) {
  let initial = "let z = f x"
  let steps = [
    // Add a + operand: "f x" (len 3) → "f x + 1" (len 7) at offset 8.
    EditStep::{
      label: "add binary op to application",
      before: "let z = f x",
      after: "let z = f x + 1",
      edit: @core.Edit::new(8, 3, 7),
    },
    // Remove the + operand: "f x + 1" (len 7) → "f x" (len 3) at offset 8.
    EditStep::{
      label: "remove binary op",
      before: "let z = f x + 1",
      after: "let z = f x",
      edit: @core.Edit::new(8, 7, 3),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: malformed intermediate then recovery.
/// Tests that D2b tracker records failed input correctly and resumes on recovery.
pub fn error_recovery_fixture() -> (String, Array[EditStep]) {
  let initial = "let x = 1"
  let steps = [
    // Delete the RHS: replace "1" (len 1) with "" (len 0) at offset 8.
    // "let x = " is malformed (missing RHS).
    EditStep::{
      label: "delete RHS (malformed)",
      before: "let x = 1",
      after: "let x = ",
      edit: @core.Edit::new(8, 1, 0),
    },
    // Restore the RHS: replace "" (len 0) with "2" (len 1) at offset 8.
    EditStep::{
      label: "restore RHS (recovery)",
      before: "let x = ",
      after: "let x = 2",
      edit: @core.Edit::new(8, 0, 1),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: ParamList churn — fn definition with parameters.
/// Uses identifier application in body to exercise atom + app rules.
pub fn param_list_churn_fixture() -> (String, Array[EditStep]) {
  // "fn f(x) { x }" — fn definition with one param and body "x".
  // Note: spike's parse_block_expr_ir handles basic "{ expr }" blocks.
  let initial = "fn f(x) { x }"
  let steps = [
    // Add a parameter: "(x)" (len 3) → "(x, y)" (len 6) at offset 4.
    EditStep::{
      label: "add param y",
      before: "fn f(x) { x }",
      after: "fn f(x, y) { x }",
      edit: @core.Edit::new(4, 3, 6),
    },
    // Remove second param: "(x, y)" (len 6) → "(x)" (len 3) at offset 4.
    EditStep::{
      label: "remove param y",
      before: "fn f(x, y) { x }",
      after: "fn f(x) { x }",
      edit: @core.Edit::new(4, 6, 3),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: soft newline before required token.
/// "let x = 1" → "let x\n= 1" — A routes `=` through lambda_expect which
/// first calls consume_soft_newlines_before_expected; B must do the same via
/// spike_expect. Without the fix B sees Newline and emits a missing-= placeholder
/// instead, diverging from A in both CST shape and diagnostics (D2a failure).
pub fn soft_newline_fixture() -> (String, Array[EditStep]) {
  let initial = "let x = 1"
  let steps = [
    // Replace space before `=` with newline: offset 5, old_len=1, new_len=1.
    EditStep::{
      label: "soft newline before = (let binding)",
      before: "let x = 1",
      after: "let x\n= 1",
      edit: @core.Edit::new(5, 1, 1),
    },
    // Restore the space: verify recovery back to normal parse.
    EditStep::{
      label: "restore space before = (recovery)",
      before: "let x\n= 1",
      after: "let x = 1",
      edit: @core.Edit::new(5, 1, 1),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: soft newline before the let RHS expression.
/// "let x = 1" → "let x =\n1" — A calls parse_expression_with_mode which
/// first runs consume_soft_newlines_before_expression; B must do the same
/// after spike_expect(Eq) otherwise the newline is seen as the atom and an
/// error placeholder is emitted before 1 becomes a trailing expression.
pub fn rhs_newline_fixture() -> (String, Array[EditStep]) {
  let initial = "let x = 1"
  let steps = [
    EditStep::{
      label: "soft newline before RHS (let x =\\n1)",
      before: "let x = 1",
      after: "let x =\n1",
      edit: @core.Edit::new(7, 1, 1),
    },
    EditStep::{
      label: "restore space before RHS",
      before: "let x =\n1",
      after: "let x = 1",
      edit: @core.Edit::new(7, 1, 1),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: legacy parameter list on a let binding.
/// "let f(x) = 1" — A's parse_let_item records the 'let declarations do not
/// take parameter lists' diagnostic before expecting =; B must emit the same
/// diagnostic before calling spike_expect(Eq) so D2a counts match.
pub fn let_param_list_fixture() -> (String, Array[EditStep]) {
  let initial = "let f(x) = 1"
  let steps = [
    EditStep::{
      label: "let with param list (legacy form)",
      before: "let f(x) = 1",
      after: "let g(x) = 1",
      edit: @core.Edit::new(4, 1, 1),
    },
    EditStep::{
      label: "restore original name",
      before: "let g(x) = 1",
      after: "let f(x) = 1",
      edit: @core.Edit::new(4, 1, 1),
    },
  ]
  (initial, steps)
}

///|
/// Fixture: top-level newline application (the lone irreducible residue).
/// "f x" ↔ "f\nx" — both are an AppExpr because A parses the top-level trailing
/// expression with allow_newline_application=true. The newline is a soft
/// separator between application atoms, NOT a statement break. B reproduces this
/// only through the spike-local probe's `parse_newline_app` (ManualNewlineAppExpr
/// is placeholdered by @grammar.interpret), so this fixture is what
/// `run_newline_application_reification_probe` classifies. See spec §5.1/§5.3.
pub fn newline_app_fixture() -> (String, Array[EditStep]) {
  let initial = "f x"
  let steps = [
    // Replace the space (offset 1, len 1) with a newline (len 1): "f\nx".
    EditStep::{
      label: "space → soft newline between application atoms",
      before: "f x",
      after: "f\nx",
      edit: @core.Edit::new(1, 1, 1),
    },
    // Restore the space: "f x" — both forms must stay a single AppExpr.
    EditStep::{
      label: "soft newline → space (recovery)",
      before: "f\nx",
      after: "f x",
      edit: @core.Edit::new(1, 1, 1),
    },
  ]
  (initial, steps)
}

///|
/// Watch-item fixture for finding #1 (ExpectSkip at EOF, spec §5.3).
/// "let x = 1" → "let x" (delete " = 1") leaves the `=` and RHS missing at EOF;
/// A's lambda_expect / B's ExpectSkip(IsToken(Newline), …, Eq, …) must agree on
/// the missing-`=` diagnostic and placeholder when no newline precedes EOF.
pub fn expect_skip_eof_fixture() -> (String, Array[EditStep]) {
  let initial = "let x = 1"
  let steps = [
    // Delete " = 1" (offset 5, len 4) → "let x": missing `=` and RHS at EOF.
    EditStep::{
      label: "drop = and RHS, leaving missing-= at EOF",
      before: "let x = 1",
      after: "let x",
      edit: @core.Edit::new(5, 4, 0),
    },
    // Restore: "let x = 1".
    EditStep::{
      label: "restore = and RHS (recovery)",
      before: "let x",
      after: "let x = 1",
      edit: @core.Edit::new(5, 0, 4),
    },
  ]
  (initial, steps)
}

///|
/// Watch-item fixture for finding #4 (block delimiter check, spec §5.3).
/// RequireSep guards the separator between block DEFINITIONS (let/fn), not
/// between bare expressions — `1 2` is application (one AppExpr), so it would
/// never fire the check. This fixture uses two `let` defs (cf. the real test at
/// oracle_test.mbt:184): dropping the newline between them leaves them with no
/// separator, so A and B's RequireSep(Newline) must agree on the
/// "between definitions" diagnostic appearing then clearing.
pub fn block_delimiter_fixture() -> (String, Array[EditStep]) {
  let initial = "fn f() {\nlet x = 1\nlet y = 2\n}"
  let steps = [
    // Replace the newline between the two let defs (offset 18, len 1) with a
    // space (len 1): the defs lose their required separator.
    EditStep::{
      label: "drop newline between block defs → missing-delimiter diagnostic",
      before: "fn f() {\nlet x = 1\nlet y = 2\n}",
      after: "fn f() {\nlet x = 1 let y = 2\n}",
      edit: @core.Edit::new(18, 1, 1),
    },
    // Restore the newline: the diagnostic clears.
    EditStep::{
      label: "restore newline between block defs (recovery)",
      before: "fn f() {\nlet x = 1 let y = 2\n}",
      after: "fn f() {\nlet x = 1\nlet y = 2\n}",
      edit: @core.Edit::new(18, 1, 1),
    },
  ]
  (initial, steps)
}

///|
/// Combined fixture: LetDef + top-level reuse + error + recovery + Pratt.
/// Used by the main oracle test to exercise all oracle checks in one run.
pub fn combined_fixture() -> (String, Array[EditStep]) {
  let initial = "let x = 1\nlet y = 2"
  let steps = [
    // Edit second definition — should trigger reuse of first.
    EditStep::{
      label: "edit second let (reuse first)",
      before: "let x = 1\nlet y = 2",
      after: "let x = 1\nlet y = 99",
      edit: @core.Edit::new(18, 1, 2),
    },
    // Make second definition malformed (delete RHS).
    EditStep::{
      label: "delete second RHS (malformed)",
      before: "let x = 1\nlet y = 99",
      after: "let x = 1\nlet y = ",
      edit: @core.Edit::new(18, 2, 0),
    },
    // Recover second definition.
    EditStep::{
      label: "restore second RHS (recovery)",
      before: "let x = 1\nlet y = ",
      after: "let x = 1\nlet y = 42",
      edit: @core.Edit::new(18, 0, 2),
    },
    // Add a Pratt binary expression to first definition.
    EditStep::{
      label: "add binary op to first def",
      before: "let x = 1\nlet y = 42",
      after: "let x = 1 + 2\nlet y = 42",
      edit: @core.Edit::new(9, 0, 4),
    },
  ]
  (initial, steps)
}
