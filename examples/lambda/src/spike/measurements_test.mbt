test "E1: total rules = 7" {
  let m = measure_e1()
  inspect(m.total_rules, content="7")
}

test "E1: declarative rules = 1 (Source only)" {
  // Only Source (RepeatTopLevel) is dispatched through the IR generically.
  // All other rules are hardcoded or escape-hatched.
  let m = measure_e1()
  inspect(m.declarative_rules, content="1")
}

test "E1: hardcoded rules = 4 (Definition, Binary, Application, Expression)" {
  // These rules use named parse_*_ir functions called directly, not via
  // the generic IR interpreter dispatch.
  let m = measure_e1()
  inspect(m.hardcoded_rules, content="4")
}

test "E1: escape hatch rules = 2 (Atom, ParamList)" {
  // ManualAtom and ManualParamList are lambda-specific bypasses.
  let m = measure_e1()
  inspect(m.escape_hatch_rules, content="2")
}

test "E1: coverage ratio = 1/7 (~14%)" {
  let m = measure_e1()
  let (num, den) = e1_coverage_ratio(m)
  inspect(num, content="1")
  inspect(den, content="7")
  // sanity: all parts sum to total
  inspect(m.declarative_rules + m.hardcoded_rules + m.escape_hatch_rules == m.total_rules, content="true")
}

test "E2: 2 lambda-specific escape hatches" {
  let m = measure_e2()
  inspect(m.escape_hatch_count, content="2")
}

test "E2: 2 missing combinators (Seq, Pratt)" {
  let m = measure_e2()
  inspect(m.missing_combinators.length(), content="2")
  inspect(m.missing_combinators[0].contains("Seq"), content="true")
  inspect(m.missing_combinators[1].contains("Pratt"), content="true")
}

test "E2: escape hatch names are ManualAtom and ManualParamList" {
  let m = measure_e2()
  inspect(m.escape_hatches.length(), content="2")
  inspect(m.escape_hatches[0].0, content="ManualAtom")
  inspect(m.escape_hatches[1].0, content="ManualParamList")
}

test "E2: ManualAtom reason mentions Seq" {
  let m = measure_e2()
  inspect(m.escape_hatches[0].1.contains("Seq"), content="true")
}

test "E2: ManualParamList reason mentions Seq and RepeatWhile" {
  let m = measure_e2()
  inspect(m.escape_hatches[1].1.contains("Seq"), content="true")
  inspect(m.escape_hatches[1].1.contains("RepeatWhile"), content="true")
}
