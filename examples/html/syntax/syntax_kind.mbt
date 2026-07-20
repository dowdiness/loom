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
  Div
  Br
  Img
  Area
  Base
  Col
  Embed
  Hr
  Input
  Link
  Meta
  Param
  Source
  Track
  Wbr
  Script
  Style
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
    Div => 13
    Br => 14
    Img => 15
    Area => 24
    Base => 25
    Col => 26
    Embed => 27
    Hr => 28
    Input => 29
    Link => 30
    Meta => 31
    Param => 32
    Source => 33
    Track => 34
    Wbr => 35
    Script => 16
    Style => 17
    DoctypeNode => 18
    CommentNode => 19
    TextLeaf => 20
    RawTextLeaf => 21
    ErrorNode => 22
    RootNode => 23
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
    13 => Div
    14 => Br
    15 => Img
    24 => Area
    25 => Base
    26 => Col
    27 => Embed
    28 => Hr
    29 => Input
    30 => Link
    31 => Meta
    32 => Param
    33 => Source
    34 => Track
    35 => Wbr
    16 => Script
    17 => Style
    18 => DoctypeNode
    19 => CommentNode
    20 => TextLeaf
    21 => RawTextLeaf
    22 => ErrorNode
    23 => RootNode
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
