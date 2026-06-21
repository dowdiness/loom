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
