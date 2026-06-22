// Generic parser infrastructure — ParserContext[T, K]

///|
/// A sorted sequence addressable by integer offset.
/// Implement this trait to make a type searchable with lower_bound.
///
/// Design note: uses a trait instead of a closure pair (count, get_key) so the
/// same lower_bound function works on both Array[OldToken] (searched by .start)
/// and ReuseCursor[T,K] (searched by get_start closure) without threading extra
/// arguments. Two impls suffice — no stdlib binary_search is available in
/// MoonBit, and stdlib exact-match search would require Compare on full elements
/// rather than on an extracted key field.
priv trait OffsetIndexed {
  /// Total number of elements in the sorted sequence.
  fn length(Self) -> Int
  /// The sort key (code-unit offset) at index i. Must be non-decreasing in i.
  fn offset_at(Self, Int) -> Int
}

///|
/// Lower-bound binary search over any OffsetIndexed source.
///
/// Returns the first index i where offset_at(i) >= target, or source.length()
/// if every element is smaller (i.e. "would insert at end").
///
/// Invariant maintained throughout:
///   - Every index < lo has offset_at < target  (definitely too small)
///   - Every index >= hi has offset_at >= target (candidate or answer)
/// When lo == hi the loop exits and lo is the answer.
///
/// Note: uses < rather than subtraction for comparison to avoid integer
/// overflow on large offsets.
fn[S : OffsetIndexed] lower_bound(source : S, target : Int) -> Int {
  let mut lo = 0
  let mut hi = source.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if source.offset_at(mid) < target {
      lo = mid + 1 // mid is too small; exclude it
    } else {
      hi = mid // mid is a candidate; keep it
    }
  }
  lo
}

///|
/// Describes one language to the generic parser infrastructure.
/// Create one instance at module init — it is reused across all parses.
///
/// Fields:
///   whitespace_kind — the SyntaxKind for whitespace trivia nodes in the tree
///   error_kind      — the SyntaxKind for error tokens/nodes
///   root_kind       — the SyntaxKind for the root node (e.g. SourceFile)
///   eof_token       — the T value returned when past end of input
///   K must implement ToRawKind (enforced on functions that call k.to_raw())
///   T must implement Eq + IsTrivia + IsEof (enforced on functions that use them)
pub struct LanguageSpec[T, K] {
  whitespace_kind : K
  error_kind : K
  incomplete_kind : K
  root_kind : K
  eof_token : T
  // Grammar entry point. Called by parse_tokens_indexed to drive the full parse.
  // Receives a fully-configured ParserContext; parse_tokens_indexed calls
  // flush_trivia after parse_root returns, so parse_root need not call it.
  // Set to a no-op by default for call sites (e.g. tests) that use
  // parse_with() with an explicit grammar parameter instead.
  parse_root : (ParserContext[T, K]) -> Unit
  // Minimum text_len (in code units) for a CST node to be eligible for reuse.
  // Nodes smaller than this threshold are re-parsed instead of reused, avoiding
  // the overhead of cursor seek + 4-condition check on tiny subtrees.
  reuse_size_threshold : Int
}

///|
/// Construct a LanguageSpec. Use this from outside the core package.
pub fn[T, K] LanguageSpec::new(
  whitespace_kind : K,
  error_kind : K,
  root_kind : K,
  eof_token : T,
  incomplete_kind? : K = error_kind,
  parse_root? : (ParserContext[T, K]) -> Unit = _ => (),
  reuse_size_threshold? : Int = 64,
) -> LanguageSpec[T, K] {
  {
    whitespace_kind,
    error_kind,
    incomplete_kind,
    root_kind,
    eof_token,
    parse_root,
    reuse_size_threshold,
  }
}

///|
/// Core parser state. Grammar functions receive this and call methods on it.
/// T = token type, K = syntax-kind type.
///
/// Token storage is closure-based: callers provide indexed accessors so
/// ParserContext never needs to copy tokens into a wrapper array.
///
/// Grammar-author boundary (loom#251): the stable grammar-author surface is the
/// methods on `ParserContext`, not its fields. All fields below are `priv`
/// internal parser state — they are deliberately absent from the generated
/// interface so grammars cannot couple to the cursor/error/reuse representation.
/// If a grammar genuinely needs to read some state, add a named accessor method
/// with explicit semantics rather than re-exposing a field.
pub struct ParserContext[T, K] {
  priv spec : LanguageSpec[T, K]
  priv token_count : Int
  priv get_token : (Int) -> T
  priv get_start : (Int) -> Int
  priv get_end : (Int) -> Int
  priv source : String
  priv mut position : Int
  priv events : @seam.EventBuffer
  priv diagnostics : DiagnosticSet
  priv mut error_count : Int
  priv mut open_nodes : Int
  // Incremental reuse — None on a fresh parse, Some(cursor) for incremental.
  priv mut reuse_cursor : ReuseCursor[T, K]?
  // Diagnostics from the previous parse (optional). When present, reuse hits
  // replay matching diagnostics by code-unit span to preserve exact messages.
  priv mut reuse_diagnostics : DiagnosticSet?
  priv mut reuse_count : Int
}

///|
/// Opaque snapshot of parser state for speculative parsing.
/// Create with checkpoint(), restore with restore().
pub(all) struct Checkpoint[T, K] {
  priv position : Int
  priv events_len : Int
  priv error_count : Int
  priv open_nodes : Int
  priv reuse_cursor : ReuseCursor[T, K]?
  priv reuse_count : Int
}
