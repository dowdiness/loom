///|
pub(all) enum Token {
  Minus
  Arrow
  Let
  Ident
  Number
  Whitespace
  Error(String)
  EOF
} derive(Eq, Debug)
