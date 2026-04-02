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
/// Stores the full lex output (tokens, positions, source) but only
/// **non-trivia tokens** and error state participate in equality.
/// Trivia tokens (whitespace, newlines), positions (`starts`), and source
/// text are all excluded from comparison. This means:
///
/// - Edits that only change whitespace → token memo backdates → parse skipped
/// - Edits that shift positions without changing content → same result
///
/// The CST memo reads `starts` and `source` from the (possibly stale)
/// TokenStage value when it needs to recompute. When the token memo
/// backdates, the CST memo does not recompute at all.
pub(all) struct TokenStage[T] {
  tokens : Array[TokenInfo[T]]
  starts : Array[Int]
  source : String
  is_lex_error : Bool
  lex_error_message : String
}

///|
/// Trivia-insensitive equality for early cutoff.
///
/// Compares non-trivia tokens by kind, length, AND source text. Trivia tokens
/// (whitespace, newlines) and token positions are excluded. Two TokenStages
/// that differ only in trivia are considered equal, causing the Salsa memo
/// to backdate and skip downstream parse/AST recomputation.
///
/// Source text is included so that payload-free token kinds (e.g. bare
/// `Identifier` or `Integer` with no embedded value) are still distinguished
/// by their actual content. A whitespace-only edit does not change any
/// non-trivia token's text, so it still backdates correctly.
pub impl[T : Eq + @seam.IsTrivia] Eq for TokenStage[T] with equal(self, other) {
  if self.is_lex_error != other.is_lex_error {
    return false
  }
  if self.lex_error_message != other.lex_error_message {
    return false
  }
  let a = self.tokens
  let b = other.tokens
  let mut ai = 0
  let mut bi = 0
  while ai < a.length() && bi < b.length() {
    if a[ai].token.is_trivia() {
      ai = ai + 1
      continue
    }
    if b[bi].token.is_trivia() {
      bi = bi + 1
      continue
    }
    if a[ai] != b[bi] {
      return false
    }
    // Also compare the actual source text so payload-free token kinds
    // (e.g. bare Integer, Identifier) are distinguished by content.
    let a_start = self.starts[ai]
    let b_start = other.starts[bi]
    let a_text = self.source[a_start:a_start + a[ai].len]
    let b_text = other.source[b_start:b_start + b[bi].len]
    if a_text != b_text {
      return false
    }
    ai = ai + 1
    bi = bi + 1
  }
  // Skip remaining trivia at the end
  while ai < a.length() && a[ai].token.is_trivia() {
    ai = ai + 1
  }
  while bi < b.length() && b[bi].token.is_trivia() {
    bi = bi + 1
  }
  ai == a.length() && bi == b.length()
}

///|
priv struct ReusedErrorSpan {
  start : Int
  end : Int
}
