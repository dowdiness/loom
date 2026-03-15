///|
/// Lambda grammar: handles `LetDef* Expression?` sequences.
///
/// Uses `tokenize` so that newlines act as definition delimiters
/// rather than being folded into whitespace runs.
pub let lambda_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @seam.SyntaxNode,
] = @loom.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  to_ast=fn(s) { s },
  on_lex_error=fn(_msg) {
    let cst = @seam.CstNode::new(@syntax.ErrorNode.to_raw(), [])
    @seam.SyntaxNode::from_cst(cst)
  },
  error_token=Some(@token.Error("")),
  prefix_lexer=Some(@core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer)),
)
