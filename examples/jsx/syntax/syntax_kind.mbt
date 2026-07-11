///|
pub(all) enum SyntaxKind {
  OpenTagStartToken
  TagNameToken
  SlashToken
  TagEndToken
  SelfCloseEndToken
  AttrNameToken
  EqToken
  AttrStringLitToken
  AttrStringLitUnterminatedToken
  BraceOpenToken
  BraceCloseToken
  ExprRawTextToken
  ExprStringUnterminatedToken
  TextToken
  FragmentOpenToken
  FragmentCloseToken
  WhitespaceToken
  ErrorToken
  EofToken
  ElementNode
  FragmentNode
  AttrNode
  ExprSpanNode
  TextLeaf
  ErrorNode
  RootNode
} derive(Debug, Eq)

///|
pub impl Show for SyntaxKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  match self {
    OpenTagStartToken
    | TagNameToken
    | SlashToken
    | TagEndToken
    | SelfCloseEndToken
    | AttrNameToken
    | EqToken
    | AttrStringLitToken
    | AttrStringLitUnterminatedToken
    | BraceOpenToken
    | BraceCloseToken
    | ExprRawTextToken
    | ExprStringUnterminatedToken
    | TextToken
    | FragmentOpenToken
    | FragmentCloseToken
    | WhitespaceToken
    | ErrorToken
    | EofToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {
  let n : Int = match self {
    OpenTagStartToken => 0
    TagNameToken => 1
    SlashToken => 2
    TagEndToken => 3
    SelfCloseEndToken => 4
    AttrNameToken => 5
    EqToken => 6
    AttrStringLitToken => 7
    AttrStringLitUnterminatedToken => 8
    BraceOpenToken => 9
    BraceCloseToken => 10
    ExprRawTextToken => 11
    ExprStringUnterminatedToken => 12
    TextToken => 13
    FragmentOpenToken => 14
    FragmentCloseToken => 15
    WhitespaceToken => 16
    ErrorToken => 17
    EofToken => 18
    ElementNode => 19
    FragmentNode => 20
    AttrNode => 21
    ExprSpanNode => 22
    TextLeaf => 23
    ErrorNode => 24
    RootNode => 25
  }
  @seam.RawKind(n)
}

///|
pub impl @seam.FromRawKind for SyntaxKind with fn from_raw(raw) {
  let @seam.RawKind(n) = raw
  match n {
    0 => OpenTagStartToken
    1 => TagNameToken
    2 => SlashToken
    3 => TagEndToken
    4 => SelfCloseEndToken
    5 => AttrNameToken
    6 => EqToken
    7 => AttrStringLitToken
    8 => AttrStringLitUnterminatedToken
    9 => BraceOpenToken
    10 => BraceCloseToken
    11 => ExprRawTextToken
    12 => ExprStringUnterminatedToken
    13 => TextToken
    14 => FragmentOpenToken
    15 => FragmentCloseToken
    16 => WhitespaceToken
    17 => ErrorToken
    18 => EofToken
    19 => ElementNode
    20 => FragmentNode
    21 => AttrNode
    22 => ExprSpanNode
    23 => TextLeaf
    24 => ErrorNode
    25 => RootNode
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
