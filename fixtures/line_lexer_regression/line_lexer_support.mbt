///|
/// Consume the rest of the current line, including its line ending. This is
/// the fallback used after a generated line marker has consumed its prefix.
fn lex_inline(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
  if pos >= source.length() {
    return (Done, LineStart)
  }
  let mut line_end = pos
  while line_end < source.length() {
    match source[line_end:line_end + 1].to_owned() {
      "\r" | "\n" => break
      _ => line_end = line_end + 1
    }
  }
  let newline_width = if line_end >= source.length() {
    0
  } else if line_end + 1 < source.length() &&
    source[line_end:line_end + 2].to_owned() == "\r\n" {
    2
  } else {
    1
  }
  let consumed_end = line_end + newline_width
  if line_end == pos {
    return (
      Produced(
        @core.TokenInfo::new(BlankLine, newline_width),
        next_offset=consumed_end,
      ),
      LineStart,
    )
  }
  (
    Produced(
      @core.TokenInfo::new(
        Text(source[pos:consumed_end].to_owned()),
        consumed_end - pos,
      ),
      next_offset=consumed_end,
    ),
    LineStart,
  )
}

///|
/// Extract the number of leading `#` characters from the generated match.
fn lex_heading_marker(
  _source : String,
  pos : Int,
  len : Int,
) -> (@core.LexStep[Token], LexMode) {
  (
    Produced(
      @core.TokenInfo::new(HeadingMarker(len - 1), len),
      next_offset=pos + len,
    ),
    LineStart,
  )
}

///|
/// Fixture-local dispatch mirroring the generated lexer skeleton contract.
pub fn lex(
  source : String,
  pos : Int,
  mode : LexMode,
) -> (@core.LexStep[Token], LexMode) {
  match mode {
    LineStart => lex_line_start(source, pos)
    Inline => lex_inline(source, pos)
  }
}
