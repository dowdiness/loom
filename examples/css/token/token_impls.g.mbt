///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      Ident => "<ident>"
      Colon => ":"
      Semicolon => ";"
      LBrace => "{"
      RBrace => "}"
      Number => "<int>"
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with fn is_trivia(self) {
  false
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
    Ident => 0
    Colon => 1
    Semicolon => 2
    LBrace => 3
    RBrace => 4
    Number => 5
    Error(_) => 6
    EOF => 7
  }
  @seam.RawKind(n)
}
