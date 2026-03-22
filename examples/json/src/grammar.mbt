///|
/// JSON grammar: wires tokenizer, parser, and CST→AST fold together.
pub let json_grammar : @loom.Grammar[Token, SyntaxKind, JsonValue] = @loom.Grammar::new(
  spec=json_spec,
  tokenize~,
  fold_node=json_fold_node,
  on_lex_error=fn(msg) { JsonValue::Error("lex error: " + msg) },
  error_token=Some(Error("")),
  prefix_lexer=Some(@core.PrefixLexer::new(lex_step=json_step_lexer)),
  block_reparse_spec=Some(json_block_reparse_spec),
)
