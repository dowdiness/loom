///|
// Public API facade for dowdiness/lambda.

///|
// AST types — Term and Bop remain for evaluation; AstNode is removed.
pub using @ast {type Term, type Bop, type VarName}

///|
// Typed view types — primary tree navigation API.
// Import `dowdiness/lambda` and use these to navigate parse results.
pub using @seam {type SyntaxNode, type SyntaxToken, type SyntaxElement}

///|
// Edit primitive — apply incremental updates to the parser
pub using @core {type Edit}

///|
// Incremental engine — the primary type for incremental parsing
pub using @incremental {type ImperativeParser}

///|
/// Create a lambda calculus ImperativeParser, pre-configured with the lambda
/// grammar. The grammar is baked in — pass only the initial source string.
/// The parser returns SyntaxNode; use typed view types to navigate the tree.
pub fn new_imperative_parser(
  source : String,
) -> @incremental.ImperativeParser[@seam.SyntaxNode] {
  @loom.new_imperative_parser(source, lambda_grammar)
}
