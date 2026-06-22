///|
pub enum Token {
  Identifier
  Number
  StringLit
  Equal
  LParen
  RParen
  Colon
  Comma
  Arrow
  Newline
  Whitespace
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      Identifier => "<identifier>"
      Number => "<number>"
      StringLit => "<string>"
      Equal => "="
      LParen => "("
      RParen => ")"
      Colon => ":"
      Comma => ","
      Arrow => "->"
      Newline => "\\n"
      Whitespace => " "
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with fn is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for Token with fn is_eof(self) {
  self == EOF
}

///|
pub impl @seam.ToRawKind for Token with fn to_raw(self) {
  let n : Int = match self {
    Identifier => 0
    Number => 1
    StringLit => 2
    Equal => 3
    LParen => 4
    RParen => 5
    Colon => 6
    Comma => 7
    Arrow => 8
    Newline => 9
    Whitespace => 10
    Error(_) => 11
    EOF => 12
  }
  @seam.RawKind(n)
}
