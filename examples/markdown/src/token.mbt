///|
pub(all) enum Token {
  HeadingMarker(Int) // "# " = 1, "## " = 2, etc. (includes trailing space)
  ListMarker // "- " or "* " or "+ " (includes trailing space)
  CodeFenceOpen(Int, String) // backtick count, info string
  CodeFenceClose // closing fence
  BlankLine // empty or whitespace-only line
  Star // *
  StarStar // **
  Backtick // `
  LeftBracket // [
  RightBracket // ]
  LeftParen // (
  RightParen // )
  Text(String) // plain text run (includes inter-word spaces)
  CodeText(String) // line of code block content
  Newline // \n
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for Token with output(self, logger) {
  logger.write_string(
    match self {
      HeadingMarker(n) => "#".repeat(n) + " "
      ListMarker => "- "
      CodeFenceOpen(n, info) => "`".repeat(n) + info
      CodeFenceClose => "```"
      BlankLine => ""
      Star => "*"
      StarStar => "**"
      Backtick => "`"
      LeftBracket => "["
      RightBracket => "]"
      LeftParen => "("
      RightParen => ")"
      Text(s) => s
      CodeText(s) => s
      Newline => "\n"
      Error(msg) => "<error: " + msg + ">"
      EOF => ""
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with is_trivia(_self) {
  false
}

///|
pub impl @seam.IsEof for Token with is_eof(self) {
  self == EOF
}

///|
/// Maps Token to the same RawKind as the corresponding SyntaxKind.
/// Payload-carrying variants (HeadingMarker, CodeFenceOpen, Text, CodeText)
/// collapse to their kind — text is available via token_text_at at the framework level.
pub impl @seam.ToRawKind for Token with to_raw(self) {
  @seam.RawKind(
    match self {
      HeadingMarker(_) => 0 // HeadingMarkerToken
      ListMarker => 1 // ListMarkerToken
      CodeFenceOpen(_, _) => 2 // CodeFenceOpenToken
      CodeFenceClose => 3 // CodeFenceCloseToken
      BlankLine => 4 // BlankLineToken
      Star => 5 // StarToken
      StarStar => 6 // StarStarToken
      Backtick => 7 // BacktickToken
      LeftBracket => 8 // LeftBracketToken
      RightBracket => 9 // RightBracketToken
      LeftParen => 10 // LeftParenToken
      RightParen => 11 // RightParenToken
      Text(_) => 12 // TextToken
      CodeText(_) => 13 // CodeTextToken
      Newline => 14 // NewlineToken
      Error(_) => 15 // ErrorToken
      EOF => 16 // EofToken
    },
  )
}
