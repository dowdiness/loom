// Inline parser for Markdown.
//
// Markdown delimiters (*, **, `, [) are ambiguous. Bold, italic, and links
// use speculative checkpoint/restore so malformed markup remains lossless.
// Code spans instead use a container-local delimiter index that pairs each
// eligible maximal backtick run with its next equal-length run. This keeps
// matching linear while preserving literal source spelling for unmatched runs.

///|
/// True when the current token ends an inline run: block markers, newlines,
/// blank lines, or EOF. Inline parsers check this to know when to stop.
fn is_inline_end(token : Token) -> Bool {
  is_block_boundary(token) || token is Newline || token == EOF
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
priv struct CodeSpanDelimiterIndex {
  eligible_openers : Map[Int, Bool]
  successors : Map[Int, Int]
}

///|
fn text_ends_with_odd_backslashes(text : StringView) -> Bool {
  let mut count = 0
  for ch in text {
    if ch == '\\' {
      count = count + 1
    } else {
      count = 0
    }
  }
  count % 2 == 1
}

///|
fn index_code_span_delimiter_run(
  index : CodeSpanDelimiterIndex,
  previous_by_length : Map[Int, Int],
  start : Int,
  run_length : Int,
  eligible_opener : Bool,
) -> Unit {
  index.eligible_openers[start] = eligible_opener
  match previous_by_length.get(run_length) {
    Some(previous) => index.successors[previous] = start
    None => ()
  }
  previous_by_length[run_length] = start
}

///|
priv enum ContinuationDecision[T] {
  Continue(T)
  Stop
}

///|
priv struct ContinuationHandler[T] {
  decide : () -> ContinuationDecision[T]
  consume : (T) -> Unit
}

///|
fn[T] continuation_step(
  handler : ContinuationHandler[T],
) -> () -> Bool {
  () => {
    match (handler.decide)() {
      Continue(action) => {
        (handler.consume)(action)
        true
      }
      Stop => false
    }
  }
}

///|
fn parse_indexed_inline_container_with_continue_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> Unit {
  let delimiters = ctx.lookahead(() => {
    let index : CodeSpanDelimiterIndex = {
      eligible_openers: {},
      successors: {},
    }
    let previous_by_length : Map[Int, Int] = {}
    let mut preceding_text_ends_escaped = false
    while true {
      while !token_is_inline_end(ctx.peek(), policy) {
        match ctx.peek() {
          Text(_) =>
            preceding_text_ends_escaped = text_ends_with_odd_backslashes(
              ctx.current_token_text(),
            )
          Backtick => {
            let range = ctx.current_token_range()
            let start = range.start
            let run_length = range.length()
            index_code_span_delimiter_run(
              index,
              previous_by_length,
              start,
              run_length,
              !preceding_text_ends_escaped,
            )
            preceding_text_ends_escaped = false
          }
          _ => preceding_text_ends_escaped = false
        }
        ctx.emit_current_token()
      }
      guard ctx.peek() is Newline && continue_line() else { break }
      preceding_text_ends_escaped = false
    }
    index
  })
  while true {
    while !token_is_inline_end(ctx.peek(), policy) {
      match ctx.peek() {
        Backtick => parse_indexed_inline_code(ctx, delimiters, continue_line)
        _ => parse_inline(ctx, policy, delimiters, continue_line)
      }
    }
    guard ctx.peek() is Newline && continue_line() else { break }
  }
}

///|
fn[T] parse_indexed_inline_container(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  handler : ContinuationHandler[T],
) -> Unit {
  let continue_line = continuation_step(handler)
  parse_indexed_inline_container_with_continue_line(ctx, policy, continue_line)
}

///|
fn parse_indexed_inline_container_without_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  parse_indexed_inline_container_with_continue_line(ctx, policy, () => false)
}

///|
fn parse_indexed_inline_code(
  ctx : @core.ParserContext[Token, SyntaxKind],
  delimiters : CodeSpanDelimiterIndex,
  continue_line : () -> Bool,
) -> Unit {
  let opener_start = ctx.current_token_range().start
  guard delimiters.eligible_openers.get(opener_start).unwrap_or(false) else {
    ctx.emit_token(BacktickToken)
    return
  }
  guard delimiters.successors.get(opener_start) is Some(closer_start) else {
    ctx.emit_token(BacktickToken)
    return
  }
  ctx.start_node(InlineCodeNode)
  ctx.emit_token(BacktickToken)
  while ctx.current_token_range().start != closer_start {
    if ctx.peek() is Newline {
      guard continue_line() else {
        abort("indexed code span crossed its container boundary")
      }
      continue
    }
    match ctx.peek() {
      Text(_) => ctx.emit_token(TextToken)
      Indentation(_) => ctx.emit_token(TextToken)
      Star => ctx.emit_token(StarToken)
      StarStar => ctx.emit_token(StarStarToken)
      Backtick => ctx.emit_token(BacktickToken)
      LeftBracket => ctx.emit_token(LeftBracketToken)
      RightBracket => ctx.emit_token(RightBracketToken)
      LeftParen => ctx.emit_token(LeftParenToken)
      RightParen => ctx.emit_token(RightParenToken)
      _ => ctx.bump_error()
    }
  }
  ctx.emit_token(BacktickToken)
  ctx.finish_node()
}

///|
/// Parse a single inline element.
fn parse_inline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  delimiters : CodeSpanDelimiterIndex,
  continue_line : () -> Bool,
) -> Unit {
  match ctx.peek() {
    StarStar => parse_bold(ctx, policy, delimiters, continue_line)
    Star => parse_italic(ctx, policy, delimiters, continue_line)
    Backtick => parse_indexed_inline_code(ctx, delimiters, continue_line)
    LeftBracket => parse_link(ctx, policy, delimiters, continue_line)
    Text(_) => ctx.emit_token(TextToken)
    Indentation(_) => ctx.emit_token(TextToken)
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
  delimiters : CodeSpanDelimiterIndex,
  continue_line : () -> Bool,
) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(BoldNode)
  ctx.emit_token(StarStarToken) // opening **
  // Parse inline content until closing ** or block boundary
  while !(ctx.peek() is StarStar) &&
        !token_is_inline_block_boundary(ctx.peek(), policy) {
    if ctx.peek() is Newline {
      if !continue_line() {
        break
      }
    } else {
      parse_inline(ctx, policy, delimiters, continue_line)
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
  delimiters : CodeSpanDelimiterIndex,
  continue_line : () -> Bool,
) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(ItalicNode)
  ctx.emit_token(StarToken) // opening *
  // Parse inline content until closing * or block boundary
  while !(ctx.peek() is Star) &&
        !token_is_inline_block_boundary(ctx.peek(), policy) {
    if ctx.peek() is Newline {
      if !continue_line() {
        break
      }
    } else {
      parse_inline(ctx, policy, delimiters, continue_line)
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
/// Parse link: [text](url)
fn parse_link(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  delimiters : CodeSpanDelimiterIndex,
  continue_line : () -> Bool,
) -> Unit {
  let cp = ctx.checkpoint()
  ctx.start_node(LinkNode)
  ctx.emit_token(LeftBracketToken) // [
  // Parse link text content until ]
  while !(ctx.peek() is RightBracket) && !is_inline_end(ctx.peek()) {
    parse_inline(ctx, policy, delimiters, continue_line)
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
