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
/// Carries the parse inputs needed downstream: tokens, their explicit starts,
/// Token sequence for the three-memo pipeline.
///
/// Stores the full lex output (tokens, positions, source) but only `tokens`
/// and error state participate in equality. Positions (`starts`) and source
/// text are carried for consumption by the downstream CST memo but are
/// excluded from comparison. This means edits that shift positions without
/// changing token kinds/lengths cause the memo to backdate, enabling early
/// cutoff for downstream parse and AST memos.
pub(all) struct TokenStage[T] {
  tokens : Array[TokenInfo[T]]
  starts : Array[Int]
  source : String
  is_lex_error : Bool
  lex_error_message : String
}

///|
/// Equality for early cutoff: compares only tokens + error state.
///
/// `starts` and `source` are intentionally excluded — two TokenStages with
/// the same token sequence but different positions are considered equal.
/// This is correct because CstNode is position-independent and will produce
/// the same parse tree from the same token sequence.
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
