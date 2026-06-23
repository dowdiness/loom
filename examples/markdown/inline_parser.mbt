// Inline parser for Markdown.
//
// Markdown delimiters (*, **, `, [) are ambiguous: `*foo` might be
// an italic opener or literal text. We resolve this via speculative
// parsing with checkpoint/restore: open a CST node, parse content,
// and if the closing delimiter is missing before the line/block ends,
// restore the checkpoint and re-emit the opener as literal text
// wrapped in an ErrorNode. This preserves source fidelity while
// producing correct AST structure for well-formed markup.

///|
/// True when the current token ends an inline run: block markers, newlines,
/// blank lines, or EOF. Inline parsers check this to know when to stop.
fn is_inline_end(token : Token) -> Bool {
  is_block_boundary(token) || token is Newline || token == EOF
}

///|
/// Parse inline content until block boundary, newline, or EOF.
fn parse_inline_content(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_inline_content_with_policy(ctx, InlineParsePolicy::paragraph())
}

///|
fn parse_line_bound_inline_content(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  parse_inline_content_with_policy(ctx, InlineParsePolicy::line_bound())
}

///|
fn parse_setext_heading_inline_content(
  ctx : @core.ParserContext[Token, SyntaxKind],
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> Unit {
  parse_inline_content_with_policy(
    ctx,
    InlineParsePolicy::setext_heading(allow_list_marker~, min_indent~),
  )
}

///|
fn parse_list_item_setext_heading_inline_content(
  ctx : @core.ParserContext[Token, SyntaxKind],
  allow_ordered_marker~ : Bool,
  min_indent~ : Int,
) -> Unit {
  parse_inline_content_with_policy(
    ctx,
    InlineParsePolicy::list_item_setext_heading(
      allow_ordered_marker~,
      min_indent~,
    ),
  )
}

///|
fn token_is_inline_block_boundary(
  token : Token,
  policy : InlineParsePolicy,
) -> Bool {
  match token {
    OrderedListMarker(_) if policy.allows_ordered_marker() =>
      token_breaks_paragraph_after_newline(token)
    _ => is_block_boundary(token)
  }
}

///|
fn token_is_inline_end(token : Token, policy : InlineParsePolicy) -> Bool {
  token_is_inline_block_boundary(token, policy) || token is Newline
}

///|
fn parse_inline_content_with_policy(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  while !token_is_inline_end(ctx.peek(), policy) {
    parse_inline(ctx, policy)
  }
}

///|
/// Parse a single inline element.
fn parse_inline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  match ctx.peek() {
    StarStar => parse_bold(ctx, policy)
    Star => parse_italic(ctx, policy)
    Backtick => parse_inline_code(ctx)
    LeftBracket => parse_link(ctx, policy)
    Text(_) => ctx.emit_token(TextToken)
    IndentedCodeText(_) => ctx.emit_token(TextToken)
    OrderedListMarker(_) if policy.allows_ordered_marker() =>
      ctx.emit_token(TextToken)
    _ =>
      // Unexpected inline token — emit as error
      ctx.bump_error()
  }
}

///|
/// Parse bold: **content**
fn parse_bold(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(BoldNode)
  ctx.emit_token(StarStarToken) // opening **
  // Parse inline content until closing ** or block boundary
  while !(ctx.peek() is StarStar) &&
        !token_is_inline_block_boundary(ctx.peek(), policy) {
    if ctx.peek() is Newline {
      if !policy.softbreak_continues(ctx) {
        break
      }
      ctx.emit_token(NewlineToken)
    } else {
      parse_inline(ctx, policy)
    }
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
fn parse_italic(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(ItalicNode)
  ctx.emit_token(StarToken) // opening *
  // Parse inline content until closing * or block boundary
  while !(ctx.peek() is Star) &&
        !token_is_inline_block_boundary(ctx.peek(), policy) {
    if ctx.peek() is Newline {
      if !policy.softbreak_continues(ctx) {
        break
      }
      ctx.emit_token(NewlineToken)
    } else {
      parse_inline(ctx, policy)
    }
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
  while !(ctx.peek() is Backtick) && !is_inline_end(ctx.peek()) {
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
fn parse_link(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(LinkNode)
  ctx.emit_token(LeftBracketToken) // [
  // Parse link text content until ]
  while !(ctx.peek() is RightBracket) && !is_inline_end(ctx.peek()) {
    parse_inline(ctx, policy)
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
  // Parse URL content until the matching outer ). Balanced parentheses are
  // part of the URL and must not terminate the link destination early.
  let mut depth = 1
  while depth > 0 && !is_inline_end(ctx.peek()) {
    match ctx.peek() {
      LeftParen => {
        depth = depth + 1
        ctx.emit_token(LeftParenToken)
      }
      RightParen => {
        depth = depth - 1
        ctx.emit_token(RightParenToken)
      }
      Text(_) => ctx.emit_token(TextToken)
      Star => ctx.emit_token(StarToken)
      StarStar => ctx.emit_token(StarStarToken)
      Backtick => ctx.emit_token(BacktickToken)
      LeftBracket => ctx.emit_token(LeftBracketToken)
      RightBracket => ctx.emit_token(RightBracketToken)
      _ => ctx.bump_error()
    }
  }
  if depth == 0 {
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
