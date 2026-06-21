///|
/// E1 ergonomics measurement: what fraction of grammar rules are truly
/// declarative (dispatched generically through the GrammarIr with no
/// special-case logic in run_expr or parse_top_level_repeat)?
pub struct E1Measurement {
  total_rules : Int
  declarative_rules : Int
  hardcoded_rules : Int
  escape_hatch_rules : Int
} derive(Debug, Eq)

///|
/// E2 ergonomics measurement: lambda-specific escape hatches and missing
/// combinators that prevented full-IR encoding.
pub struct E2Measurement {
  escape_hatch_count : Int
  /// Combinators missing from the IR that required escape hatches.
  missing_combinators : Array[String]
  /// Escape hatch names and their reason.
  escape_hatches : Array[(String, String)]
} derive(Debug)

///|
/// Measure E1 rule coverage for the lambda spike IR.
///
/// Rules classified as declarative: encoded as GrammarIr expressions that
/// run_expr dispatches generically (no per-rule special-case).
///
/// Rules classified as hardcoded: logic lives in a named parse_*_ir function
/// that is called directly rather than through the IR expression dispatch.
///
/// Rules classified as escape_hatch: represented in GrammarIr by ManualX
/// variants that bypass the generic interpreter entirely.
pub fn measure_e1() -> E1Measurement {
  // Declarative (1): Source — RepeatTopLevel is a generic IR expression
  //   run_expr handles it uniformly, no special case needed.
  //
  // Hardcoded (4):
  //   Definition — parse_top_level_repeat calls parse_definition_ir directly,
  //     never through IR dispatch; Definition Expr is Empty (never dispatched).
  //   Binary — run_expr has: Expr::Ref(RuleId::Binary) => parse_binary_ir(...)
  //     This is a special case in run_expr, not generic Ref dispatch.
  //   Application — same pattern: Expr::Ref(RuleId::Application) => parse_application_ir(...)
  //   Expression — delegates to Binary via Ref, but Binary is special-cased.
  //     Expression itself has no parse function; its Ref dispatch hits Binary's
  //     special case, making it a dependent of the hardcoded layer.
  //
  // Escape hatch (2):
  //   Atom — ManualAtom: no Seq combinator to express paren/block/error sequences
  //   ParamList — ManualParamList: comma-delimited token loop
  E1Measurement::{
    total_rules: 7,
    declarative_rules: 1,
    hardcoded_rules: 4,
    escape_hatch_rules: 2,
  }
}

///|
/// Measure E2 escape hatches: lambda-specific code that cannot be expressed
/// in the current GrammarIr without adding new combinators.
pub fn measure_e2() -> E2Measurement {
  E2Measurement::{
    escape_hatch_count: 2,
    missing_combinators: [
      "Seq — sequential composition of tokens/exprs in a single rule body", "Pratt — infix operator table for binary expressions and left-associative application",
    ],
    escape_hatches: [
      (
        "ManualAtom", "Atom requires Seq to express 'EmitToken + recurse + ExpectToken' (paren expr) and multi-branch dispatch with embedded token emission (block, literal, ident)",
      ),
      (
        "ManualParamList", "ParamList is a comma-delimited identifier loop; requires Seq + RepeatWhile with separator, not expressible with current IR combinators",
      ),
    ],
  }
}

///|
/// Coverage ratio for reporting: declarative_rules / total_rules.
/// Expressed as (numerator, denominator) to avoid floating point.
pub fn e1_coverage_ratio(m : E1Measurement) -> (Int, Int) {
  (m.declarative_rules, m.total_rules)
}

///|
/// E3 probe: what would a second-grammar reuse test require, and is it gated?
///
/// E3 asks: "If we build a SECOND grammar (not lambda) using GrammarIr, would
/// the safety oracles (D1/D2a/D2b) still pass? Does the architecture generalize
/// to languages not known at IR-design time?"
///
/// Current gate status: BLOCKED on E2 findings. The spike required 5 escape
/// hatches and/or hardcoded paths (ManualAtom, ManualParamList, parse_definition_ir,
/// parse_binary_ir, parse_application_ir) for lambda's 7-rule grammar. Building
/// a second grammar would require redesigning the IR to add Seq and Pratt
/// combinators BEFORE the probe would be meaningful — otherwise the second
/// grammar would face the same escape-hatch accumulation.
pub struct ReuseProbePlan {
  /// Description of the second grammar to build for the E3 probe.
  target_grammar : String
  /// IR extensions required before the probe is executable.
  required_extensions : Array[String]
  /// Expected safety oracle outcomes if extensions are implemented correctly.
  expected_oracle_result : String
  /// Gate condition: E3 is only meaningful when this holds.
  gate_condition : String
} derive(Debug)

///|
/// Return the E3 follow-up probe plan.
pub fn e3_probe_plan() -> ReuseProbePlan {
  ReuseProbePlan::{
    target_grammar: "A minimal JSON-like language: object/array/string/number/null literals with no operators (avoids needing Pratt for E3 validation).",
    required_extensions: [
      "Seq combinator in GrammarIr.Expr — sequential composition of token emission and recursive calls without lambda-specific escape hatches.",
      "RepeatWhile with separator support — for array/object element lists.", "Error recovery Expr variant (or reuse ErrorUntil) — for malformed JSON recovery.",
    ],
    expected_oracle_result: "D1/D2a/D2b all pass across all oracle fixtures. No WrongModelStop divergences. Possible ReplicationResidual on error messages (as seen in lambda E2). REUSE-PARITY vacuous (same finding as lambda).",
    gate_condition: "E1 coverage ratio for the new grammar must be >= 5/7 — at least 5 of 7 grammar rules encoded declaratively with no ManualX escape hatches. This proves the IR generalizes beyond the design-target language.",
  }
}

///|
/// E3 gate: returns false when E3 probe is blocked on outstanding E2 issues.
/// When this returns false, the full GO decision should note that E3 requires
/// IR extensions before it can validate generalizability.
pub fn e3_follow_up_gate() -> (Bool, String) {
  let e2 = measure_e2()
  if e2.escape_hatch_count > 0 {
    (
      false,
      "Blocked: " +
      e2.escape_hatch_count.to_string() +
      " lambda-specific escape hatches require IR redesign (add Seq, Pratt) before a second-grammar probe is meaningful.",
    )
  } else {
    (true, "Ready: no lambda-specific escape hatches in IR.")
  }
}
