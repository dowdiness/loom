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
