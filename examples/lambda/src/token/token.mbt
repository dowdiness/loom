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
  Identifier(String) // variable names
  Integer(Int) // integer literals
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
      Identifier(name) => name
      Integer(n) => n.to_string()
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
pub using @core {type TokenInfo}

///|
/// Print a TokenInfo
pub fn print_token_info(token_info : TokenInfo[Token]) -> String {
  let token_str = print_token(token_info.token)
  token_str +
  "@" +
  token_info.start.to_string() +
  "-" +
  token_info.end.to_string()
}

///|
/// Print an array of TokenInfo
pub fn print_token_infos(tokens : Array[TokenInfo[Token]]) -> String {
  let token_strs = tokens.map(print_token_info)
  "[" + token_strs.join(", ") + "]"
}

///|
pub fn print_token(token : Token) -> String {
  match token {
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
    Identifier(name) => name
    Integer(n) => n.to_string()
    Whitespace => "whitespace"
    Newline => "newline"
    Error(msg) => "<error: " + msg + ">"
    EOF => "EOF"
  }
}

///|
pub fn print_tokens(tokens : Array[Token]) -> String {
  let token_strs = tokens.map(print_token)
  "[" + token_strs.join(", ") + "]"
}
