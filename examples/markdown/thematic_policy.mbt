///|
fn line_at_offset_is_thematic_break(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
) -> Bool {
  let line = StringBuilder::new()
  for i = offset {
    match ctx.peek_nth(i) {
      ThematicBreak(_) => break true
      Newline | EOF =>
        break is_valid_thematic_break_markers(line.to_string().view())
      Text(text) => line.write_string(text)
      Star => line.write_string("*")
      StarStar => line.write_string("**")
      _ => break false
    }
    continue i + 1
  }
}
///|
fn line_at_offset_is_thematic_break_from_facts(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
) -> Bool {
  let line = StringBuilder::new()
  for cursor = offset {
    let (token, end) = ctx.token_at(cursor, 0)
    match token {
      ThematicBreak(_) => break true
      Newline | EOF =>
        break is_valid_thematic_break_markers(line.to_string().view())
      Text(text) => line.write_string(text)
      Star => line.write_string("*")
      StarStar => line.write_string("**")
      _ => break false
    }
    continue end
  }
}


///|
fn next_unquoted_line_is_thematic_break(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  line_at_offset_is_thematic_break(ctx, 1)
}
