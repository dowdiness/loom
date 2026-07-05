///|
pub(all) enum SyntaxKind {
  OpenTagToken
  CloseTagToken
  EqToken
  StringToken
  TextToken
  CommentToken
  DoctypeToken
  RawTextToken
  CDataToken
  WhitespaceToken
  ErrorToken
  EofToken
  ElementNode
  DoctypeNode
  CommentNode
  TextLeaf
  RawTextLeaf
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
    OpenTagToken
    | CloseTagToken
    | EqToken
    | StringToken
    | TextToken
    | CommentToken
    | DoctypeToken
    | RawTextToken
    | CDataToken
    | WhitespaceToken
    | ErrorToken
    | EofToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {
  let n : Int = match self {
    OpenTagToken => 0
    CloseTagToken => 1
    EqToken => 2
    StringToken => 3
    TextToken => 4
    CommentToken => 5
    DoctypeToken => 6
    RawTextToken => 7
    CDataToken => 8
    WhitespaceToken => 9
    ErrorToken => 10
    EofToken => 11
    ElementNode => 12
    DoctypeNode => 13
    CommentNode => 14
    TextLeaf => 15
    RawTextLeaf => 16
    ErrorNode => 17
    RootNode => 18
  }
  @seam.RawKind(n)
}

///|
pub impl @seam.FromRawKind for SyntaxKind with fn from_raw(raw) {
  let @seam.RawKind(n) = raw
  match n {
    0 => OpenTagToken
    1 => CloseTagToken
    2 => EqToken
    3 => StringToken
    4 => TextToken
    5 => CommentToken
    6 => DoctypeToken
    7 => RawTextToken
    8 => CDataToken
    9 => WhitespaceToken
    10 => ErrorToken
    11 => EofToken
    12 => ElementNode
    13 => DoctypeNode
    14 => CommentNode
    15 => TextLeaf
    16 => RawTextLeaf
    17 => ErrorNode
    18 => RootNode
    _ => ErrorNode
  }
}

///|
pub impl @seam.IsTrivia for SyntaxKind with fn is_trivia(self) {
  self == WhitespaceToken
}

///|
pub impl @seam.IsError for SyntaxKind with fn is_error(self) {
  self == ErrorToken || self == ErrorNode
}
