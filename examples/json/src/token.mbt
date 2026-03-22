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
pub fn print_token(token : Token) -> String {
  token.to_string()
}
