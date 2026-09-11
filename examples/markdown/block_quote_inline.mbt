// Shared inline-node shell for ordinary and repeated nested blockquotes.
// Callers provide continuation and Setext-prefix policies; this file owns the
// paragraph/heading node lifecycle and checkpoint semantics.

///|
fn[T : InlineContinuationAction] parse_block_quote_paragraph_with_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  decide : () -> ContinuationDecision[T],
) -> Unit {
  ctx.node(ParagraphNode, fn() {
    parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), decide)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
fn[T : InlineContinuationAction] try_parse_block_quote_setext_heading_with_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  decide : () -> ContinuationDecision[T],
  underline_depth : () -> Int?,
  consume_underline : () -> Unit,
) -> Bool {
  let checkpoint = ctx.checkpoint()
  ctx.start_node(HeadingNode)
  parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), decide)
  if underline_depth() is Some(_) {
    consume_underline()
    ctx.finish_node()
    true
  } else {
    ctx.finish_node()
    ctx.restore(checkpoint)
    false
  }
}
