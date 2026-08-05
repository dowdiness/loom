// Deterministic pretokenized-parser attribution probes for #872.
//
// Behavioral boundary matrix:
// - paragraph: continuation/lookahead and ordinary Text payloads
// - mixed: block dispatch, continuation, inline analysis, and event emission
// - delimiter-heavy: code/link/emphasis analysis and backtick negative control
// - recovery-heavy: literal fallback, error nodes, and diagnostics
// - raw HTML: HtmlBlockOpen/HtmlText payload materialization
// - fenced code: CodeFenceOpen/CodeText payload materialization
// - nested containers: block-quote dispatch and continuation
//
// Every row compares the instrumented pretokenized path with production
// parse_cst output. Representative and stress scales reuse the same matrix.

///|
priv struct EventAttributionCorpus {
  name : String
  source : String
}

///|
priv struct EventAttributionPayloadStats {
  copies : Int
  units : Int
  text_units : Int
  html_units : Int
  code_units : Int
  indentation_units : Int
  fence_info_units : Int
  error_units : Int
  backtick_tokens : Int
}

///|
priv struct EventAttributionSnapshot {
  cst : @seam.CstNode
  diagnostics : @core.DiagnosticSet
  token_count : Int
  token_reads : Array[Int]
  start_reads : Array[Int]
  end_reads : Array[Int]
  cst_tokens : Int
  cst_branches : Int
  retained_event_lower_bound : Int
  payload : EventAttributionPayloadStats
}

///|
fn event_attribution_corpus_matrix(
  scale : Int,
) -> Array[EventAttributionCorpus] {
  guard scale > 0 else { abort("event-attribution scale must be positive") }
  let delimiter = delimiter_performance_workloads(scale)
  let mixed_section = "## Section\n\nParagraph with **bold**, *italic*, `code`, and [link](/url).\n" +
    "Continuation line.\n\n- first item\n- second item\n\n" +
    "```moonbit\nfn item() -> Int { 1 }\n```\n\n"
  let recovery_case = "case: \\*literal* \\*\\*literal** \\\\*em* \\*😈* " +
    "\\* literal *unclosed\n[\\*literal*](/) \\*a \\*b***\n\n"
  let html_block = "<div data-row=\"x\">\nraw <span>payload</span>\n</div>\n\n"
  let fenced_block = "```moonbit\nfn item() -> Int {\n  1\n}\n```\n"
  [
    { name: "paragraph", source: perf_work_paragraph_doc(scale) },
    { name: "mixed", source: mixed_section.repeat(scale) },
    { name: "delimiter-heavy", source: delimiter.delimiter_heavy.source },
    { name: "recovery-heavy", source: recovery_case.repeat(scale) },
    { name: "html", source: html_block.repeat(scale) },
    { name: "fenced-code", source: fenced_block.repeat(scale) },
    {
      name: "nested-container",
      source: line_end_cache_nested_quote_doc(8, scale),
    },
  ]
}

///|
fn event_attribution_payload_stats(
  buffer : @core.TokenBuffer[Token],
) -> EventAttributionPayloadStats {
  let mut copies = 0
  let mut units = 0
  let mut text_units = 0
  let mut html_units = 0
  let mut code_units = 0
  let mut indentation_units = 0
  let mut fence_info_units = 0
  let mut error_units = 0
  let mut backtick_tokens = 0
  for index = 0; index < buffer.token_count(); index = index + 1 {
    match buffer.get_token(index) {
      Text(text) => {
        copies += 1
        units += text.length()
        text_units += text.length()
      }
      HtmlBlockOpen(text) | HtmlText(text) => {
        copies += 1
        units += text.length()
        html_units += text.length()
      }
      CodeText(text) => {
        copies += 1
        units += text.length()
        code_units += text.length()
      }
      Indentation(text) => {
        copies += 1
        units += text.length()
        indentation_units += text.length()
      }
      CodeFenceOpen(_, info) => {
        copies += 1
        units += info.length()
        fence_info_units += info.length()
      }
      Error(message) => {
        copies += 1
        units += message.length()
        error_units += message.length()
      }
      Backtick => backtick_tokens += 1
      _ => ()
    }
  }
  {
    copies,
    units,
    text_units,
    html_units,
    code_units,
    indentation_units,
    fence_info_units,
    error_units,
    backtick_tokens,
  }
}

///|
fn event_attribution_snapshot(
  corpus : EventAttributionCorpus,
) -> EventAttributionSnapshot {
  let source_id = @core.SourceId(
    "markdown-event-attribution-oracle:" + corpus.name,
  )
  let buffer = perf_new_markdown_buffer(corpus.source)
  let token_count = buffer.token_count()
  let token_reads = Array::make(token_count, 0)
  let start_reads = Array::make(token_count, 0)
  let end_reads = Array::make(token_count, 0)
  let (cst, diagnostics, reuse_count) = @core.parse_tokens_indexed(
    source_id,
    corpus.source,
    token_count,
    index => {
      token_reads[index] += 1
      buffer.get_token(index)
    },
    index => {
      start_reads[index] += 1
      buffer.get_start(index)
    },
    index => {
      end_reads[index] += 1
      buffer.get_end(index)
    },
    markdown_spec,
  )
  guard reuse_count == 0 else {
    abort("fresh event-attribution parse unexpectedly reused a CST node")
  }
  let mut cst_tokens = 0
  let mut cst_branches = 0
  for element in @seam.CstElement::Node(cst).iter() {
    match element {
      Node(_) => cst_branches += 1
      Token(_) => cst_tokens += 1
    }
  }
  {
    cst,
    diagnostics,
    token_count,
    token_reads,
    start_reads,
    end_reads,
    cst_tokens,
    cst_branches,
    retained_event_lower_bound: cst_tokens + (cst_branches - 1) * 2,
    payload: event_attribution_payload_stats(buffer),
  }
}

///|
test "event attribution: corpus matrix preserves production oracle" {
  for corpus in event_attribution_corpus_matrix(4) {
    let snapshot = event_attribution_snapshot(corpus)
    let (production_cst, production_diagnostics) = parse_cst(
      @core.SourceId("markdown-event-attribution-oracle:" + corpus.name),
      corpus.source,
    ) catch {
      _ => abort("production event-attribution oracle failed")
    }
    assert_eq(snapshot.cst, production_cst)
    assert_eq(snapshot.diagnostics, production_diagnostics)
  }
}

///|
test "event attribution: deterministic work matrix covers representative and stress scales" {
  let mut saw_backtick_control = false
  let mut saw_html_payload = false
  let mut saw_code_payload = false
  for scale in [4, 64] {
    for corpus in event_attribution_corpus_matrix(scale) {
      let snapshot = event_attribution_snapshot(corpus)
      assert_eq(snapshot.token_reads.length(), snapshot.token_count)
      assert_eq(snapshot.start_reads.length(), snapshot.token_count)
      assert_eq(snapshot.end_reads.length(), snapshot.token_count)
      assert_true(snapshot.token_reads.all(count => count > 0))
      assert_true(
        snapshot.token_reads.fold(init=0, (sum, count) => sum + count) > 0,
      )
      assert_true(
        snapshot.start_reads.fold(init=0, (sum, count) => sum + count) > 0,
      )
      assert_true(
        snapshot.end_reads.fold(init=0, (sum, count) => sum + count) > 0,
      )
      assert_true(snapshot.cst_tokens > 0)
      assert_true(snapshot.cst_branches > 0)
      assert_eq(
        snapshot.retained_event_lower_bound,
        snapshot.cst_tokens + (snapshot.cst_branches - 1) * 2,
      )
      assert_true(snapshot.payload.copies > 0)
      assert_eq(
        snapshot.payload.units,
        snapshot.payload.text_units +
        snapshot.payload.html_units +
        snapshot.payload.code_units +
        snapshot.payload.indentation_units +
        snapshot.payload.fence_info_units +
        snapshot.payload.error_units,
      )
      saw_backtick_control = saw_backtick_control ||
        snapshot.payload.backtick_tokens > 0
      saw_html_payload = saw_html_payload || snapshot.payload.html_units > 0
      saw_code_payload = saw_code_payload || snapshot.payload.code_units > 0
    }
  }
  assert_true(saw_backtick_control)
  assert_true(saw_html_payload)
  assert_true(saw_code_payload)
}
