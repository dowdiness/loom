///|
pub(all) enum SyntaxCategory {
  Keyword
  Identifier
  Number
  StringLit
  Operator
  Punctuation
  Comment
  Error
} derive(Show, Eq)

///|
pub(all) struct Span {
  start : Int
  end : Int
} derive(Show, Eq)
