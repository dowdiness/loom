///|
test "E1: total rules = 7" {
  let m = measure_e1()
  inspect(m.total_rules, content="7")
}

///|
test "E1: declarative rules = 5 (Source, Expression, Binary, Application, Atom)" {
  // Track 2: Seq + PrattBinary + PrattApp wired. ManualAtom removed.
  // Source, Expression (Ref), Binary (PrattBinary), Application (PrattApp),
  // Atom (Choice+Seq) all dispatch generically through run_expr.
  let m = measure_e1()
  inspect(m.declarative_rules, content="5")
}

///|
test "E1: hardcoded rules = 0 (no special cases remain in run_expr)" {
  // Track 2 removed parse_binary_ir, parse_application_ir, parse_atom_ir,
  // and the Ref(Application)/Ref(Binary) special cases from run_expr.
  let m = measure_e1()
  inspect(m.hardcoded_rules, content="0")
}

///|
test "E1: escape hatch rules = 2 (Definition, ParamList)" {
  // Definition: parse_top_level_repeat calls parse_definition_ir directly.
  // ParamList: ManualParamList — retroactive wrap cannot be expressed in IR.
  let m = measure_e1()
  inspect(m.escape_hatch_rules, content="2")
}

///|
test "E1: coverage ratio = 5/7 (~71%)" {
  let m = measure_e1()
  let (num, den) = e1_coverage_ratio(m)
  inspect(num, content="5")
  inspect(den, content="7")
  // sanity: all parts sum to total
  inspect(
    m.declarative_rules + m.hardcoded_rules + m.escape_hatch_rules ==
    m.total_rules,
    content="true",
  )
}

///|
test "E2: 1 lambda-specific escape hatch (ManualParamList)" {
  // ManualAtom removed in Track 2. Only ManualParamList remains.
  let m = measure_e2()
  inspect(m.escape_hatch_count, content="1")
}

///|
test "E2: 0 missing combinators (Seq and Pratt added in Track 2)" {
  let m = measure_e2()
  inspect(m.missing_combinators.length(), content="0")
}

///|
test "E2: escape hatch name is ManualParamList" {
  let m = measure_e2()
  inspect(m.escape_hatches.length(), content="1")
  inspect(m.escape_hatches[0].0, content="ManualParamList")
}

///|
test "E2: ManualParamList reason mentions retroactive-wrap" {
  let m = measure_e2()
  inspect(m.escape_hatches[0].1.contains("retroactive"), content="true")
}

///|
test "E3: probe plan targets JSON grammar" {
  let plan = e3_probe_plan()
  inspect(plan.target_grammar.contains("JSON"), content="true")
  // Track 2 complete: no remaining required extensions.
  inspect(plan.required_extensions.length(), content="0")
  inspect(plan.expected_oracle_result.contains("PASS"), content="true")
}

///|
test "E3: gate open — probe complete (Track 2)" {
  let (ready, reason) = e3_follow_up_gate()
  inspect(ready, content="true")
  inspect(reason.contains("PASS"), content="true")
}

///|
test "E3: gate consistent with E2 state" {
  // ManualParamList remains but does not block E3 (JSON grammar has no param list).
  let e2 = measure_e2()
  let (gate_open, _) = e3_follow_up_gate()
  inspect(e2.escape_hatch_count, content="1")
  inspect(gate_open, content="true")
}
