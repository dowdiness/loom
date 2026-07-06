/// Fixture for #635 default lex patterns — no explicit #loom.pattern annotations.
/// Defaults: ident=[a-zA-Z_][a-zA-Z0-9_]*, literal=[0-9]+(\.[0-9]+)?, trivia=[ \t\r\n]+.
#loom.token
pub(all) enum Token {
  #loom.ident
  Ident
  #loom.literal
  Number
  #loom.trivia
  Whitespace
  #loom.error
  Error(String)
  #loom.eof
  EOF
} derive(Eq, Debug)
