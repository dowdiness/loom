// Parse data types: token information, diagnostics, and lex errors.

///|
/// Generic token with source position. T is the language-specific token type.
pub struct TokenInfo[T] {
  token : T
  start : Int // code-unit offset, inclusive
  end : Int // code-unit offset, exclusive
} derive(Show, Eq)

///|
/// A parse diagnostic (error or warning) with source position.
/// Stores the offending token so consumers never need to re-tokenize.
pub struct Diagnostic[T] {
  message : String
  start : Int
  end : Int
  got_token : T
} derive(Show)

///|
/// Format a diagnostic as `"message [start,end]"`.
/// Used by factory functions to normalize diagnostics for parser consumers.
pub fn[T] format_diagnostic(d : Diagnostic[T]) -> String {
  d.message + " [" + d.start.to_string() + "," + d.end.to_string() + "]"
}

///|
/// Lex error raised by a tokenize_fn when the source contains unrecognizable input.
/// Generic replacement for language-specific tokenization error types.
pub(all) suberror LexError {
  LexError(String)
}

///|
/// Construct a TokenInfo. Use this from outside the core package.
pub fn[T] TokenInfo::new(token : T, start : Int, end : Int) -> TokenInfo[T] {
  { token, start, end }
}

///|
priv struct ReusedErrorSpan {
  start : Int
  end : Int
}
