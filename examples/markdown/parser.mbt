///|
pub fn parse_cst(
  source_id : @core.SourceId,
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise {
  markdown_grammar.parse_cst(source_id, source)
}

///|
pub fn parse_markdown(
  source_id : @core.SourceId,
  source : String,
) -> (Block, @core.DiagnosticSet) raise {
  let document = parse_document(source_id, source)
  let diagnostics = document.diagnostics()
  let block = markdown_semantic_read_to_block(document.semantic_read())
  (block, diagnostics)
}

///|
pub fn parse(
  source_id : @core.SourceId,
  source : String,
) -> Block raise Failure {
  // Tolerant parse — lex errors become Block::Error; semantic recovery folds
  // the source-bound MarkdownIR while preserving recoverable inline text.
  let (block, _) = parse_markdown(source_id, source) catch {
    Failure::Failure(_) as failure => raise failure
    _ => return Block::Error("lex error")
  }
  block
}
