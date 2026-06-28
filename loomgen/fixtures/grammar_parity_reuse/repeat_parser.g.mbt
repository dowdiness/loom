///|
pub fn parse_root(ctx : @core.ParserContext[ReuseToken, ReuseKind]) -> Unit {
  parse_source(ctx)
}

///|
fn parse_source(ctx : @core.ParserContext[ReuseToken, ReuseKind]) -> Unit {
  ctx.node(ReuseKind::Root, fn() {
    ctx.consume_while_emit(fn(t) { t == ReuseToken::Skip }, ReuseKind::SkipKind)
    while !ctx.at_eof() && ctx.peek() == ReuseToken::Int {
      if ctx.try_reuse_repeat_group() {
        ctx.consume_while_emit(
          fn(t) { t == ReuseToken::Skip },
          ReuseKind::SkipKind,
        )
        continue
      }
      parse_item(ctx)
      let had = ctx.peek() == ReuseToken::Skip
      ctx.consume_while_emit(
        fn(t) { t == ReuseToken::Skip },
        ReuseKind::SkipKind,
      )
      if !had && !ctx.at_eof() {
        if ctx.peek() == ReuseToken::Int {
          ctx.error("between")
        } else {
          ctx.error("after")
        }
      }
    }
  })
}

///|
fn parse_item(ctx : @core.ParserContext[ReuseToken, ReuseKind]) -> Unit {
  ctx.node(ReuseKind::IntItem, fn() {
    if ctx.at(ReuseToken::Int) {
      ctx.emit_token(ReuseKind::IntToken)
    }
  })
}
