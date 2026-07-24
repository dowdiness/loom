///|
fn text_has_min_leading_spaces(text : StringView, min_indent : Int) -> Bool {
  let spaces = for ch in text; count = 0 {
    match ch {
      ' ' => continue count + 1
      _ => break count
    }
  } nobreak {
    count
  }
  spaces >= min_indent
}

///|
fn current_token_text_has_min_leading_spaces(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Bool {
  text_has_min_leading_spaces(ctx.current_token_text(), min_indent)
}

///|
fn setext_list_marker_line_ends_after_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek_nth(1) {
    Newline | BlankLine | EOF => true
    Text(text) if !direct_list_item_text_has_non_blank_content(text) =>
      ctx.peek_nth(2) is Newline ||
      ctx.peek_nth(2) is BlankLine ||
      ctx.peek_nth(2) is EOF
    _ => false
  }
}
///|
fn setext_list_marker_line_ends_after_marker_at(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
) -> Bool {
  let (_, marker_end) = ctx.token_at(offset, 0)
  let (next, next_end) = ctx.token_at(marker_end, 0)
  match next {
    Newline | BlankLine | EOF => true
    Text(text) if !direct_list_item_text_has_non_blank_content(text) => {
      let (following, _) = ctx.token_at(next_end, 0)
      following is Newline || following is BlankLine || following is EOF
    }
    _ => false
  }
}
///|
fn setext_underline_depth_from_fact(
  ctx : @core.ParserContext[Token, SyntaxKind],
  token : Token,
  offset : Int,
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> Int? {
  match token {
    Text(text) if text_has_min_leading_spaces(text.view(), min_indent) =>
      parse_setext_underline_depth(text.view())
    ThematicBreak(text) if min_indent == 0 =>
      parse_setext_underline_depth(text.view())
    ListMarker(marker) if min_indent == 0 && allow_list_marker &&
      setext_list_marker_line_ends_after_marker_at(ctx, offset) =>
      parse_setext_underline_depth(marker.text().view())
    _ => None
  }
}

///|
fn setext_underline_depth_after_newline_at(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> Int? {
  let (newline, next_offset) = ctx.token_at(offset, 0)
  guard newline is Newline else { return None }
  let (next, next_end) = ctx.token_at(next_offset, 0)
  match next {
    Indentation(text) => {
      let indent = count_leading_indent(text.view())
      if indent >= min_indent && indent < min_indent + 4 {
        let (following, _) = ctx.token_at(next_end, 0)
        setext_underline_depth_from_fact(
          ctx,
          following,
          next_end,
          allow_list_marker~,
          min_indent=0,
        )
      } else {
        None
      }
    }
    _ =>
      setext_underline_depth_from_fact(
        ctx,
        next,
        next_offset,
        allow_list_marker~,
        min_indent~,
      )
  }
}
///|
fn quoted_setext_underline_depth_after_newline_at(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
) -> Int? {
  let (newline, marker_offset) = ctx.token_at(offset, 0)
  guard newline is Newline else { return None }
  let (marker, content_offset) = ctx.token_at(marker_offset, 0)
  guard marker is BlockQuoteMarker else { return None }
  let (content, _) = ctx.token_at(content_offset, 0)
  setext_underline_depth_from_fact(
    ctx,
    content,
    content_offset,
    allow_list_marker=true,
    min_indent=0,
  )
}




///|
fn setext_underline_depth_at_current_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> Int? {
  match ctx.peek() {
    Text(text) if text_has_min_leading_spaces(text.view(), min_indent) =>
      parse_setext_underline_depth(text.view())
    ThematicBreak(_) if current_token_text_has_min_leading_spaces(
        ctx, min_indent,
      ) => parse_setext_underline_depth(ctx.current_token_text())
    ListMarker(_) if allow_list_marker &&
      current_token_text_has_min_leading_spaces(ctx, min_indent) &&
      setext_list_marker_line_ends_after_marker(ctx) =>
      parse_setext_underline_depth(ctx.current_token_text())
    _ => None
  }
}

///|
fn setext_underline_depth_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> Int? {
  ctx.lookahead(() => {
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      Indentation(_) => {
        let indent = current_token_leading_indent(ctx)
        if indent >= min_indent && indent < min_indent + 4 {
          ctx.emit_token(IndentationToken)
          setext_underline_depth_at_current_line(
            ctx,
            allow_list_marker~,
            min_indent=0,
          )
        } else {
          None
        }
      }
      _ =>
        setext_underline_depth_at_current_line(
          ctx,
          allow_list_marker~,
          min_indent~,
        )
    }
  })
}

///|
fn quoted_setext_underline_depth_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int? {
  ctx.lookahead(() => {
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      BlockQuoteMarker => {
        ctx.emit_token(BlockQuoteMarkerToken)
        setext_underline_depth_at_current_line(
          ctx,
          allow_list_marker=true,
          min_indent=0,
        )
      }
      _ => None
    }
  })
}
