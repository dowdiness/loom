///|
/// CSS token enum for the #610 CSS parser capstone.
/// Exercises #loom.rule operators ~ (Emit), ! (EmitOr), @until (ErrorUntil).
#loom.token
pub(all) enum Token {
  #loom.ident
  Ident // identifiers (property names, values, selectors)
  #loom.punct(":")
  Colon // :
  #loom.punct(";")
  Semicolon // ;
  #loom.punct("{")
  LBrace // {
  #loom.punct("}")
  RBrace // }
  #loom.literal("NumberToken")
  Number // numeric literals
  #loom.error
  Error(String) // lexer error
  #loom.eof
  EOF // end of input
} derive(Eq, Debug)

///|
pub using @core {type TokenInfo}

///|
pub fn print_token(token : Token) -> String {
  token.to_string()
}

///|
pub fn print_tokens(tokens : Array[Token]) -> String {
  let token_strs = tokens.map(print_token)
  "[" + token_strs.join(", ") + "]"
}
