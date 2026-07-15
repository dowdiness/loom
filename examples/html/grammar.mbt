///|
/// HTML grammar: wires tokenizer, parser, and CST construction together.
pub let html_grammar : @loom.Grammar[@token.Token, @syntax.SyntaxKind, Unit] = @loom.Grammar::new(
  spec=html_spec,
  lex~,
  fold_node=(_node, _recurse) => (),
  incremental_relex_enabled=false,
  mode_relex=Some(html_mode_relex_factory),
)
