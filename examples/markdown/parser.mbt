///|
pub fn parse_cst(
  source_id : @core.SourceId,
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise {
  markdown_grammar.parse_cst(source_id, source)
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

///|
pub fn parse_markdown(
  source_id : @core.SourceId,
  source : String,
) -> (Block, @core.DiagnosticSet) raise {
  let (cst, diags) = parse_cst(source_id, source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (fold_markdown_syntax_with_source(syntax, source), diags)
}

///|
pub fn parse(
  source_id : @core.SourceId,
  source : String,
) -> Block raise Failure {
  // Tolerant parse — lex errors become Block::Error; parser recovery folds the
  // current CST, preserving recoverable inline text where possible.
  let (cst, _diags) = parse_cst(source_id, source) catch {
    Failure::Failure(_) as failure => raise failure
    _ => return Block::Error("lex error")
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  fold_markdown_syntax_with_source(syntax, source)
}
