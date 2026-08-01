// Private lexer-buffer probes for #838.

///|
fn perf_new_markdown_buffer(source : String) -> @core.TokenBuffer[Token] {
  let source_id = @core.SourceId("markdown-perf-buffer")
  let (state, initial) = mode_factory
    .new_session_with_initial(source_id, source)
    .unwrap()
  let initial_pending : Ref[Bool] = Ref(true)
  let lex = current_source => {
    if initial_pending.val {
      initial_pending.val = false
      initial
    } else {
      (mode_factory.tokenize)(source_id, current_source)
    }
  }
  @core.TokenBuffer::new_from_lex(
    source_id,
    source,
    lex_fn=lex,
    eof_token=EOF,
    mode_relex=Some(state),
  )
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
