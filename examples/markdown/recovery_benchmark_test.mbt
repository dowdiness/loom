// Ungated characterization rows for #483/#772. This separate file keeps them
// out of the PR base/head guard, which selects benchmark_test.mbt explicitly.
// Promote them only after the workload exists on both compared revisions and
// #396 fixes the target delimiter semantics.

///|
fn recovery_parity_heavy_markdown_doc(repeats : Int) -> String {
  let slash = "\\"
  let escaped_literal = slash + "*literal*"
  let two_escaped_openers = slash + "*" + slash + "*literal**"
  let even_backslashes = slash + slash + "*em*"
  let non_bmp_literal = slash + "*😈*"
  let flanking_recovery = slash + "* literal *unclosed"
  let link_literal = "[" + slash + "*literal*](/)"
  let consume_then_reset = slash + "*a " + slash + "*b***"
  let buf = StringBuilder::new()
  for i = 0; i < repeats; i = i + 1 {
    buf.write_string(
      "case " +
      i.to_string() +
      ": " +
      escaped_literal +
      " " +
      two_escaped_openers +
      " " +
      even_backslashes +
      " " +
      non_bmp_literal +
      " " +
      flanking_recovery +
      "\n",
    )
    buf.write_string(link_literal + " " + consume_then_reset + "\n\n")
  }
  buf.to_string()
}

///|
fn recovery_benchmark_parse_to_syntax(source : String) -> @seam.SyntaxNode {
  let (cst, _) = parse_cst(source) catch { _ => abort("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

///|
test "markdown: recovery-parity-heavy doc - lowering SyntaxNode -> Block" (
  b : @bench.T,
) {
  let syntax = recovery_benchmark_parse_to_syntax(
    recovery_parity_heavy_markdown_doc(128),
  )
  b.bench(fn() {
    let fold = @core.CstFold::new(markdown_fold_node)
    let block = fold.fold(syntax)
    b.keep(block)
  })
}

///|
test "markdown: recovery-parity-heavy doc - lowering SyntaxNode -> MarkdownIR -> Block" (
  b : @bench.T,
) {
  let syntax = recovery_benchmark_parse_to_syntax(
    recovery_parity_heavy_markdown_doc(128),
  )
  b.bench(fn() {
    let ir = experimental_markdown_ir_from_syntax(syntax)
    let block = experimental_markdown_ir_to_block(ir)
    b.keep(block)
  })
}
