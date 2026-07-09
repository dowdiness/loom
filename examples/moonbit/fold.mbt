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
      let result = for
        child in node.children()
        result = MoonbitParseShell::empty() {
        continue result.combine(recurse(child))
      } nobreak {
        result
      }
      if node_has_parse_errors(node) {
        { ..result, contains_errors: true }
      } else {
        result
      }
    }
    SourceItemNode
    | LetItemNode
    | FunctionItemNode
    | StructItemNode
    | EnumItemNode
    | TypeItemNode =>
      {
        item_count: 1,
        token_count: count_non_trivia_tokens(node),
        contains_errors: node_has_parse_errors(node),
      }
    IfExprNode | BlockExprNode =>
      {
        item_count: 0,
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
  let direct_count = for token in node.tokens(); count = 0 {
    let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(token.kind())
    continue match kind {
        TriviaToken | EofToken => count
        _ => count + 1
      }
  } nobreak {
    count
  }
  for child in node.children(); count = direct_count {
    continue count + count_non_trivia_tokens(child)
  } nobreak {
    count
  }
}
