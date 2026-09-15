// Indexed token access must match production CSTs and diagnostics.
// Accessor call counts are implementation details, not test contracts.

///|
priv struct IndexedParserCorpus {
  name : String
  source : String
}

///|
/// Covers token payloads, recovery, delimiters, and nested block ownership.
fn indexed_parser_corpora(scale : Int) -> Array[IndexedParserCorpus] {
  guard scale > 0 else { abort("indexed-parser corpus scale must be positive") }
  let delimiter = delimiter_performance_workloads(scale)
  let mixed_section = "## Section\n\nParagraph with **bold**, *italic*, `code`, and [link](/url).\n" +
    "Continuation line.\n\n- first item\n- second item\n\n" +
    "```moonbit\nfn item() -> Int { 1 }\n```\n\n"
  let recovery_case = "case: \\*literal* \\*\\*literal** \\\\*em* \\*😈* " +
    "\\* literal *unclosed\n[\\*literal*](/) \\*a \\*b***\n\n"
  let inline_html = "x <a title=\"line `\nline two\">y\n"
  let html_block = "<div data-row=\"x\">\nraw <span>payload</span>\n</div>\n\n"
  let fenced_block = "```moonbit\nfn item() -> Int {\n  1\n}\n```\n"
  [
    { name: "paragraph", source: perf_work_paragraph_doc(scale), },
    { name: "mixed", source: mixed_section.repeat(scale), },
    { name: "delimiter-heavy", source: delimiter.delimiter_heavy.source, },
    { name: "recovery-heavy", source: recovery_case.repeat(scale), },
    { name: "inline-html", source: inline_html.repeat(scale), },
    { name: "html", source: html_block.repeat(scale), },
    { name: "fenced-code", source: fenced_block.repeat(scale), },
    {
      name: "nested-container",
      source: line_end_cache_nested_quote_doc(8, scale),
    },
  ]
}

///|
/// Reuse is forbidden because it would bypass the indexed accessors under test.
fn parse_indexed_corpus(
  corpus : IndexedParserCorpus,
) -> (@seam.CstNode, @core.DiagnosticSet) {
  let source_id = @core.SourceId(
    "markdown-indexed-parser-oracle:" + corpus.name,
  )
  let buffer = perf_new_markdown_buffer(corpus.source)
  let (cst, diagnostics, reuse_count) = try! @core.parse_tokens_indexed(
    source_id,
    corpus.source,
    buffer.token_count(),
    index => buffer.get_token(index),
    index => buffer.get_start(index),
    index => buffer.get_end(index),
    markdown_spec,
  )
  guard reuse_count == 0 else {
    abort("fresh indexed parse unexpectedly reused a CST node")
  }
  (cst, diagnostics)
}

///|
test "indexed parser matches production across representative corpora" {
  for corpus in indexed_parser_corpora(4) {
    let (indexed_cst, indexed_diagnostics) = parse_indexed_corpus(corpus)
    let (production_cst, production_diagnostics) = try! parse_cst(
      @core.SourceId("markdown-indexed-parser-oracle:" + corpus.name),
      corpus.source,
    )
    assert_eq(indexed_cst, production_cst)
    assert_eq(indexed_diagnostics, production_diagnostics)
  }
}
