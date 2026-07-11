///|
#loom.token
pub(all) enum Token {
  #loom.punct("λ")
  #loom.recovery("sync")
  Lambda // legacy λ or \ (lexed for diagnostics; parser rejects as syntax)
  #loom.punct(".")
  Dot // .
  #loom.punct("(")
  LeftParen // (
  #loom.punct(")")
  #loom.recovery("sync")
  RightParen // )
  #loom.punct("+")
  Plus // +
  #loom.punct("-")
  Minus // -
  #loom.keyword("if")
  #loom.recovery("sync")
  If // if
  #loom.keyword("then")
  #loom.recovery("sync")
  Then // then
  #loom.keyword("else")
  #loom.recovery("sync")
  Else // else
  #loom.keyword("fn")
  #loom.recovery("sync")
  Fn // fn
  #loom.keyword("let")
  #loom.recovery("sync")
  Let // let value declaration
  #loom.punct("=")
  Eq // =
  #loom.punct("{")
  #loom.recovery("sync")
  LBrace // {
  #loom.punct("}")
  #loom.recovery("sync")
  RBrace // }
  #loom.punct(",")
  Comma // ,
  #loom.punct(";")
  #loom.recovery("sync")
  Semicolon // ;
  #loom.punct(":")
  Colon // :
  #loom.punct("->")
  Arrow // ->
  #loom.punct("=>")
  #loom.recovery("sync")
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
  #loom.recovery("sync")
  Newline // newline (\n or \r\n) — non-trivia in source-file grammar
  #loom.error
  Error(String) // lexer error placeholder for step-based resilient mode
  #loom.eof
  #loom.recovery("sync")
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
