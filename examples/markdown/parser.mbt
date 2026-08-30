///|
pub fn parse_cst(
  source_id : @core.SourceId,
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise {
  markdown_grammar.parse_cst(source_id, source)
}

///|
pub fn parse_block_ast(
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
