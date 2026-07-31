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
/// grammar. The grammar is baked in — pass the source identity and initial
/// source string.
/// The parser returns Term directly via memoized CST fold.
pub fn new_imperative_parser(
  source_id : @core.SourceId,
  source : String,
) -> @incremental.ImperativeParser[@ast.Term] {
  @loom.new_imperative_parser(source_id, source, lambda_grammar)
}
