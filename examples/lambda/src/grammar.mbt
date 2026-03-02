///|
/// Lambda calculus grammar description.
///
/// This is the complete integration surface — a single value that
/// bridge factories consume to produce ImperativeParser or ReactiveParser.
pub let lambda_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.AstNode,
] = @loom.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  to_ast=fn(s) { syntax_node_to_ast_node(s, Ref::new(0)) },
  on_lex_error=fn(msg) { @ast.AstNode::error(msg, 0, 0) },
)
