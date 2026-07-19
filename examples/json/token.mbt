///|
#loom.token_set(value_start, LBrace, LBracket, StringLit, NumberLit, True, False, Null)
#loom.token
pub(all) enum Token {
  #loom.punct("{")
  LBrace // {
  #loom.punct("}")
  #loom.recovery("sync")
  RBrace // }
  #loom.punct("[")
  LBracket // [
  #loom.punct("]")
  #loom.recovery("sync")
  RBracket // ]
  #loom.punct(":")
  Colon // :
  #loom.punct(",")
  #loom.recovery("sync")
  Comma // ,
  #loom.literal("StringToken")
  #loom.display("<string>")
  StringLit // "hello" (raw text including quotes)
  #loom.display("<number>")
  #loom.literal("NumberToken")
  NumberLit // 42, 3.14e-2 (raw text)
  #loom.keyword("true")
  True // true
  #loom.keyword("false")
  False // false
  #loom.keyword("null")
  Null // null
  #loom.trivia
  #loom.display(" ")
  Whitespace // spaces, tabs, newlines, carriage returns
  #loom.error
  Error(String) // lexer error
  #loom.eof
  #loom.recovery("sync")
  EOF // end of input
} derive(Eq, Debug)

///|
pub fn print_token(token : Token) -> String {
  token.to_string()
}
