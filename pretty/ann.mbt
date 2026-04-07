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
  EvalAnnotation
  EvalError
} derive(Debug, Eq)

///|
pub impl Show for SyntaxCategory with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct Span {
  start : Int
  end : Int
} derive(Debug, Eq)

///|
pub impl Show for Span with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
