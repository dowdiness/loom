///|
let mode_factory : @core.ModeRelexFactory[Token] = @core.erase_mode_lexer_factory(
  new_markdown_mode_lexer,
  EOF,
  error_token=Error("lex error"),
  error_token_from_message=Some(msg => Error(msg)),
)

///|
fn lex_for_grammar(
  source_id : @core.SourceId,
  source : String,
) -> @core.LexResult[Token] {
  mode_factory.tokenize(source_id, source)
}

///|
pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block] = @loom.Grammar::new(
  spec=markdown_spec,
  lex=lex_for_grammar,
  fold_node=markdown_fold_node,
  block_reparse_spec=Some(markdown_block_reparse_spec),
  mode_relex=Some(mode_factory),
)
