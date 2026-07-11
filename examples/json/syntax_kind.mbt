///|
pub(all) enum SyntaxKind {
  LBraceToken
  RBraceToken
  LBracketToken
  RBracketToken
  ColonToken
  CommaToken
  StringToken
  NumberToken
  TrueKeyword
  FalseKeyword
  NullKeyword
  WhitespaceToken
  ErrorToken
  EofToken
  ObjectNode
  ArrayNode
  MemberNode
  StringValue
  NumberValue
  BoolValue
  NullValue
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
    LBraceToken
    | RBraceToken
    | LBracketToken
    | RBracketToken
    | ColonToken
    | CommaToken
    | StringToken
    | NumberToken
    | TrueKeyword
    | FalseKeyword
    | NullKeyword
    | WhitespaceToken
    | ErrorToken
    | EofToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {
  let n : Int = match self {
    LBraceToken => 0
    RBraceToken => 1
    LBracketToken => 2
    RBracketToken => 3
    ColonToken => 4
    CommaToken => 5
    StringToken => 6
    NumberToken => 7
    TrueKeyword => 8
    FalseKeyword => 9
    NullKeyword => 10
    WhitespaceToken => 11
    ErrorToken => 12
    EofToken => 13
    ObjectNode => 14
    ArrayNode => 15
    MemberNode => 16
    StringValue => 17
    NumberValue => 18
    BoolValue => 19
    NullValue => 20
    ErrorNode => 21
    RootNode => 22
  }
  @seam.RawKind(n)
}

///|
pub impl @seam.FromRawKind for SyntaxKind with fn from_raw(raw) {
  let @seam.RawKind(n) = raw
  match n {
    0 => LBraceToken
    1 => RBraceToken
    2 => LBracketToken
    3 => RBracketToken
    4 => ColonToken
    5 => CommaToken
    6 => StringToken
    7 => NumberToken
    8 => TrueKeyword
    9 => FalseKeyword
    10 => NullKeyword
    11 => WhitespaceToken
    12 => ErrorToken
    13 => EofToken
    14 => ObjectNode
    15 => ArrayNode
    16 => MemberNode
    17 => StringValue
    18 => NumberValue
    19 => BoolValue
    20 => NullValue
    21 => ErrorNode
    22 => RootNode
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
