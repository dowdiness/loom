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
test "perf source-bound benchmark control" (b : @bench.T) {
  let source = markdown_document_benchmark_source(100)
  let expected_length = source.length()
  b.bench(fn() { b.keep(expected_length) })
}

///|
test "perf source-bound parse_document 100 paragraphs" (b : @bench.T) {
  let run = markdown_document_benchmark_parse_runner(
    markdown_document_benchmark_source(100),
  )
  b.bench(fn() { b.keep(run()) })
}

///|
test "perf source-bound semantic_read 100 paragraphs" (b : @bench.T) {
  let run = markdown_document_benchmark_semantic_read_runner(
    markdown_document_benchmark_source(100),
  )
  b.bench(fn() { b.keep(run()) })
}

///|
test "perf source-bound Block adapter 100 paragraphs" (b : @bench.T) {
  let run = markdown_document_benchmark_block_runner(
    markdown_document_benchmark_source(100),
  )
  b.bench(fn() { b.keep(run()) })
}

///|
test "perf source-bound mdast adapter 100 paragraphs" (b : @bench.T) {
  let run = markdown_document_benchmark_mdast_runner(
    markdown_document_benchmark_source(100),
  )
  b.bench(fn() { b.keep(run()) })
}

///|
test "perf source-bound preserve rewrite 100 paragraphs" (b : @bench.T) {
  let run = markdown_document_benchmark_preserve_runner(
    markdown_document_benchmark_source(100),
  )
  b.bench(fn() { b.keep(run()) })
}

///|
test "perf source-bound local rewrite selection" (b : @bench.T) {
  let run = markdown_document_benchmark_local_rewrite_runner(
    "# Benchmark\n\n[link](https://example.test)\n",
  )
  b.bench(fn() { b.keep(run()) })
}

///|
test "perf source-bound IR-only target through read" (b : @bench.T) {
  let run = markdown_document_benchmark_ir_only_runner(
    markdown_document_benchmark_source(100),
  )
  b.bench(fn() { b.keep(run()) })
}

///|
test "perf source-bound attachment source_document" (b : @bench.T) {
  let run = markdown_document_benchmark_attachment_runner(
    markdown_document_benchmark_source(100),
  )
  b.bench(fn() { b.keep(run()) })
}
