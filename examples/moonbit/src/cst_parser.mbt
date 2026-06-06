///|
const MAX_SKELETON_ERRORS : Int = 200

///|
/// Parse a coarse token-stream CST.
///
/// This is intentionally not the real MoonBit grammar yet. It establishes the
/// Loom integration points: official lexer tokens in, reusable CST nodes out.
fn parse_moonbit_root(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  while !ctx.at_eof() && ctx.error_count < MAX_SKELETON_ERRORS {
    parse_source_item(ctx)
  }
}

///|
fn parse_source_item(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  ctx.node(SourceItemNode, fn() {
    let mut consumed = 0
    while !ctx.at_eof() && ctx.error_count < MAX_SKELETON_ERRORS {
      let token = ctx.peek()
      ctx.emit_token(token.syntax_kind())
      consumed = consumed + 1
      if token.is_item_delimiter() {
        break
      }
    }
    if consumed == 0 && !ctx.at_eof() {
      ctx.error("moonbit skeleton parser made no progress")
      ctx.bump_error()
    }
  })
}
