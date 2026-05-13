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
  on_lex_error=fn(msg) { @ast.Term::Error("lex error: " + msg) },
  incremental_relex_enabled=false,
  block_reparse_spec=Some(lambda_block_reparse_spec),
)

///|
/// Lambda grammar with reuse_size_threshold=0 (skip disabled).
/// Used in tests to compare reuse behavior with/without threshold.
pub let lambda_grammar_no_threshold : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.Term,
] = @loom.Grammar::new(
  spec=lambda_spec_no_threshold,
  lex=@lexer.lex,
  fold_node=lambda_fold_node,
  on_lex_error=fn(msg) { @ast.Term::Error("lex error: " + msg) },
  incremental_relex_enabled=false,
  block_reparse_spec=Some(lambda_block_reparse_spec),
)
