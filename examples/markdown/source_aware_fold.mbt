///|
/// Source-aware Block algebra used when the top-level caller already owns the
/// current document string. This keeps indented-code column handling explicit
/// and avoids rebuilding the syntax root for each code block.
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
