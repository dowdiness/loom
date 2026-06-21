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
fn setext_underline_depth_at_current_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> Int? {
  match ctx.peek() {
    Text(text) if text_has_min_leading_spaces(text.view(), min_indent) =>
      parse_setext_underline_depth(text.view())
    ThematicBreak if current_token_text_has_min_leading_spaces(ctx, min_indent) =>
      parse_setext_underline_depth(ctx.current_token_text())
    ListMarker if allow_list_marker &&
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
  let cp = ctx.checkpoint()
  ctx.emit_token(NewlineToken)
  let depth = setext_underline_depth_at_current_line(
    ctx,
    allow_list_marker~,
    min_indent~,
  )
  ctx.restore(cp)
  depth
}

///|
fn quoted_setext_underline_depth_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int? {
  let cp = ctx.checkpoint()
  ctx.emit_token(NewlineToken)
  let depth = match ctx.peek() {
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
  ctx.restore(cp)
  depth
}
