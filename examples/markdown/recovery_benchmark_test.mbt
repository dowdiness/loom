// Release characterization rows for #396/#772. This separate file keeps them
// available on both compared revisions without silently widening the existing
// PR base/head guard. Promotion can set workload-specific thresholds in a
// dedicated performance-policy change.

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
/// Parse diagnostics are intentionally excluded: these rows isolate the
/// syntax-only lowering work shared by the direct and MarkdownIR lanes.
/// Diagnostic attachment is covered separately by MarkdownIR recovery tests.
fn recovery_benchmark_parse_to_syntax(source : String) -> @seam.SyntaxNode {
  let (cst, _) = parse_cst(source) catch { _ => abort("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn recovery_benchmark_direct_block(syntax : @seam.SyntaxNode) -> Block {
  let fold = @core.CstFold::new(markdown_fold_node)
  fold.fold(syntax)
}

///|
fn recovery_benchmark_ir_block(syntax : @seam.SyntaxNode) -> Block {
  experimental_markdown_ir_to_block(
    experimental_markdown_ir_from_syntax(syntax),
  )
}

///|
test "recovery benchmark workload is output-equivalent" {
  let syntax = recovery_benchmark_parse_to_syntax(
    recovery_parity_heavy_markdown_doc(128),
  )
  let direct = recovery_benchmark_direct_block(syntax)
  inspect(recovery_benchmark_ir_block(syntax), content=@debug.to_string(direct))
}

///|
test "markdown: recovery-parity-heavy doc - lowering SyntaxNode -> Block" (
  b : @bench.T,
) {
  let syntax = recovery_benchmark_parse_to_syntax(
    recovery_parity_heavy_markdown_doc(128),
  )
  b.bench(fn() { b.keep(recovery_benchmark_direct_block(syntax)) })
}

///|
test "markdown: recovery-parity-heavy doc - lowering SyntaxNode -> MarkdownIR -> Block" (
  b : @bench.T,
) {
  let syntax = recovery_benchmark_parse_to_syntax(
    recovery_parity_heavy_markdown_doc(128),
  )
  b.bench(fn() { b.keep(recovery_benchmark_ir_block(syntax)) })
}
