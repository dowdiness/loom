///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      OpenTag(_) => "<int>"
      CloseTag(_) => "<int>"
      Eq => "="
      StringLit => "<int>"
      Text => "<int>"
      Comment => "<int>"
      Doctype => "<int>"
      RawText => "<int>"
      CData => "<int>"
      Whitespace => "whitespace"
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
    OpenTag(_) => 0
    CloseTag(_) => 1
    Eq => 2
    StringLit => 3
    Text => 4
    Comment => 5
    Doctype => 6
    RawText => 7
    CData => 8
    Whitespace => 9
    Error(_) => 10
    EOF => 11
  }
  @seam.RawKind(n)
}
