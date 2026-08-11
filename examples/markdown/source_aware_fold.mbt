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
  let fold = @core.CstFold::new(fn(node, recurse) {
    markdown_fold_node_with_source(node, recurse, source)
  })
  fold.fold(syntax)
}
