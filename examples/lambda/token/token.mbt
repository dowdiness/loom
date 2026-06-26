///|
#loom.token
pub(all) enum Token {
  #loom.punct("λ")
  Lambda // legacy λ or \ (lexed for diagnostics; parser rejects as syntax)
  #loom.punct(".")
  Dot // .
  #loom.punct("(")
  LeftParen // (
  #loom.punct(")")
  RightParen // )
  #loom.punct("+")
  Plus // +
  #loom.punct("-")
  Minus // -
  #loom.keyword("if")
  If // if
  #loom.keyword("then")
  Then // then
  #loom.keyword("else")
  Else // else
  #loom.keyword("fn")
  Fn // fn
  #loom.keyword("let")
  Let // let value declaration
  #loom.punct("=")
  Eq // =
  #loom.punct("{")
  LBrace // {
  #loom.punct("}")
  RBrace // }
  #loom.punct(",")
  Comma // ,
  #loom.punct(";")
  Semicolon // ;
  #loom.punct(":")
  Colon // :
  #loom.punct("->")
  Arrow // ->
  #loom.punct("=>")
  FatArrow // =>
  #loom.punct("_")
  Hole // _ (typed hole placeholder)
  #loom.ident
  Identifier // variable names
  #loom.literal("IntToken")
  Integer // integer literals
  #loom.trivia
  Whitespace // whitespace (spaces, tabs — not newlines in layout mode)
  #loom.delimiter
  Newline // newline (\n or \r\n) — non-trivia in source-file grammar
  #loom.error
  Error(String) // lexer error placeholder for step-based resilient mode
  #loom.eof
  EOF // end of input
} derive(Eq, Debug)

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
