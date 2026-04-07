///|
pub(all) enum SyntaxKind {
  // Token kinds
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
  // Node kinds
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
pub impl Show for SyntaxKind with output(self, logger) {
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
pub impl @seam.ToRawKind for SyntaxKind with to_raw(self) {
  match self {
    LBraceToken => @seam.RawKind(0)
    RBraceToken => @seam.RawKind(1)
    LBracketToken => @seam.RawKind(2)
    RBracketToken => @seam.RawKind(3)
    ColonToken => @seam.RawKind(4)
    CommaToken => @seam.RawKind(5)
    StringToken => @seam.RawKind(6)
    NumberToken => @seam.RawKind(7)
    TrueKeyword => @seam.RawKind(8)
    FalseKeyword => @seam.RawKind(9)
    NullKeyword => @seam.RawKind(10)
    WhitespaceToken => @seam.RawKind(11)
    ErrorToken => @seam.RawKind(12)
    EofToken => @seam.RawKind(13)
    ObjectNode => @seam.RawKind(14)
    ArrayNode => @seam.RawKind(15)
    MemberNode => @seam.RawKind(16)
    StringValue => @seam.RawKind(17)
    NumberValue => @seam.RawKind(18)
    BoolValue => @seam.RawKind(19)
    NullValue => @seam.RawKind(20)
    ErrorNode => @seam.RawKind(21)
    RootNode => @seam.RawKind(22)
  }
}

///|
pub fn SyntaxKind::from_raw(raw : @seam.RawKind) -> SyntaxKind {
  match raw.0 {
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
    _ => ErrorToken
  }
}
