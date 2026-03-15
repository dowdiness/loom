///|
/// Source-file grammar: handles `LetDef* Expression?` sequences.
///
/// Uses `tokenize_layout` so that newlines act as definition delimiters
/// rather than being folded into whitespace runs.
pub let source_file_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @seam.SyntaxNode,
] = @loom.Grammar::new(
  spec=source_file_spec,
  tokenize=@lexer.tokenize_layout,
  to_ast=fn(s) { s },
  on_lex_error=fn(_msg) {
    let cst = @seam.CstNode::new(@syntax.ErrorNode.to_raw(), [])
    @seam.SyntaxNode::from_cst(cst)
  },
  error_token=Some(@token.Error("")),
  prefix_lexer=Some(
    @core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer_layout),
  ),
)
