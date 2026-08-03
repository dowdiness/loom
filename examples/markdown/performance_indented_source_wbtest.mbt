///|
test "perf indented source: corpus dimensions and lowering parity" {
  let source_2k = perf_indented_source_doc(500)
  let source_10k = perf_indented_source_doc(2500)
  let mut lines_2k = 1
  for ch in source_2k {
    if ch == '\n' {
      lines_2k = lines_2k + 1
    }
  }
  let mut lines_10k = 1
  for ch in source_10k {
    if ch == '\n' {
      lines_10k = lines_10k + 1
    }
  }
  assert_eq(lines_2k, 2001)
  assert_eq(lines_10k, 10001)
  let syntax = perf_indented_source_syntax(source_2k)
  let code_blocks : Array[@seam.SyntaxNode] = []
  collect_code_block_nodes(syntax, code_blocks)
  assert_eq(code_blocks.length(), 500)
  let compatibility = @core.CstFold::new(markdown_fold_node).fold(syntax)
  assert_eq(compatibility, fold_markdown_syntax_with_source(syntax, source_2k))
  let mut source_reconstructions = 0
  for code_block in code_blocks {
    ignore(
      code_block_source_with_fallback(code_block, fn() {
        source_reconstructions = source_reconstructions + 1
        syntax.text()
      }),
    )
  }
  assert_eq(source_reconstructions, 0)
}
