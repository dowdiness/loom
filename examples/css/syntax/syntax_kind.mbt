///|
pub(all) enum SyntaxKind {
  IdentToken
  ColonToken
  SemicolonToken
  LBraceToken
  RBraceToken
  NumberToken
  WhitespaceToken
  ErrorToken
  EofToken
  Stylesheet
  Rule
  Decls
  Decl
  ErrorNode
} derive(Debug, Eq)

///|
pub impl Show for SyntaxKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  match self {
    IdentToken
    | ColonToken
    | SemicolonToken
    | LBraceToken
    | RBraceToken
    | NumberToken
    | WhitespaceToken
    | ErrorToken
    | EofToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {
  let n : Int = match self {
    IdentToken => 0
    ColonToken => 1
    SemicolonToken => 2
    LBraceToken => 3
    RBraceToken => 4
    NumberToken => 5
    WhitespaceToken => 6
    ErrorToken => 7
    EofToken => 8
    Stylesheet => 9
    Rule => 10
    Decls => 11
    Decl => 12
    ErrorNode => 13
  }
  @seam.RawKind(n)
}

///|
pub impl @seam.FromRawKind for SyntaxKind with fn from_raw(raw) {
  let @seam.RawKind(n) = raw
  match n {
    0 => IdentToken
    1 => ColonToken
    2 => SemicolonToken
    3 => LBraceToken
    4 => RBraceToken
    5 => NumberToken
    6 => WhitespaceToken
    7 => ErrorToken
    8 => EofToken
    9 => Stylesheet
    10 => Rule
    11 => Decls
    12 => Decl
    13 => ErrorNode
    _ => ErrorNode
  }
}

///|
pub impl @seam.IsTrivia for SyntaxKind with fn is_trivia(self) {
  self == WhitespaceToken
}

///|
pub impl @seam.IsError for SyntaxKind with fn is_error(self) {
  self == ErrorToken
}
