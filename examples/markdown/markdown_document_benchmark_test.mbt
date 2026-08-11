///|
fn markdown_document_benchmark_source(count : Int) -> String {
  let out = StringBuilder::new()
  out.write_string("# Benchmark\n\n")
  for i = 0; i < count; i = i + 1 {
    out.write_string(
      "Paragraph \\{i + 1} with *semantic* content and a [link](https://example.test/\\{i + 1}).\n\n",
    )
  }
  out.to_string()
}

///|
fn markdown_document_benchmark_selection(
  read : MarkdownSemanticRead,
) -> MarkdownSemanticSelection {
  match read.root().children() {
    [_heading, paragraph, ..] =>
      match paragraph.children() {
        [link] =>
          match
            link.selection(kind=MarkdownSemanticSelectionKind::Destination) {
            Some(selection) => selection
            None => abort("expected a benchmark destination selection")
          }
        _ => abort("expected one benchmark paragraph link")
      }
    _ => abort("expected benchmark heading and paragraph")
  }
}

///|
test "perf source-bound parse_document 100 paragraphs" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  b.bench(fn() {
    b.keep(
      try! parse_document(
        @core.SourceId("markdown-document-benchmark-source"),
        source,
      ),
    )
  })
}

///|
test "perf source-bound semantic_read 100 paragraphs" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  let document = try! parse_document(
    @core.SourceId("markdown-document-benchmark-read"),
    source,
  )
  b.bench(fn() { b.keep(document.semantic_read()) })
}

///|
test "perf source-bound Block adapter 100 paragraphs" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  let read = try! parse_document(
    @core.SourceId("markdown-document-benchmark-block"),
    source,
  ).semantic_read()
  b.bench(fn() { b.keep(markdown_semantic_read_to_block(read)) })
}

///|
test "perf source-bound mdast adapter 100 paragraphs" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  let read = try! parse_document(
    @core.SourceId("markdown-document-benchmark-mdast"),
    source,
  ).semantic_read()
  b.bench(fn() {
    b.keep(markdown_semantic_read_to_mdast_json_with_positions(read))
  })
}

///|
test "perf source-bound preserve rewrite 100 paragraphs" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  let read = try! parse_document(
    @core.SourceId("markdown-document-benchmark-preserve"),
    source,
  ).semantic_read()
  b.bench(fn() { b.keep(markdown_semantic_read_preserve_rewrite(read)) })
}

///|
test "perf source-bound local rewrite selection" (b : @bench.T) {
  let source = "# Benchmark\n\n[link](https://example.test)\n"
  let read = try! parse_document(
    @core.SourceId("markdown-document-benchmark-local"),
    source,
  ).semantic_read()
  let selection = markdown_document_benchmark_selection(read)
  b.bench(fn() {
    b.keep(
      markdown_semantic_read_local_transform_rewrite(
        selection,
        replacement_text="https://changed.test",
      ),
    )
  })
}

///|
test "perf source-bound IR-only target through read" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  let read = try! parse_document(
    @core.SourceId("markdown-document-benchmark-ir-only"),
    source,
  ).semantic_read()
  b.bench(fn() {
    b.keep(experimental_markdown_ir_to_commonmark_html(read.ir()))
  })
}

///|
test "perf source-bound attachment source_document" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  let parser = try! @loom.new_parser(
    @core.SourceId("markdown-document-benchmark-attachment"),
    source,
    markdown_grammar,
  )
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  b.bench(fn() { b.keep(attachment.source_document()) })
  attachment.dispose()
}
