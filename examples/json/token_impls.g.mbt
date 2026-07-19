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
  match self {
    Whitespace => true
    _ => false
  }
}

///|
pub impl @seam.IsEof for Token with fn is_eof(self) {
  match self {
    EOF => true
    _ => false
  }
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
