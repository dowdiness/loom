///|
// Public API facade for dowdiness/lambda.
// A single import gives access to all lambda parser types through one alias.

///|
// AST types — the result of parsing lambda calculus expressions
pub using @ast {type AstNode, type AstKind, type Term, type Bop, type VarName}

///|
// Edit primitive — apply incremental updates to the parser
pub using @core {type Edit}

///|
// Incremental engine — the primary type for incremental parsing
pub using @incremental {type IncrementalParser}

///|
/// Create a lambda calculus IncrementalParser, pre-configured with the lambda
/// grammar. The grammar is baked in — pass only the initial source string.
pub fn new_incremental_parser(
  source : String,
) -> @incremental.IncrementalParser[@ast.AstNode] {
  @loom.new_incremental_parser(source, lambda_grammar)
}
