///|
pub fn parse_root(ctx : @core.ParserContext[ParityToken, ParityKind]) -> Unit {
  parse_source(ctx)
}

///|
fn parse_source(ctx : @core.ParserContext[ParityToken, ParityKind]) -> Unit {
  ctx.node(ParityKind::Root, fn() {
    if ctx.at(ParityToken::Int) {
      ctx.emit_token(ParityKind::IntToken)
    }
  })
}