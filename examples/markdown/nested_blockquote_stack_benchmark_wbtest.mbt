// Release benchmark for #875. Compare depth independently from physical line
// count on both wasm-gc and JavaScript.

///|
fn bench_nested_blockquote_stack_cst(
  b : @bench.T,
  source_id : String,
  source : String,
) -> Unit {
  b.bench(() => {
    let (cst, diagnostics) = parse_cst(@core.SourceId(source_id), source) catch {
      _ => abort("nested blockquote stack benchmark failed to lex")
    }
    b.keep(cst)
    b.keep(diagnostics)
  })
}

///|
test "nested blockquote stack: depth 8 with 64 lines" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-64",
    line_end_cache_nested_quote_doc(8, 64),
  )
}

///|
test "nested blockquote stack: depth 1 with 64 lines" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-depth-1-lines-64",
    line_end_cache_nested_quote_doc(1, 64),
  )
}

///|
test "nested blockquote stack: depth 32 with 64 lines" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-depth-32-lines-64",
    line_end_cache_nested_quote_doc(32, 64),
  )
}

///|
test "nested blockquote stack: depth 128 with 64 lines" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-depth-128-lines-64",
    line_end_cache_nested_quote_doc(128, 64),
  )
}

///|
test "nested blockquote stack: depth 8 with 128 lines" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-128",
    line_end_cache_nested_quote_doc(8, 128),
  )
}

///|
test "nested blockquote stack: depth 8 with 256 lines" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-256",
    line_end_cache_nested_quote_doc(8, 256),
  )
}

///|
test "nested blockquote stack control: paragraph" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-paragraph-control",
    perf_work_paragraph_doc(100),
  )
}

///|
test "nested blockquote stack control: mixed" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-mixed-control",
    ("## Section\n\nParagraph with **bold**, *italic*, `code`, and [link](/url).\n" +
    "Continuation line.\n\n- first item\n- second item\n\n" +
    "```moonbit\nfn item() -> Int { 1 }\n```\n\n").repeat(64),
  )
}

///|
test "nested blockquote stack control: HTML" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-html-control",
    "<div>\nraw <span>payload</span>\n</div>\n\n".repeat(200),
  )
}

///|
test "nested blockquote stack control: fenced code" (b : @bench.T) {
  bench_nested_blockquote_stack_cst(
    b,
    "markdown-nested-blockquote-stack-fenced-control",
    "```moonbit\nfn item() -> Int { 1 }\n```\n\n".repeat(200),
  )
}
