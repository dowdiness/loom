// Parse data types: token information, diagnostics, and lex errors.

///|
/// Generic position-independent token. T is the language-specific token type.
/// Positions are stored externally in TokenBuffer's `starts` array.
pub struct TokenInfo[T] {
  token : T
  len : Int // length in code units
} derive(Debug, Eq)

///|
/// A parse diagnostic (error or warning) with source position.
/// Stores the offending token so consumers never need to re-tokenize.
pub struct Diagnostic[T] {
  message : String
  start : Int
  end : Int
  got_token : T
} derive(Debug)

///|
pub impl[T : Debug] Show for Diagnostic[T] with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Format a diagnostic as `"message [start,end]"`.
/// Used by factory functions to normalize diagnostics for parser consumers.
pub fn[T] format_diagnostic(d : Diagnostic[T]) -> String {
  d.message + " [" + d.start.to_string() + "," + d.end.to_string() + "]"
}

///|
/// Convert a diagnostic's source offsets to line/column coordinates.
pub fn[T] diagnostic_line_range(
  d : Diagnostic[T],
  index : LineIndex,
) -> LineRange {
  index.line_range(d.start, d.end)
}

///|
/// Format a diagnostic using 0-based line and UTF-16/code-unit column spans.
pub fn[T] format_diagnostic_with_line_col(
  d : Diagnostic[T],
  index : LineIndex,
) -> String {
  let range = diagnostic_line_range(d, index)
  d.message +
  " [" +
  format_line_col(range.start) +
  "," +
  format_line_col(range.end) +
  "]"
}

///|
fn format_line_col(pos : LineCol) -> String {
  pos.line.to_string() + ":" + pos.column.to_string()
}

///|
/// Lex error raised by a tokenize_fn when the source contains unrecognizable input.
/// Generic replacement for language-specific tokenization error types.
pub(all) suberror LexError {
  LexError(String)
}

///|
/// Construct a TokenInfo. Use this from outside the core package.
pub fn[T] TokenInfo::new(token : T, len : Int) -> TokenInfo[T] {
  { token, len }
}

///|
priv struct ReusedErrorSpan {
  start : Int
  end : Int
}
