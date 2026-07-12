///|

///|
fn fixture_lexer() -> @core.ModeLexer[Token, LexMode] {
  { lex_step: lex, initial_mode: LineStart }
}

///|
test "generated line-mode lexer tokenizes Markdown lines" {
  let source = "# Heading\n\n- item\n> quote\n"
  let lexer = fixture_lexer()
  let (tokens, modes) = @core.tokenize_with_modes(lexer, source, EOF)
  guard tokens ==
    [
      @core.TokenInfo::new(HeadingMarker(1), 2),
      @core.TokenInfo::new(Text("Heading\n"), 8),
      @core.TokenInfo::new(BlankLine, 1),
      @core.TokenInfo::new(ListMarker, 2),
      @core.TokenInfo::new(Text("item\n"), 5),
      @core.TokenInfo::new(BlockQuoteMarker, 1),
      @core.TokenInfo::new(Text(" quote\n"), 7),
      @core.TokenInfo::new(EOF, 0),
    ] else {
    fail("generated lexer token sequence mismatch")
  }
  guard @core.build_starts(tokens) == [0, 2, 10, 11, 13, 18, 19, 26] else {
    fail("generated lexer token positions mismatch")
  }
  guard modes ==
    [
      LineStart,
      LineStart,
      LineStart,
      LineStart,
      LineStart,
      LineStart,
      LineStart,
      LineStart,
    ] else {
    fail("generated lexer mode sequence mismatch")
  }
  match lex_line_start(source, source.length()) {
    (Done, LineStart) => ()
    _ => fail("generated line lexer must return Done at EOF")
  }
}

///|
test "generated line-mode lexer preserves CRLF line lengths" {
  let source = "# H\r\n\r\n- x\r\n"
  let lexer = fixture_lexer()
  let (tokens, _modes) = @core.tokenize_with_modes(lexer, source, EOF)
  guard tokens ==
    [
      @core.TokenInfo::new(HeadingMarker(1), 2),
      @core.TokenInfo::new(Text("H\r\n"), 3),
      @core.TokenInfo::new(BlankLine, 2),
      @core.TokenInfo::new(ListMarker, 2),
      @core.TokenInfo::new(Text("x\r\n"), 3),
      @core.TokenInfo::new(EOF, 0),
    ] else {
    fail("generated lexer CRLF sequence mismatch")
  }
  guard @core.build_starts(tokens) == [0, 2, 5, 7, 9, 12] else {
    fail("generated lexer CRLF positions mismatch")
  }
}
