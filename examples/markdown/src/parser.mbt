///|
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  markdown_grammar.parse_cst(source)
}

///|
pub fn parse_markdown(
  source : String,
) -> (Block, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  let (cst, diags) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let fold = @core.CstFold::new(markdown_fold_node)
  (fold.fold(syntax), diags)
}

///|
pub fn parse(source : String) -> Block {
  // Tolerant parse — returns Document with Error nodes on failure
  let (cst, _diags) = parse_cst(source) catch {
    _ => return Block::Error("lex error")
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let fold = @core.CstFold::new(markdown_fold_node)
  fold.fold(syntax)
}
