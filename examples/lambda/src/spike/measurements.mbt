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
  // P2 fixes (after Track 2):
  //
  // Declarative (5):
  //   Source     — RepeatTopLevel dispatched generically via run_expr;
  //     rule_id + starts_pred + tail_expr are all threaded so RepeatTopLevel
  //     is fully generic: all behavior expressed in the IR value, none in the
  //     interpreter.
  //   Expression — Ref(Binary): generic Ref dispatch.
  //   Binary     — PrattBinary: fully declarative Pratt binary.
  //   Application— PrattApp: fully declarative Pratt left-assoc application.
  //   Atom       — Choice([…]) with Seq; ManualDefinition + ManualBlockDelimiterCheck
  //     appear as sub-expressions but Atom itself is a declarative Choice dispatch.
  //
  // Hardcoded (0): no per-rule special cases remain in run_expr.
  //
  // Escape hatch (2):
  //   Definition — ManualDefinition: parse_definition_ir dispatched via run_expr;
  //     complex let/fn logic not expressible with current IR combinators.
  //   ParamList  — ManualParamList: mark/start_at retroactive-wrap dance.
  //
  // Sub-rule combinator gaps (not rule-level escape hatches; counted in E2):
  //   ManualBlockDelimiterCheck — counted-repeat-with-conditional-diagnostic.
  //   ManualNewlineAppExpr      — context-sensitive allow_newline_application mode.
  E1Measurement::{
    total_rules: 7,
    declarative_rules: 5,
    hardcoded_rules: 0,
    escape_hatch_rules: 2,
  }
}

///|
/// Measure E2 escape hatches: lambda-specific code that cannot be expressed
/// in the current GrammarIr without adding new combinators.
pub fn measure_e2() -> E2Measurement {
  // P2 fixes: ManualBlockDelimiterCheck + ManualNewlineAppExpr added.
  // These are sub-rule combinator gaps — logic that belongs inside GrammarIr
  // combinators but cannot be expressed with the current set.
  //
  //   ManualParamList — retroactive-wrap (mark/start_at): combinator missing.
  //   ManualBlockDelimiterCheck — counted-repeat-with-conditional-diagnostic:
  //     RepeatWhile can loop but cannot count iterations or branch on the count.
  //   ManualNewlineAppExpr — context-sensitive allow_newline_application=true:
  //     PrattApp uses a fixed starts predicate; it cannot conditionally consume
  //     soft newlines between atoms depending on parse context.
  E2Measurement::{
    escape_hatch_count: 3,
    missing_combinators: [],
    escape_hatches: [
      (
        "ManualParamList", "ParamList requires mark/start_at retroactive-wrap to match A's CST shape; Seq+RepeatWhile alone cannot express the deferred node-open pattern",
      ),
      (
        "ManualBlockDelimiterCheck", "Block definition delimiter check requires counting consumed newlines and conditionally emitting a diagnostic; RepeatWhile cannot express count-gated conditionals",
      ),
      (
        "ManualNewlineAppExpr", "Top-level and block trailing expressions use allow_newline_application=true (soft newlines between atoms form AppExpr); PrattApp uses a fixed lookahead predicate and cannot vary newline-consumption by parse context",
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
  // Track 2: E3 probe complete. Seq, PrattBinary, PrattApp, RepeatWhile added.
  // JSON-shaped grammar (e3_oracle_wbtest.mbt): 5/5 rules declarative, D1 PASS.
  ReuseProbePlan::{
    target_grammar: "JSON (RFC 8259) structure over lambda's lexer: Integer=number, Identifier=string-like, Hole=null, LeftParen/RightParen=array, LBrace/RBrace=object, Eq=member separator.",
    required_extensions: [],
    expected_oracle_result: "D1 PASS — all E3 oracle fixtures pass (Track 2). No A-side for D2a (E3 has no hand-written parser). E3 grammar is 5/5 declarative with no escape hatches.",
    gate_condition: "E3 probe complete. Gate condition met: E3 grammar encodes all 5 rules declaratively (no ManualX), D1 oracle passes on array/object/nested fixtures.",
  }
}

///|
/// E3 gate: returns false when E3 probe is blocked on outstanding E2 issues.
/// When this returns false, the full GO decision should note that E3 requires
/// IR extensions before it can validate generalizability.
pub fn e3_follow_up_gate() -> (Bool, String) {
  // Track 2: Seq, PrattBinary, PrattApp added. E3 JSON-shaped grammar is 5/5
  // declarative and D1 oracle passes. ManualParamList remains but is
  // lambda-specific — it does not appear in the JSON grammar.
  (true, "Ready: E3 probe complete — 5/5 declarative, D1 PASS (Track 2).")
}
