// Private lexer-buffer probes for #838.

///|
fn perf_new_markdown_buffer(source : String) -> @core.TokenBuffer[Token] {
  let source_id = @core.SourceId("markdown-perf-buffer")
  @core.TokenBuffer::new_from_mode_relex(
    source_id,
    source,
    factory=mode_factory,
    eof_token=EOF,
  )
}

///|
fn bench_perf_buffer_build(b : @bench.T, count : Int) -> Unit {
  let source = perf_work_paragraph_doc(count)
  b.bench(fn() {
    let buffer = perf_new_markdown_buffer(source)
    b.keep(buffer.token_count())
    b.keep(buffer.get_diagnostics())
  })
}

///|
fn perf_parse_buffer(
  source_id : @core.SourceId,
  source : String,
  buffer : @core.TokenBuffer[Token],
) -> (@seam.CstNode, @core.DiagnosticSet, Int) {
  @core.parse_tokens_indexed(
    source_id,
    source,
    buffer.token_count(),
    fn(index) { buffer.get_token(index) },
    fn(index) { buffer.get_start(index) },
    fn(index) { buffer.get_end(index) },
    markdown_spec,
  )
}

///|
fn bench_perf_pretokenized_cst(b : @bench.T, count : Int) -> Unit {
  let source_id = @core.SourceId("markdown-perf-pretokenized-cst")
  let source = perf_work_paragraph_doc(count)
  let buffer = perf_new_markdown_buffer(source)
  b.bench(fn() {
    let (cst, diagnostics, reuse_count) = perf_parse_buffer(
      source_id, source, buffer,
    )
    b.keep(cst)
    b.keep(diagnostics)
    b.keep(reuse_count)
  })
}

///|
fn bench_perf_buffer_rebuild_cycle(b : @bench.T, count : Int) -> Unit {
  let source = perf_work_paragraph_doc(count)
  let (edited, _) = perf_work_middle_edit(source)
  b.bench(fn() {
    b.keep(perf_new_markdown_buffer(edited).token_count())
    b.keep(perf_new_markdown_buffer(source).token_count())
  })
}

///|
fn bench_perf_buffer_update_cycle(b : @bench.T, count : Int) -> Unit {
  let source = perf_work_paragraph_doc(count)
  let (edited, edit) = perf_work_middle_edit(source)
  let buffer = perf_new_markdown_buffer(source)
  b.bench(fn() {
    buffer.update(edit, edited) catch {
      _ => abort("incremental relex failed")
    }
    b.keep(buffer.token_count())
    buffer.update(edit, source) catch {
      _ => abort("restore relex failed")
    }
    b.keep(buffer.token_count())
  })
}

///|
test "perf envelope: token buffer build 10 paragraphs" (b : @bench.T) {
  bench_perf_buffer_build(b, 10)
}

///|
test "perf envelope: token buffer build 100 paragraphs" (b : @bench.T) {
  bench_perf_buffer_build(b, 100)
}

///|
test "perf envelope: token buffer build 500 paragraphs" (b : @bench.T) {
  bench_perf_buffer_build(b, 500)
}

///|
test "perf envelope: pretokenized CST 10 paragraphs" (b : @bench.T) {
  bench_perf_pretokenized_cst(b, 10)
}

///|
test "perf envelope: pretokenized CST 100 paragraphs" (b : @bench.T) {
  bench_perf_pretokenized_cst(b, 100)
}

///|
test "perf envelope: pretokenized CST 500 paragraphs" (b : @bench.T) {
  bench_perf_pretokenized_cst(b, 500)
}

///|
test "perf envelope: token buffer rebuild cycle 100 paragraphs" (b : @bench.T) {
  bench_perf_buffer_rebuild_cycle(b, 100)
}

///|
test "perf envelope: token buffer rebuild cycle 500 paragraphs" (b : @bench.T) {
  bench_perf_buffer_rebuild_cycle(b, 500)
}

///|
test "perf envelope: token buffer update cycle 100 paragraphs" (b : @bench.T) {
  bench_perf_buffer_update_cycle(b, 100)
}

///|
test "perf envelope: token buffer update cycle 500 paragraphs" (b : @bench.T) {
  bench_perf_buffer_update_cycle(b, 500)
}
