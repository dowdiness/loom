// Parse data types: token information, diagnostics, and lex errors.

///|
/// Generic position-independent token. T is the language-specific token type.
/// Positions are stored externally in TokenBuffer's `starts` array.
pub struct TokenInfo[T] {
  token : T
  len : Int // length in code units
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
pub fn[T] TokenInfo::new(token : T, len : Int) -> TokenInfo[T] {
  { token, len }
}

///|
/// Lexing stage output — designed for Memo[T : Eq] boundaries.
///
/// Carries position-independent tokens + the source text for parsing.
/// `source` is NOT part of equality — only the token sequence determines
/// whether the downstream parse memo recomputes.
pub(all) struct TokenStage[T] {
  tokens : Array[TokenInfo[T]]
  source : String
  is_lex_error : Bool
  lex_error_message : String
}

///|
/// Custom Eq: compares tokens + error state only, intentionally excluding `source`.
///
/// This drives the three-memo pipeline's early cutoff. The Salsa-style Memo
/// system calls `equal` to decide whether to backdate (skip downstream
/// recomputation). By excluding `source`, the CST memo skips re-parsing when
/// the token sequence is unchanged — even if the source text differs (e.g.,
/// different whitespace content that produces identical token kinds and lengths).
///
/// `source` is carried as data for the CST memo to use when it *does* recompute,
/// but it is not part of the identity.
pub impl[T : Eq] Eq for TokenStage[T] with equal(self, other) {
  self.is_lex_error == other.is_lex_error &&
  self.lex_error_message == other.lex_error_message &&
  self.tokens == other.tokens
}

///|
priv struct ReusedErrorSpan {
  start : Int
  end : Int
}
