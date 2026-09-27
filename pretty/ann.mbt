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
pub impl Show for SyntaxCategory with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct Span {
  start : Int
  end : Int
} derive(Debug, Eq)

///|
pub impl Show for Span with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend SyntaxCategory with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyntaxCategory with Eq::{not_equal, equal}

///|
pub extend SyntaxCategory with Show::{to_string, output}

///|
pub extend Span with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Span with Eq::{not_equal, equal}

///|
pub extend Span with Show::{to_string, output}
