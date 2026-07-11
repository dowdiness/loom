///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      OpenTagStart => "<"
      TagName => "<int>"
      Slash => "/"
      TagEnd => ">"
      SelfCloseEnd => "/>"
      AttrName => "<int>"
      Eq => "="
      AttrStringLit => "<int>"
      AttrStringLitUnterminated => "<int>"
      BraceOpen => "{"
      BraceClose => "}"
      ExprRawText => "<int>"
      ExprStringUnterminated => "<int>"
      Text => "<int>"
      FragmentOpen => "<>"
      FragmentClose => "</>"
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
    OpenTagStart => 0
    TagName => 1
    Slash => 2
    TagEnd => 3
    SelfCloseEnd => 4
    AttrName => 5
    Eq => 6
    AttrStringLit => 7
    AttrStringLitUnterminated => 8
    BraceOpen => 9
    BraceClose => 10
    ExprRawText => 11
    ExprStringUnterminated => 12
    Text => 13
    FragmentOpen => 14
    FragmentClose => 15
    Whitespace => 16
    Error(_) => 17
    EOF => 18
  }
  @seam.RawKind(n)
}
