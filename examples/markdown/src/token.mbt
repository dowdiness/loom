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
