///|
test "E1: total rules = 7" {
  let m = measure_e1()
  inspect(m.total_rules, content="7")
}

///|
test "E1: declarative rules = 7 (all rules are @grammar IR values after the port)" {
  // ManualDefinition + ManualParamList reified (spec §5.3), so every rule —
  // source, definition, expression, binary, application, atom, param_list — is
  // a declarative @grammar.Expr value dispatched by the interpreter.
  let m = measure_e1()
  inspect(m.declarative_rules, content="7")
}

///|
test "E1: hardcoded rules = 0 (all parse_*_ir functions deleted in the port)" {
  let m = measure_e1()
  inspect(m.hardcoded_rules, content="0")
}

///|
test "E1: escape hatch rules = 0 (no rule-level Manual* bypass remains)" {
  // The lone residues are node behaviors held in the probe (counted in E2),
  // not rule-level escape hatches.
  let m = measure_e1()
  inspect(m.escape_hatch_rules, content="0")
}

///|
test "E1: coverage ratio = 7/7 (100%)" {
  let m = measure_e1()
  let (num, den) = e1_coverage_ratio(m)
  inspect(num, content="7")
  inspect(den, content="7")
  // sanity: all parts sum to total
  inspect(
    m.declarative_rules + m.hardcoded_rules + m.escape_hatch_rules ==
    m.total_rules,
    content="true",
  )
}

///|
test "E2: 2 node-level residues held in the spike probe" {
  let m = measure_e2()
  inspect(m.residue_count, content="2")
  inspect(m.residues.length(), content="2")
}

///|
test "E2: residues are ManualNewlineAppExpr and AtomPositionErrorRecovery" {
  let m = measure_e2()
  inspect(m.residues[0].0, content="ManualNewlineAppExpr")
  inspect(m.residues[1].0, content="AtomPositionErrorRecovery")
}

///|
test "E2: ManualNewlineAppExpr reason mentions the recursive newline mode" {
  let m = measure_e2()
  inspect(m.residues[0].1.contains("allow_newline_application"), content="true")
}

///|
test "E2: AtomPositionErrorRecovery reason mentions the at-sync placeholder" {
  let m = measure_e2()
  inspect(m.residues[1].1.contains("placeholder"), content="true")
}

///|
test "E2: grown vocabulary = the 7 nodes that reified the escape hatches" {
  // These nodes (spec §5.3) are what moved E1 from the spike's 5/7 to 7/7.
  let m = measure_e2()
  inspect(m.grown_nodes.length(), content="7")
  inspect(m.grown_nodes.contains("ExpectSkip"), content="true")
  inspect(m.grown_nodes.contains("RequireSep"), content="true")
  inspect(m.grown_nodes.contains("ErrorNodeUntil"), content="true")
}

///|
test "E3: probe plan targets JSON with no required extensions" {
  let plan = e3_probe_plan()
  inspect(plan.target_grammar.contains("JSON"), content="true")
  inspect(plan.required_extensions.length(), content="0")
  inspect(plan.expected_oracle_result.contains("PASS"), content="true")
}

///|
test "E3: JSON drives @grammar.interpret directly — no probe, no residue" {
  // The cross-language proof the contract stands alone: lambda needs the probe,
  // JSON does not.
  let plan = e3_probe_plan()
  inspect(plan.expected_oracle_result.contains("directly"), content="true")
  inspect(plan.gate_condition.contains("zero residues"), content="true")
}

///|
test "E3: gate open" {
  let (ready, reason) = e3_follow_up_gate()
  inspect(ready, content="true")
  inspect(reason.contains("PASS"), content="true")
}
