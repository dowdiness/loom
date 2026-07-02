///|
/// Lambda grammar: handles `LetDef* Expression?` sequences.
///
/// Uses `lex=@lexer.lex` so that newlines act as definition delimiters
/// rather than being folded into whitespace runs.
pub let lambda_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.Term,
] = @loom.Grammar::new(
  spec=lambda_spec,
  lex=@lexer.lex,
  fold_node=lambda_fold_node,
  incremental_relex_enabled=false,
  block_reparse_spec=Some(lambda_block_reparse_spec),
)

///|
/// Lambda grammar with reuse_size_threshold=0 (skip disabled).
/// Used in tests to compare reuse behavior with/without threshold.
/// Note: `lambda_spec` itself already uses reuse_size_threshold=0, so this
/// is currently identical to `lambda_grammar`; the separate name is kept for
/// the tests that state threshold intent explicitly.
pub let lambda_grammar_no_threshold : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.Term,
] = @loom.Grammar::new(
  spec=lambda_spec,
  lex=@lexer.lex,
  fold_node=lambda_fold_node,
  incremental_relex_enabled=false,
  block_reparse_spec=Some(lambda_block_reparse_spec),
)
