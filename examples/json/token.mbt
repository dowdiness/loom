///|
#loom.token
pub(all) enum Token {
  #loom.punct("{")
  LBrace // {
  #loom.punct("}")
  #loom.recovery("sync")
  RBrace // }
  #loom.punct("[")
  LBracket // [
  #loom.punct("]")
  #loom.recovery("sync")
  RBracket // ]
  #loom.punct(":")
  Colon // :
  #loom.punct(",")
  #loom.recovery("sync")
  Comma // ,
  #loom.literal("StringToken")
  StringLit // "hello" (raw text including quotes)
  #loom.literal("NumberToken")
  NumberLit // 42, 3.14e-2 (raw text)
  #loom.keyword("true")
  True // true
  #loom.keyword("false")
  False // false
  #loom.keyword("null")
  Null // null
  #loom.trivia
  Whitespace // spaces, tabs, newlines, carriage returns
  #loom.error
  Error(String) // lexer error
  #loom.eof
  #loom.recovery("sync")
  EOF // end of input
} derive(Eq, Debug)

///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      LBrace => "{"
      RBrace => "}"
      LBracket => "["
      RBracket => "]"
      Colon => ":"
      Comma => ","
      StringLit => "<string>"
      NumberLit => "<number>"
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
pub impl @seam.IsTrivia for Token with fn is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for Token with fn is_eof(self) {
  self == EOF
}

///|
/// Maps tokens to the same raw-kind space as SyntaxKind.
pub impl @seam.ToRawKind for Token with fn to_raw(self) {
  let n : Int = match self {
    LBrace => 0
    RBrace => 1
    LBracket => 2
    RBracket => 3
    Colon => 4
    Comma => 5
    StringLit => 6
    NumberLit => 7
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
