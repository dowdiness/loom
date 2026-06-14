///|
let mode_state : @core.ModeRelexState[Token] = @core.erase_mode_lexer(
  markdown_mode_lexer,
  EOF,
  error_token=Error("lex error"),
  error_token_from_message=Some(fn(msg) { Error(msg) }),
)

///|
fn lex_for_grammar(source : String) -> @core.LexResult[Token] {
  (mode_state.tokenize)(source)
}

///|
pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block] = @loom.Grammar::new(
  spec=markdown_spec,
  lex=lex_for_grammar,
  fold_node=markdown_fold_node,
  block_reparse_spec=Some(markdown_block_reparse_spec),
  mode_relex=Some(mode_state),
)
