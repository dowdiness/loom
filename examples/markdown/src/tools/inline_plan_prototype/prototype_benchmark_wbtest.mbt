// Throwaway benchmark for #890. It measures only the pure prototype planner;
// scenario construction and production lexing stay outside the timed closure.

///|
fn benchmark_prototype_kind(
  b : @bench.T,
  kind : String,
  base_count : Int,
) -> Unit {
  let counts = [base_count - 1, base_count, base_count + 1, base_count + 2]
  let scenarios = counts.map(count => {
    if kind == "segmented" {
      segmented_stress_scenario(count)
    } else {
      stress_scenario(kind, count)
    }
  })
  let boundaries = scenarios.map(scenario => {
    boundary_evidence_or_abort(scenario.source)
  })
  b.bench(() => {
    for index, scenario in scenarios {
      let report = analyze_without_lexer(scenario, boundaries[index])
      b.keep(report.work.source_units)
      b.keep(report.work.candidate_units)
      b.keep(report.work.ordering_units)
      b.keep(report.work.resolver_steps)
      b.keep(report.work.mapping_steps)
    }
  })
}

///|
fn benchmark_prototype_end_to_end(
  b : @bench.T,
  kind : String,
  base_count : Int,
) -> Unit {
  let counts = [base_count - 1, base_count, base_count + 1, base_count + 2]
  let scenarios = counts.map(count => {
    if kind == "segmented" {
      segmented_stress_scenario(count)
    } else {
      stress_scenario(kind, count)
    }
  })
  b.bench(() => {
    for scenario in scenarios {
      let evidence = boundary_evidence_or_abort(scenario.source)
      let report = analyze_without_lexer(scenario, evidence)
      b.keep(report.work.source_units)
      b.keep(report.work.candidate_units)
      b.keep(report.work.ordering_units)
      b.keep(report.work.resolver_steps)
      b.keep(report.work.mapping_steps)
    }
  })
}

///|
test "prototype planner: angle-free 256 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "plain", 256)
}

///|
test "prototype planner: greater-than-heavy 256 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "greater", 256)
}

///|
test "prototype planner: angle-heavy 64 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "angle", 64)
}

///|
test "prototype planner: angle-heavy 128 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "angle", 128)
}

///|
test "prototype planner: angle-heavy 256 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "angle", 256)
}

///|
test "prototype planner: angle-heavy 512 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "angle", 512)
}

///|
test "prototype planner: angle-heavy 1024 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "angle", 1024)
}

///|
test "prototype planner: unclosed-angle 1024 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "unclosed-angle", 1024)
}

///|
test "prototype planner: shared-angle-closer 1024 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "shared-angle-closer", 1024)
}

///|
test "prototype planner: unclosed-link 1024 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "unclosed-link", 1024)
}

///|
test "prototype planner: segmented 256 motifs" (b : @bench.T) {
  benchmark_prototype_kind(b, "segmented", 256)
}

///|
test "prototype end-to-end: angle-free 256 motifs" (b : @bench.T) {
  benchmark_prototype_end_to_end(b, "plain", 256)
}

///|
test "prototype end-to-end: angle-heavy 256 motifs" (b : @bench.T) {
  benchmark_prototype_end_to_end(b, "angle", 256)
}

///|
test "prototype end-to-end: shared-angle-closer 1024 motifs" (b : @bench.T) {
  benchmark_prototype_end_to_end(b, "shared-angle-closer", 1024)
}

///|
test "prototype end-to-end: segmented 256 motifs" (b : @bench.T) {
  benchmark_prototype_end_to_end(b, "segmented", 256)
}
