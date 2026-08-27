///|
/// Source-aware direct fold retained for parity fixtures and benchmarks.
///
/// High-level parsing uses the source-bound MarkdownIR projection instead.
#warnings("-unused_value")
fn markdown_fold_node_with_source(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> Block,
  source : String,
) -> Block {
  markdown_fold_node_with_code_value(node, recurse, code_node => {
    code_block_value_with_source(code_node, source)
  })
}

///|
/// Parity and benchmark oracle for the pre-cutover source-aware Block fold.
#warnings("-unused_value")
fn fold_markdown_syntax_with_source(
  syntax : @seam.SyntaxNode,
  source : String,
) -> Block {
  // This algebra reads absolute token columns from source. CstFold's
  // position-independent structural cache would reuse the wrong value for
  // equal code blocks at different source columns.
  fn lower(node : @seam.SyntaxNode) -> Block {
    markdown_fold_node_with_source(node, lower, source)
  }
  lower(syntax)
}
