///|
pub(all) enum Token {
  Lambda // λ or \
  Dot // .
  LeftParen // (
  RightParen // )
  Plus // +
  Minus // -
  If // if
  Then // then
  Else // else
  Let // let
  In // in
  Eq // =
  LBrace // {
  RBrace // }
  Comma // ,
  Semicolon // ;
  Hole // _ (typed hole placeholder)
  Identifier // variable names
  Integer // integer literals
  Whitespace // whitespace (spaces, tabs — not newlines in layout mode)
  Newline // newline (\n or \r\n) — non-trivia in source-file grammar
  Error(String) // lexer error placeholder for step-based resilient mode
  EOF // end of input
} derive(Eq, Debug)

///|
pub impl Show for Token with output(self, logger) {
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
      Let => "let"
      In => "in"
      Eq => "="
      LBrace => "{"
      RBrace => "}"
      Comma => ","
      Semicolon => ";"
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
pub impl @seam.IsTrivia for Token with is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for Token with is_eof(self) {
  self == EOF
}

///|
/// Maps tokens to the same raw-kind space as SyntaxKind.
/// Fixed tokens map to their corresponding SyntaxKind raw values.
/// Value-carrying tokens (Identifier, Integer) map to IdentToken/IntToken kinds.
pub impl @seam.ToRawKind for Token with to_raw(self) {
  let n : Int = match self {
    Lambda => 0 // LambdaToken
    Dot => 1 // DotToken
    LeftParen => 2 // LeftParenToken
    RightParen => 3 // RightParenToken
    Plus => 4 // PlusToken
    Minus => 5 // MinusToken
    If => 6 // IfKeyword
    Then => 7 // ThenKeyword
    Else => 8 // ElseKeyword
    Identifier => 9 // IdentToken
    Integer => 10 // IntToken
    Whitespace => 11 // WhitespaceToken
    Error(_) => 12 // ErrorToken
    EOF => 13 // EofToken
    Let => 23 // LetKeyword
    In => 24 // InKeyword (gap in SyntaxKind numbering)
    Eq => 25 // EqToken
    Newline => 28 // NewlineToken
    LBrace => 29 // LBraceToken
    RBrace => 30 // RBraceToken
    Comma => 31 // CommaToken
    Semicolon => 32 // SemicolonToken
    Hole => 35 // HoleToken
  }
  @seam.RawKind(n)
}

///|
pub using @core {type TokenInfo}

///|
/// Print a TokenInfo (position-independent: shows token(len) format)
pub fn print_token_info(token_info : TokenInfo[Token]) -> String {
  let token_str = print_token(token_info.token)
  token_str + "(" + token_info.len.to_string() + ")"
}

///|
/// Print an array of TokenInfo
pub fn print_token_infos(tokens : Array[TokenInfo[Token]]) -> String {
  let token_strs = tokens.map(print_token_info)
  "[" + token_strs.join(", ") + "]"
}

///|
pub fn print_token(token : Token) -> String {
  token.to_string()
}

///|
pub fn print_tokens(tokens : Array[Token]) -> String {
  let token_strs = tokens.map(print_token)
  "[" + token_strs.join(", ") + "]"
}
