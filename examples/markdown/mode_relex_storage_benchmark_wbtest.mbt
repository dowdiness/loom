// Isolate block reparse and mode-state synchronization from TokenBuffer work.
//
// These benchmarks preserve the causal evidence for equal-length local edits:
// block reparse should stay local, and parallel lexer storage should not be
// rebuilt across the unchanged document suffix.

///|
fn bench_perf_block_reparse_cycle(b : @bench.T, count : Int) -> Unit {
  let source_id = @core.SourceId("markdown-block-reparse-benchmark")
  let source = perf_work_paragraph_doc(count)
  let (edited, edit) = perf_work_middle_edit(source)
  let (initial_cst, initial_diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("initial parse failed")
  }
  let mut syntax = @seam.SyntaxNode::from_cst(initial_cst)
  let mut diagnostics = initial_diagnostics
  b.bench(fn() {
    let (edited_cst, edited_diagnostics) = @core.reparse_block(
      source_id, syntax, edited, edit, lex_for_grammar, markdown_spec, markdown_block_reparse_spec,
      diagnostics,
    ).unwrap()
    syntax = @seam.SyntaxNode::from_cst(edited_cst)
    diagnostics = edited_diagnostics
    b.keep(syntax)
    let (restored_cst, restored_diagnostics) = @core.reparse_block(
      source_id, syntax, source, edit, lex_for_grammar, markdown_spec, markdown_block_reparse_spec,
      diagnostics,
    ).unwrap()
    syntax = @seam.SyntaxNode::from_cst(restored_cst)
    diagnostics = restored_diagnostics
    b.keep(syntax)
  })
}

///|
fn perf_mode_relex_left_token(starts : Array[Int], edit_start : Int) -> Int {
  let mut left = 0
  while left + 1 < starts.length() && starts[left + 1] <= edit_start {
    left = left + 1
  }
  if left > 0 {
    left - 1
  } else {
    left
  }
}

///|
fn bench_perf_mode_relex_cycle(b : @bench.T, count : Int) -> Unit {
  let source_id = @core.SourceId("markdown-mode-relex-benchmark")
  let source = perf_work_paragraph_doc(count)
  let (edited, edit) = perf_work_middle_edit(source)
  let (state, initial) = mode_factory
    .new_session_with_initial(source_id, source)
    .unwrap()
  let starts = initial.starts()
  let left = perf_mode_relex_left_token(starts, edit.start)
  b.bench(fn() {
    b.keep(
      (state.relex_from)(
        edited,
        starts[left],
        left,
        starts.length(),
        starts,
        edit.delta(),
        edit.new_end(),
      ),
    )
    b.keep(
      (state.relex_from)(
        source,
        starts[left],
        left,
        starts.length(),
        starts,
        edit.delta(),
        edit.new_end(),
      ),
    )
  })
}

///|
test "perf envelope: isolated block reparse cycle 10 paragraphs" (b : @bench.T) {
  bench_perf_block_reparse_cycle(b, 10)
}

///|
test "perf envelope: isolated block reparse cycle 100 paragraphs" (b : @bench.T) {
  bench_perf_block_reparse_cycle(b, 100)
}

///|
test "perf envelope: isolated block reparse cycle 500 paragraphs" (b : @bench.T) {
  bench_perf_block_reparse_cycle(b, 500)
}

///|
test "perf envelope: isolated mode relex cycle 10 paragraphs" (b : @bench.T) {
  bench_perf_mode_relex_cycle(b, 10)
}

///|
test "perf envelope: isolated mode relex cycle 100 paragraphs" (b : @bench.T) {
  bench_perf_mode_relex_cycle(b, 100)
}

///|
test "perf envelope: isolated mode relex cycle 500 paragraphs" (b : @bench.T) {
  bench_perf_mode_relex_cycle(b, 500)
}

///|
test "core ownership: equal-cardinality mode relex cycle 500 paragraphs" (
  b : @bench.T,
) {
  // `perf_work_middle_edit` replaces one code unit with one code unit. Keep
  // this row as the direct old-offset handoff baseline for Phase 1.
  bench_perf_mode_relex_cycle(b, 500)
}
