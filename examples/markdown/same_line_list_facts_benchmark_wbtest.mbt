// Same-line list marker guard benchmark.
//
// This keeps the source line in the prefix-heavy case where lex_inline
// repeatedly consults the cached line facts.

///|
fn same_line_list_facts_benchmark_input(
  marker_count : Int,
) -> (String, Array[Int]) {
  let source = "- ".repeat(marker_count) + "text\n"
  let positions : Array[Int] = []
  for i = 0; i < marker_count; i = i + 1 {
    positions.push(i * 2)
  }
  (source, positions)
}

///|
fn same_line_list_facts_workload(
  source : String,
  positions : Array[Int],
) -> Int {
  let session = MarkdownLexSession()
  let mut checksum = 0
  for pos in positions {
    let (step, _) = session.step(source, pos, Inline)
    checksum += next_lex_step_offset(step, source)
  }
  checksum
}

///|
fn same_line_list_facts_stateless_workload(
  source : String,
  positions : Array[Int],
) -> Int {
  let mut checksum = 0
  for pos in positions {
    let (step, _) = markdown_lex_step(source, pos, Inline)
    checksum += next_lex_step_offset(step, source)
  }
  checksum
}

///|
test "same-line list facts: 1024 markers" (b : @bench.T) {
  let (source, positions) = same_line_list_facts_benchmark_input(1024)
  b.bench(() => b.keep(same_line_list_facts_workload(source, positions)))
}

///|
test "same-line list facts: 1024 markers stateless control" (b : @bench.T) {
  let (source, positions) = same_line_list_facts_benchmark_input(1024)
  b.bench(() => {
    b.keep(same_line_list_facts_stateless_workload(source, positions))
  })
}
