// Residual deployment-target envelope for indented-code source ownership.
// The compatibility path is measured beside the explicit-source control so a
// return to per-block document reconstruction is visible at 2k and 10k lines.

///|
fn perf_indented_source_doc(block_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  for i = 0; i < block_count; i = i + 1 {
    out.write_string("    code_line_\{i}\n\n")
    out.write_string("separator_\{i}\n\n")
  }
  out.to_string()
}

///|
fn perf_indented_source_syntax(source : String) -> @seam.SyntaxNode {
  let (cst, diagnostics) = parse_cst(
    @core.SourceId("markdown-perf-indented-source"),
    source,
  ) catch {
    _ => abort("indented-source performance parse failed")
  }
  guard diagnostics.is_empty() else {
    abort("indented-source performance fixture must parse without diagnostics")
  }
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn bench_indented_compatibility_fold(b : @bench.T, block_count : Int) -> Unit {
  let source = perf_indented_source_doc(block_count)
  let syntax = perf_indented_source_syntax(source)
  b.bench(fn() {
    let fold = @core.CstFold::new(markdown_fold_node)
    b.keep(fold.fold(syntax))
  })
}

///|
fn bench_indented_source_aware_fold(b : @bench.T, block_count : Int) -> Unit {
  let source = perf_indented_source_doc(block_count)
  let syntax = perf_indented_source_syntax(source)
  b.bench(fn() { b.keep(fold_markdown_syntax_with_source(syntax, source)) })
}

///|
test "perf indented source: compatibility fold 2k" (b : @bench.T) {
  bench_indented_compatibility_fold(b, 500)
}

///|
test "perf indented source: compatibility fold 10k" (b : @bench.T) {
  bench_indented_compatibility_fold(b, 2500)
}

///|
test "perf indented source: source-aware fold 2k" (b : @bench.T) {
  bench_indented_source_aware_fold(b, 500)
}

///|
test "perf indented source: source-aware fold 10k" (b : @bench.T) {
  bench_indented_source_aware_fold(b, 2500)
}
