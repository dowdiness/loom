// Throwaway #872 benchmark for event attribution while temporary core
// prototype APIs exist. Every stage times the split pipeline independently:
// pretokenized CST (production path), event generation (prototype path), and
// warm green build (prototype path). Scales and corpus order follow
// event_attribution_corpus_matrix.

///|
fn bench_event_attribution_pretokenized(
  b : @bench.T,
  corpus : EventAttributionCorpus,
) -> Unit {
  let source_id = @core.SourceId(
    "markdown-event-attribution-pretokenized:" + corpus.name,
  )
  let buffer = perf_new_markdown_buffer(corpus.source)
  b.bench(fn() {
    let (cst, diagnostics, reuse_count) = perf_parse_buffer(
      source_id,
      corpus.source,
      buffer,
    )
    b.keep(cst)
    b.keep(diagnostics)
    b.keep(reuse_count)
  })
}

///|
fn bench_event_attribution_event_generation(
  b : @bench.T,
  corpus : EventAttributionCorpus,
) -> Unit {
  let source_id = @core.SourceId(
    "markdown-event-attribution-events:" + corpus.name,
  )
  let buffer = perf_new_markdown_buffer(corpus.source)
  b.bench(fn() {
    let (events, diagnostics, reuse_count) = @core.prototype_parse_tokens_to_events(
      source_id,
      corpus.source,
      buffer.token_count(),
      index => buffer.get_token(index),
      index => buffer.get_start(index),
      index => buffer.get_end(index),
      markdown_spec,
    )
    b.keep(events.length())
    b.keep(diagnostics)
    b.keep(reuse_count)
  })
}

///|
fn bench_event_attribution_green_build(
  b : @bench.T,
  corpus : EventAttributionCorpus,
) -> Unit {
  let source_id = @core.SourceId(
    "markdown-event-attribution-warm-green:" + corpus.name,
  )
  let buffer = perf_new_markdown_buffer(corpus.source)
  // Warm green timing must not be added to event-generation timing.
  let (events, _, _) = @core.prototype_parse_tokens_to_events(
    source_id,
    corpus.source,
    buffer.token_count(),
    index => buffer.get_token(index),
    index => buffer.get_start(index),
    index => buffer.get_end(index),
    markdown_spec,
  )
  b.bench(fn() {
    b.keep(@core.prototype_build_event_buffer(events, markdown_spec))
  })
}

///|
test "event attribution: paragraph pretokenized 64" (b : @bench.T) {
  bench_event_attribution_pretokenized(
    b,
    event_attribution_corpus_matrix(64)[0],
  )
}

///|
test "event attribution: paragraph events 64" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(64)[0],
  )
}

///|
test "event attribution: paragraph warm green 64" (b : @bench.T) {
  bench_event_attribution_green_build(b, event_attribution_corpus_matrix(64)[0])
}

///|
test "event attribution: mixed pretokenized 64" (b : @bench.T) {
  bench_event_attribution_pretokenized(
    b,
    event_attribution_corpus_matrix(64)[1],
  )
}

///|
test "event attribution: mixed events 64" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(64)[1],
  )
}

///|
test "event attribution: mixed warm green 64" (b : @bench.T) {
  bench_event_attribution_green_build(b, event_attribution_corpus_matrix(64)[1])
}

///|
test "event attribution: delimiter-heavy pretokenized 64" (b : @bench.T) {
  bench_event_attribution_pretokenized(
    b,
    event_attribution_corpus_matrix(64)[2],
  )
}

///|
test "event attribution: delimiter-heavy events 64" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(64)[2],
  )
}

///|
test "event attribution: delimiter-heavy warm green 64" (b : @bench.T) {
  bench_event_attribution_green_build(b, event_attribution_corpus_matrix(64)[2])
}

///|
test "event attribution: recovery-heavy pretokenized 64" (b : @bench.T) {
  bench_event_attribution_pretokenized(
    b,
    event_attribution_corpus_matrix(64)[3],
  )
}

///|
test "event attribution: recovery-heavy events 64" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(64)[3],
  )
}

///|
test "event attribution: recovery-heavy warm green 64" (b : @bench.T) {
  bench_event_attribution_green_build(b, event_attribution_corpus_matrix(64)[3])
}

///|
test "event attribution: html pretokenized 64" (b : @bench.T) {
  bench_event_attribution_pretokenized(
    b,
    event_attribution_corpus_matrix(64)[4],
  )
}

///|
test "event attribution: html events 64" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(64)[4],
  )
}

///|
test "event attribution: html warm green 64" (b : @bench.T) {
  bench_event_attribution_green_build(b, event_attribution_corpus_matrix(64)[4])
}

///|
test "event attribution: fenced-code pretokenized 64" (b : @bench.T) {
  bench_event_attribution_pretokenized(
    b,
    event_attribution_corpus_matrix(64)[5],
  )
}

///|
test "event attribution: fenced-code events 64" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(64)[5],
  )
}

///|
test "event attribution: fenced-code warm green 64" (b : @bench.T) {
  bench_event_attribution_green_build(b, event_attribution_corpus_matrix(64)[5])
}

///|
test "event attribution: nested-container pretokenized 64" (b : @bench.T) {
  bench_event_attribution_pretokenized(
    b,
    event_attribution_corpus_matrix(64)[6],
  )
}

///|
test "event attribution: nested-container events 64" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(64)[6],
  )
}

///|
test "event attribution: nested-container warm green 64" (b : @bench.T) {
  bench_event_attribution_green_build(b, event_attribution_corpus_matrix(64)[6])
}

///|
test "event attribution: paragraph events 256" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(256)[0],
  )
}

///|
test "event attribution: paragraph warm green 256" (b : @bench.T) {
  bench_event_attribution_green_build(
    b,
    event_attribution_corpus_matrix(256)[0],
  )
}

///|
test "event attribution: mixed events 256" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(256)[1],
  )
}

///|
test "event attribution: mixed warm green 256" (b : @bench.T) {
  bench_event_attribution_green_build(
    b,
    event_attribution_corpus_matrix(256)[1],
  )
}

///|
test "event attribution: delimiter-heavy events 256" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(256)[2],
  )
}

///|
test "event attribution: delimiter-heavy warm green 256" (b : @bench.T) {
  bench_event_attribution_green_build(
    b,
    event_attribution_corpus_matrix(256)[2],
  )
}

///|
test "event attribution: recovery-heavy events 256" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(256)[3],
  )
}

///|
test "event attribution: recovery-heavy warm green 256" (b : @bench.T) {
  bench_event_attribution_green_build(
    b,
    event_attribution_corpus_matrix(256)[3],
  )
}

///|
test "event attribution: html events 256" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(256)[4],
  )
}

///|
test "event attribution: html warm green 256" (b : @bench.T) {
  bench_event_attribution_green_build(
    b,
    event_attribution_corpus_matrix(256)[4],
  )
}

///|
test "event attribution: fenced-code events 256" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(256)[5],
  )
}

///|
test "event attribution: fenced-code warm green 256" (b : @bench.T) {
  bench_event_attribution_green_build(
    b,
    event_attribution_corpus_matrix(256)[5],
  )
}

///|
test "event attribution: nested-container events 256" (b : @bench.T) {
  bench_event_attribution_event_generation(
    b,
    event_attribution_corpus_matrix(256)[6],
  )
}

///|
test "event attribution: nested-container warm green 256" (b : @bench.T) {
  bench_event_attribution_green_build(
    b,
    event_attribution_corpus_matrix(256)[6],
  )
}
