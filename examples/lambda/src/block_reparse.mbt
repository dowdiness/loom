///|
/// Lambda grammar's block reparse specification.
/// Only BlockExpr is reparseable.
pub let lambda_block_reparse_spec : @loom.BlockReparseSpec[
  @token.Token,
  @syntax.SyntaxKind,
] = {
  is_reparseable: fn(kind) { kind == @syntax.BlockExpr.to_raw() },
  get_reparser: fn(kind) {
    if kind == @syntax.BlockExpr.to_raw() {
      Some(parse_block_expr)
    } else {
      None
    }
  },
  is_balanced: fn(tokens) {
    let mut depth = 0
    for token in tokens {
      if token.token == @token.LBrace {
        depth = depth + 1
      }
      if token.token == @token.RBrace {
        depth = depth - 1
      }
      if depth < 0 {
        return false
      }
    }
    depth == 0
  },
}
