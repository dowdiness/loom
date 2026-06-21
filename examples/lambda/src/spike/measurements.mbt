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
      "Seq — sequential composition of tokens/exprs in a single rule body",
      "Pratt — infix operator table for binary expressions and left-associative application",
    ],
    escape_hatches: [
      (
        "ManualAtom",
        "Atom requires Seq to express 'EmitToken + recurse + ExpectToken' (paren expr) and multi-branch dispatch with embedded token emission (block, literal, ident)",
      ),
      (
        "ManualParamList",
        "ParamList is a comma-delimited identifier loop; requires Seq + RepeatWhile with separator, not expressible with current IR combinators",
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
