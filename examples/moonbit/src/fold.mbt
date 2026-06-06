///|
/// Skeleton CST fold.
///
/// It deliberately reports only coarse shape information. This makes the Loom
/// parser usable in tests while leaving the official AST projection as an
/// explicit future milestone.
fn moonbit_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MoonbitParseShell,
) -> MoonbitParseShell {
  let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    SourceFileNode => {
      let mut result = MoonbitParseShell::empty()
      for child in node.children() {
        result = result.combine(recurse(child))
      }
      if node_has_parse_errors(node) {
        { ..result, contains_errors: true }
      } else {
        result
      }
    }
    SourceItemNode =>
      {
        item_count: 1,
        token_count: count_non_trivia_tokens(node),
        contains_errors: node_has_parse_errors(node),
      }
    ErrorToken | IncompleteToken =>
      { item_count: 0, token_count: 0, contains_errors: true }
    _ => MoonbitParseShell::empty()
  }
}

///|
fn node_has_parse_errors(node : @seam.SyntaxNode) -> Bool {
  node.contains_errors(ErrorToken.to_raw(), ErrorToken.to_raw()) ||
  node.contains_errors(IncompleteToken.to_raw(), IncompleteToken.to_raw())
}

///|
fn count_non_trivia_tokens(node : @seam.SyntaxNode) -> Int {
  let mut count = 0
  for token in node.tokens() {
    let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(token.kind())
    match kind {
      TriviaToken | EofToken => ()
      _ => count = count + 1
    }
  }
  count
}
