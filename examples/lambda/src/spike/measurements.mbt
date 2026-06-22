///|
/// E1 ergonomics measurement (RULE granularity): what fraction of lambda's
/// grammar rules are expressed as `@grammar.Expr` values in the rule Map — i.e.
/// driven by the tree-walking interpreter, with no host closure and no hardcoded
/// `parse_*_ir` function.
///
/// After the port to the reified `@grammar` IR (Tasks 6–8), all seven rules
/// reach this bar. The two spike escape hatches that kept E1 at 5/7 — Definition
/// (`ManualDefinition`) and ParamList (`ManualParamList`) — reified into ordinary
/// nodes (`Choice`/`Node`/`Seq` for Definition; `WrapIfNext` + a `Choice`/
/// `RepeatWhile` comma-loop for ParamList; spec §5.3).
pub struct E1Measurement {
  total_rules : Int
  declarative_rules : Int
  hardcoded_rules : Int
  escape_hatch_rules : Int
} derive(Debug, Eq)

///|
/// E2 ergonomics measurement (NODE granularity): the residue behaviors the
/// MINIMAL `@grammar` interpreter cannot fully drive, plus the vocabulary grown
/// to eliminate the rule-level hatches. Distinct from E1: a rule can be a fully
/// declarative IR value (counted declarative in E1) while still containing a node
/// whose behavior is held spike-local (counted here).
pub struct E2Measurement {
  /// Node-level residues held in the spike-local probe (`probe_interpreter.mbt`).
  residue_count : Int
  /// (residue name, why it does not reduce to the minimal `@grammar` contract).
  residues : Array[(String, String)]
  /// `@grammar.Expr` nodes grown from the spike's escape hatches to reach
  /// E1 = 7/7 (spec §5.3). Each reifies an existing, tested `ParserContext`
  /// method — IR surface grew, parser behavior did not.
  grown_nodes : Array[String]
} derive(Debug)

///|
/// Measure E1 rule coverage for the reified lambda grammar IR
/// (`lambda_grammar_ir`).
///
/// Declarative: the rule is a `@grammar.Expr` value in the Map, dispatched by the
/// interpreter. Hardcoded: logic lives in a named `parse_*_ir` function called
/// directly (none remain — all deleted in the port). Escape hatch: a rule
/// represented by a `Manual*` variant bypassing the interpreter (none remain at
/// rule level — the lone residues are node behaviors, counted in E2).
pub fn measure_e1() -> E1Measurement {
  // Seven rules, all `@grammar.Expr` values in `lambda_grammar_ir`:
  //   source      — Seq[RepeatTopLevel, trailing Choice, …]
  //   definition  — Choice over let/fn (Node + Seq + EmitOr/DiagnoseIf/…)
  //   expression  — Ref(binary)
  //   binary      — PrattBinary
  //   application — PrattApp
  //   atom        — Choice([…]) (contains the two E2 node residues, but the rule
  //                 itself is a declarative Choice value)
  //   param_list  — WrapIfNext + Choice/RepeatWhile comma-loop
  //
  // Hardcoded (0): parse_definition_ir / parse_param_list_exact /
  //   parse_block_delimiter_check / parse_*_ir all deleted in the port.
  // Escape hatch (0): no rule is a Manual* bypass; ManualDefinition and
  //   ManualParamList reified (spec §5.3).
  E1Measurement::{
    total_rules: 7,
    declarative_rules: 7,
    hardcoded_rules: 0,
    escape_hatch_rules: 0,
  }
}

///|
/// Measure E2 node residues for the reified lambda grammar IR.
///
/// `cripple_reuse` is deliberately NOT a residue: it is a harness-only positive
/// control (spec §3.1) the probe gates `RepeatTopLevel` on; no grammar value
/// carries it.
pub fn measure_e2() -> E2Measurement {
  E2Measurement::{
    residue_count: 2,
    residues: [
      (
        "ManualNewlineAppExpr", "recursive newline-application mode (allow_newline_application) threaded through binary/application/atom/paren recursion in cst_parser.mbt; a flat IR node cannot carry recursion-threaded state, so @grammar.interpret placeholders it and the probe runs parse_newline_app",
      ),
      (
        "AtomPositionErrorRecovery", "A's parse_atom fallthrough (parse_error_node_until) opens an ErrorNode holding an error placeholder at a sync point; neither @grammar.ErrorUntil (error + skip) nor ErrorNodeUntil (error + bump, empty at a sync point) expresses the at-sync placeholder, so the probe special-cases the ErrorUntil arm",
      ),
    ],
    grown_nodes: [
      "Fail", "EmitOr", "DiagnoseIf", "ExpectSkip", "ConsumeGated", "RequireSep",
      "ErrorNodeUntil",
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
/// E3 probe (the second-grammar generalization check).
///
/// E3 asks: "If we build a SECOND grammar (not lambda) on the reified IR, do the
/// safety oracles still hold, and how much escape-hatch accumulation does it
/// require?" The answer is the strongest cross-language signal in the spike: the
/// JSON grammar (`e3_oracle_wbtest.mbt`) encodes all five rules in `@grammar` IR
/// with ZERO residues and drives `@grammar.interpret` DIRECTLY — no spike-local
/// probe. Lambda needs the probe; JSON does not, which is exactly the evidence
/// that the residues are lambda-specific and the minimal contract stands alone.
pub struct ReuseProbePlan {
  /// Description of the second grammar built for the E3 probe.
  target_grammar : String
  /// IR extensions required before the probe is executable (empty — the grown
  /// vocabulary already covers JSON).
  required_extensions : Array[String]
  /// Expected safety-oracle outcomes for the JSON grammar.
  expected_oracle_result : String
  /// Gate condition: E3 is meaningful when this holds.
  gate_condition : String
} derive(Debug)

///|
/// Return the E3 follow-up probe plan.
pub fn e3_probe_plan() -> ReuseProbePlan {
  ReuseProbePlan::{
    target_grammar: "JSON (RFC 8259) structure over lambda's lexer: Integer=number, Identifier=string-like, Hole=null, LeftParen/RightParen=array, LBrace/RBrace=object, Eq=member separator.",
    required_extensions: [],
    expected_oracle_result: "D1 PASS on array/object/nested/missing-key/trailing-token fixtures. No A-side (JSON has no hand-written parser, so D1 is incremental-vs-full self-consistency). The JSON grammar is 5/5 declarative AND drives @grammar.interpret directly — no spike-local probe, no residue.",
    gate_condition: "Met: JSON encodes all 5 rules as @grammar IR with zero residues; build_e3_grammar uses @grammar.interpret (not the lambda probe); D1 oracle passes.",
  }
}

///|
/// E3 gate: true when the second-grammar probe is meaningful and passing.
pub fn e3_follow_up_gate() -> (Bool, String) {
  (
    true, "Ready: JSON E3 is 5/5 declarative, drives @grammar.interpret directly with no probe, D1 PASS.",
  )
}
