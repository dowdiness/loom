/// Fixture for #521 lexer generation. Exercises punct longest-match (`-` vs
/// `->`), keyword post-classification, identifier/number patterns, and a
/// whitespace trivia pattern.

#loom.token
pub(all) enum Token {
  #loom.punct("-")
  Minus
  #loom.punct("->")
  Arrow
  #loom.keyword("let")
  Let
  #loom.ident
  #loom.pattern("[a-zA-Z_][a-zA-Z0-9_]*")
  Ident
  #loom.literal
  #loom.pattern("[0-9]+")
  Number
  #loom.trivia
  #loom.pattern("[ \t\r\n]+")
  Whitespace
  #loom.error
  Error(String)
  #loom.eof
  EOF
} derive(Eq, Debug)
