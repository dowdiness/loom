///|
/// consumers must hand-write `fn delegate_to_inner(ctx : @core.ParserContext[NativeParityToken, NativeParityKind]) -> Unit` in this file's package.

///|
pub fn parse_root(
  ctx : @core.ParserContext[NativeParityToken, NativeParityKind],
) -> Unit {
  parse_source(ctx)
}

///|
fn parse_source(
  ctx : @core.ParserContext[NativeParityToken, NativeParityKind],
) -> Unit {
  ctx.node(NativeParityKind::Root, fn() { delegate_to_inner(ctx) })
}

///|
fn parse_inner(
  ctx : @core.ParserContext[NativeParityToken, NativeParityKind],
) -> Unit {
  if ctx.at(NativeParityToken::Int) {
    ctx.emit_token(NativeParityKind::IntToken)
  }
}

///|
/// Hand-written per the header comment above (`emit_grammar` never emits a
/// native's body). Re-entry is free in the emitted path: this calls the
/// sibling `parse_inner(ctx)` directly, no `call_rule` plumbing — contrast
/// with `native_registry()` in parity_defs.mbt, which re-enters the same
/// `inner` rule through the interpreter's `call_rule` handle instead.
fn delegate_to_inner(
  ctx : @core.ParserContext[NativeParityToken, NativeParityKind],
) -> Unit {
  parse_inner(ctx)
}
