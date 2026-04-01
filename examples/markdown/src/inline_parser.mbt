///|
/// Parse inline content until block boundary, newline, or EOF.
fn parse_inline_content(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  while !is_block_boundary(ctx.peek()) &&
        !(ctx.peek() is Newline) &&
        ctx.peek() != EOF {
    parse_inline(ctx)
  }
}

///|
/// Parse a single inline element.
fn parse_inline(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  match ctx.peek() {
    StarStar => parse_bold(ctx)
    Star => parse_italic(ctx)
    Backtick => parse_inline_code(ctx)
    LeftBracket => parse_link(ctx)
    Text(_) => ctx.emit_token(TextToken)
    _ =>
      // Unexpected inline token — emit as error
      ctx.bump_error()
  }
}

///|
/// Parse bold: **content**
fn parse_bold(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(BoldNode)
  ctx.emit_token(StarStarToken) // opening **
  // Parse inline content until closing ** or block boundary
  while !(ctx.peek() is StarStar) &&
        !is_block_boundary(ctx.peek()) &&
        !(ctx.peek() is Newline) &&
        ctx.peek() != EOF {
    parse_inline(ctx)
  }
  if ctx.peek() is StarStar {
    ctx.emit_token(StarStarToken) // closing **
    ctx.finish_node()
  } else {
    // Unclosed bold — restore and treat ** as text
    ctx.finish_node()
    ctx.restore(cp)
    // Emit the ** as text by wrapping in error node
    ctx.start_node(ErrorNode)
    ctx.emit_token(StarStarToken)
    ctx.finish_node()
  }
}

///|
/// Parse italic: *content*
fn parse_italic(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(ItalicNode)
  ctx.emit_token(StarToken) // opening *
  // Parse inline content until closing * or block boundary
  while !(ctx.peek() is Star) &&
        !(ctx.peek() is StarStar) &&
        !is_block_boundary(ctx.peek()) &&
        !(ctx.peek() is Newline) &&
        ctx.peek() != EOF {
    parse_inline(ctx)
  }
  if ctx.peek() is Star {
    ctx.emit_token(StarToken) // closing *
    ctx.finish_node()
  } else {
    // Unclosed italic — restore and treat * as text
    ctx.finish_node()
    ctx.restore(cp)
    ctx.start_node(ErrorNode)
    ctx.emit_token(StarToken)
    ctx.finish_node()
  }
}

///|
/// Parse inline code: `content`
fn parse_inline_code(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(InlineCodeNode)
  ctx.emit_token(BacktickToken) // opening `
  // Consume text tokens until closing ` or block boundary
  while !(ctx.peek() is Backtick) &&
        !is_block_boundary(ctx.peek()) &&
        !(ctx.peek() is Newline) &&
        ctx.peek() != EOF {
    // Inside inline code, everything is text
    match ctx.peek() {
      Text(_) => ctx.emit_token(TextToken)
      Star => ctx.emit_token(StarToken)
      StarStar => ctx.emit_token(StarStarToken)
      LeftBracket => ctx.emit_token(LeftBracketToken)
      RightBracket => ctx.emit_token(RightBracketToken)
      LeftParen => ctx.emit_token(LeftParenToken)
      RightParen => ctx.emit_token(RightParenToken)
      _ => ctx.bump_error()
    }
  }
  if ctx.peek() is Backtick {
    ctx.emit_token(BacktickToken) // closing `
    ctx.finish_node()
  } else {
    // Unclosed inline code — restore and treat ` as text
    ctx.finish_node()
    ctx.restore(cp)
    ctx.start_node(ErrorNode)
    ctx.emit_token(BacktickToken)
    ctx.finish_node()
  }
}

///|
/// Parse link: [text](url)
fn parse_link(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(LinkNode)
  ctx.emit_token(LeftBracketToken) // [
  // Parse link text content until ]
  while !(ctx.peek() is RightBracket) &&
        !is_block_boundary(ctx.peek()) &&
        !(ctx.peek() is Newline) &&
        ctx.peek() != EOF {
    parse_inline(ctx)
  }
  if !(ctx.peek() is RightBracket) {
    // Unclosed bracket — restore and treat [ as text
    ctx.finish_node()
    ctx.restore(cp)
    ctx.start_node(ErrorNode)
    ctx.emit_token(LeftBracketToken)
    ctx.finish_node()
    return
  }
  ctx.emit_token(RightBracketToken) // ]
  // Expect (url)
  if !(ctx.peek() is LeftParen) {
    // No parenthesized URL — restore and treat [ as text
    ctx.finish_node()
    ctx.restore(cp)
    ctx.start_node(ErrorNode)
    ctx.emit_token(LeftBracketToken)
    ctx.finish_node()
    return
  }
  ctx.emit_token(LeftParenToken) // (
  // Parse URL content until )
  while !(ctx.peek() is RightParen) &&
        !is_block_boundary(ctx.peek()) &&
        !(ctx.peek() is Newline) &&
        ctx.peek() != EOF {
    match ctx.peek() {
      Text(_) => ctx.emit_token(TextToken)
      _ => ctx.bump_error()
    }
  }
  if ctx.peek() is RightParen {
    ctx.emit_token(RightParenToken) // )
    ctx.finish_node()
  } else {
    // Unclosed parens — restore
    ctx.finish_node()
    ctx.restore(cp)
    ctx.start_node(ErrorNode)
    ctx.emit_token(LeftBracketToken)
    ctx.finish_node()
  }
}
