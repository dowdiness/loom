///|
/// Lambda calculus grammar description.
///
/// This is the complete integration surface — a single value that
/// bridge factories consume to produce ImperativeParser or ReactiveParser.
pub let lambda_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @seam.SyntaxNode,
] = @loom.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  // Identity: the SyntaxNode IS the Ast. Callers use typed views to navigate.
  to_ast=fn(s) { s },
  // On lex error: create a minimal error SyntaxNode.
  on_lex_error=fn(_msg) {
    let cst = @seam.CstNode::new(@syntax.ErrorNode.to_raw(), [])
    @seam.SyntaxNode::from_cst(cst)
  },
)

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
)
