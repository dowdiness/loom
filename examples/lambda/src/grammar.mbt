///|
/// Lambda grammar: handles `LetDef* Expression?` sequences.
///
/// Uses `tokenize` so that newlines act as definition delimiters
/// rather than being folded into whitespace runs.
pub let lambda_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.Term,
] = @loom.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  fold_node=lambda_fold_node,
  on_lex_error=fn(msg) { @ast.Term::Error("lex error: " + msg) },
  error_token=Some(@token.Error("")),
  prefix_lexer=Some(@core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer)),
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
  tokenize=@lexer.tokenize,
  fold_node=lambda_fold_node,
  on_lex_error=fn(msg) { @ast.Term::Error("lex error: " + msg) },
  error_token=Some(@token.Error("")),
  prefix_lexer=Some(@core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer)),
  block_reparse_spec=Some(lambda_block_reparse_spec),
)
