///|
pub(all) enum Token {
  LBrace // {
  RBrace // }
  LBracket // [
  RBracket // ]
  Colon // :
  Comma // ,
  StringLit(String) // "hello" (raw text including quotes)
  NumberLit(String) // 42, 3.14e-2 (raw text)
  True // true
  False // false
  Null // null
  Whitespace // spaces, tabs, newlines, carriage returns
  Error(String) // lexer error
  EOF // end of input
} derive(Eq, Debug)

///|
pub impl Show for Token with output(self, logger) {
  logger.write_string(
    match self {
      LBrace => "{"
      RBrace => "}"
      LBracket => "["
      RBracket => "]"
      Colon => ":"
      Comma => ","
      StringLit(s) => s
      NumberLit(n) => n
      True => "true"
      False => "false"
      Null => "null"
      Whitespace => " "
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for Token with is_eof(self) {
  self == EOF
}

///|
/// Maps tokens to the same raw-kind space as SyntaxKind.
pub impl @seam.ToRawKind for Token with to_raw(self) {
  let n : Int = match self {
    LBrace => 0
    RBrace => 1
    LBracket => 2
    RBracket => 3
    Colon => 4
    Comma => 5
    StringLit(_) => 6
    NumberLit(_) => 7
    True => 8
    False => 9
    Null => 10
    Whitespace => 11
    Error(_) => 12
    EOF => 13
  }
  @seam.RawKind(n)
}

///|
pub fn print_token(token : Token) -> String {
  token.to_string()
}
