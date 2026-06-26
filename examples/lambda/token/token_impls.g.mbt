///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      Lambda => "λ"
      Dot => "."
      LeftParen => "("
      RightParen => ")"
      Plus => "+"
      Minus => "-"
      If => "if"
      Then => "then"
      Else => "else"
      Fn => "fn"
      Let => "let"
      Eq => "="
      LBrace => "{"
      RBrace => "}"
      Comma => ","
      Semicolon => ";"
      Colon => ":"
      Arrow => "->"
      FatArrow => "=>"
      Hole => "_"
      Identifier => "<ident>"
      Integer => "<int>"
      Whitespace => "whitespace"
      Newline => "newline"
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
    Lambda => 0
    Dot => 1
    LeftParen => 2
    RightParen => 3
    Plus => 4
    Minus => 5
    If => 6
    Then => 7
    Else => 8
    Fn => 43
    Let => 23
    Eq => 25
    LBrace => 29
    RBrace => 30
    Comma => 31
    Semicolon => 32
    Colon => 37
    Arrow => 38
    FatArrow => 44
    Hole => 35
    Identifier => 9
    Integer => 10
    Whitespace => 11
    Newline => 28
    Error(_) => 12
    EOF => 13
  }
  @seam.RawKind(n)
}
