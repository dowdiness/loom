///|
pub enum GraphAst {
  Parsed
} derive(Eq, Debug)

///|
fn graph_fold_node(
  _node : @seam.SyntaxNode,
  _recurse : (@seam.SyntaxNode) -> GraphAst,
) -> GraphAst {
  Parsed
}

///|
pub let graph_grammar : @loom.Grammar[Token, SyntaxKind, GraphAst] = @loom.Grammar::new(
  spec=graph_spec,
  lex~,
  fold_node=graph_fold_node,
  incremental_relex_enabled=false,
)
