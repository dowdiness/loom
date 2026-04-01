///|
let mode_state : @core.ModeRelexState[Token] = @core.erase_mode_lexer(
  markdown_mode_lexer,
  EOF,
)

///|
fn tokenize_for_grammar(
  source : String,
) -> Array[@core.TokenInfo[Token]] raise @core.LexError {
  let (tokens, _) = (mode_state.tokenize)(source)
  tokens
}

///|
pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block] = @loom.Grammar::new(
  spec=markdown_spec,
  tokenize=tokenize_for_grammar,
  fold_node=markdown_fold_node,
  on_lex_error=fn(msg) { Block::Error("lex error: " + msg) },
  error_token=Some(Error("")),
  mode_relex=Some(mode_state),
)
