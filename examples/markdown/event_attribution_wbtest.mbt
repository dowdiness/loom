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
  {
    cst,
    diagnostics,
    token_count,
    token_reads,
    start_reads,
    end_reads,
    payload: event_attribution_payload_stats(buffer),
  }
}

///|
fn event_attribution_transcript(scale : Int) -> String {
  let out = StringBuilder::new()
  for corpus in event_attribution_corpus_matrix(scale) {
    let snapshot = event_attribution_snapshot(corpus)
    let token_read_total = snapshot.token_reads.fold(init=0, (sum, count) => {
      sum + count
    })
    let start_read_total = snapshot.start_reads.fold(init=0, (sum, count) => {
      sum + count
    })
    let end_read_total = snapshot.end_reads.fold(init=0, (sum, count) => {
      sum + count
    })
    let token_read_max = snapshot.token_reads.fold(init=0, (largest, count) => {
      largest.max(count)
    })
    out.write_string(corpus.name)
    out.write_string("|source=")
    out.write_object(corpus.source.length())
    out.write_string("|tokens=")
    out.write_object(snapshot.token_count)
    out.write_string("|reads=")
    out.write_object(token_read_total)
    out.write_string("/")
    out.write_object(start_read_total)
    out.write_string("/")
    out.write_object(end_read_total)
    out.write_string("|token-max=")
    out.write_object(token_read_max)
    out.write_string("|diagnostics=")
    out.write_object(snapshot.diagnostics.length())
    out.write_string("|payload=")
    out.write_object(snapshot.payload.copies)
    out.write_string("/")
    out.write_object(snapshot.payload.units)
    out.write_string("|payload-units=")
    out.write_object(snapshot.payload.text_units)
    out.write_string("/")
    out.write_object(snapshot.payload.html_units)
    out.write_string("/")
    out.write_object(snapshot.payload.code_units)
    out.write_string("/")
    out.write_object(snapshot.payload.indentation_units)
    out.write_string("/")
    out.write_object(snapshot.payload.fence_info_units)
    out.write_string("/")
    out.write_object(snapshot.payload.error_units)
    out.write_string("|backticks=")
    out.write_object(snapshot.payload.backtick_tokens)
    out.write_string("\n")
  }
  out.to_string()
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
test "event attribution: deterministic transcript remains stable" {
  inspect(
    event_attribution_transcript(4),
    content=(
      #|paragraph|source=422|tokens=57|reads=1733/513/508|token-max=41|diagnostics=0|payload=21/386|payload-units=386/0/0/0/0/0|backticks=0
      #|mixed|source=640|tokens=173|reads=5126/1400/1376|token-max=76|diagnostics=0|payload=64/492|payload-units=376/0/88/0/28/0|backticks=8
      #|delimiter-heavy|source=520|tokens=293|reads=9584/3215/3214|token-max=41|diagnostics=0|payload=111/339|payload-units=339/0/0/0/0/0|backticks=8
      #|recovery-heavy|source=372|tokens=113|reads=3862/1208/1204|token-max=52|diagnostics=0|payload=40/300|payload-units=300/0/0/0/0/0|backticks=0
      #|html|source=208|tokens=29|reads=182/36/32|token-max=11|diagnostics=0|payload=12/192|payload-units=0/192/0/0/0/0|backticks=0
      #|fenced-code|source=160|tokens=37|reads=222/40/36|token-max=10|diagnostics=0|payload=16/116|payload-units=0/0/88/0/28/0|backticks=0
      #|nested-container|source=104|tokens=41|reads=933/287/285|token-max=35|diagnostics=0|payload=4/36|payload-units=36/0/0/0/0/0|backticks=0
      #|
    ),
  )
  inspect(
    event_attribution_transcript(64),
    content=(
      #|paragraph|source=6537|tokens=837|reads=27113/8073/8008|token-max=41|diagnostics=0|payload=321/6021|payload-units=6021/0/0/0/0/0|backticks=0
      #|mixed|source=10240|tokens=2753|reads=81986/22400/22016|token-max=76|diagnostics=0|payload=1024/7872|payload-units=6016/0/1408/0/448/0|backticks=128
      #|delimiter-heavy|source=8320|tokens=4673|reads=152864/51455/51454|token-max=41|diagnostics=0|payload=1791/5439|payload-units=5439/0/0/0/0/0|backticks=128
      #|recovery-heavy|source=5952|tokens=1793|reads=61762/19328/19264|token-max=52|diagnostics=0|payload=640/4800|payload-units=4800/0/0/0/0/0|backticks=0
      #|html|source=3328|tokens=449|reads=2882/576/512|token-max=11|diagnostics=0|payload=192/3072|payload-units=0/3072/0/0/0/0|backticks=0
      #|fenced-code|source=2560|tokens=577|reads=3522/640/576|token-max=10|diagnostics=0|payload=256/1856|payload-units=0/0/1408/0/448/0|backticks=0
      #|nested-container|source=1718|tokens=641|reads=14793/4727/4725|token-max=35|diagnostics=0|payload=64/630|payload-units=630/0/0/0/0/0|backticks=0
      #|
    ),
  )
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
