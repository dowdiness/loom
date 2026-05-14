///|
/// JSON grammar: wires tokenizer, parser, and CST→AST fold together.
pub let json_grammar : @loom.Grammar[Token, SyntaxKind, JsonValue] = @loom.Grammar::new(
  spec=json_spec,
  lex~,
  fold_node=json_fold_node,
  incremental_relex_enabled=false,
  block_reparse_spec=Some(json_block_reparse_spec),
)
