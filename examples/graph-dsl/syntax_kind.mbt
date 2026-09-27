///|
pub enum SyntaxKind {
  // Token kinds
  IdentifierToken
  NumberToken
  StringToken
  EqualToken
  LParenToken
  RParenToken
  ColonToken
  CommaToken
  ArrowToken
  NewlineToken
  WhitespaceToken
  ErrorToken
  // Node kinds
  RootNode
  BindingNode
  CallNode
  ArgumentNode
  ValueNode
  OutputNode
} derive(Eq, Debug)

///|
pub impl Show for SyntaxKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {
  let n : Int = match self {
    IdentifierToken => 0
    NumberToken => 1
    StringToken => 2
    EqualToken => 3
    LParenToken => 4
    RParenToken => 5
    ColonToken => 6
    CommaToken => 7
    ArrowToken => 8
    NewlineToken => 9
    WhitespaceToken => 10
    ErrorToken => 11
    RootNode => 13
    BindingNode => 14
    CallNode => 15
    ArgumentNode => 16
    ValueNode => 17
    OutputNode => 18
  }
  @seam.RawKind(n)
}

///|
pub extend SyntaxKind with @dowdiness/seam.ToRawKind::{to_raw}

///|
pub extend SyntaxKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyntaxKind with Eq::{equal, not_equal}

///|
pub extend SyntaxKind with Show::{output, to_string}
