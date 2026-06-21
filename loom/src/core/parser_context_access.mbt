// Generic parser infrastructure — ParserContext construction and token access

///|
/// Construct a ParserContext from an Array[TokenInfo[T]].
/// Convenience wrapper — internally creates indexed accessors over the array.
pub fn[T, K] ParserContext::new(
  tokens : Array[TokenInfo[T]],
  source : String,
  spec : LanguageSpec[T, K],
) -> ParserContext[T, K] {
  let starts = build_starts(tokens)
  {
    spec,
    token_count: tokens.length(),
    get_token: fn(i) { tokens[i].token },
    get_start: fn(i) { starts[i] },
    get_end: fn(i) { starts[i] + tokens[i].len },
    source,
    position: 0,
    events: @seam.EventBuffer::new(),
    diagnostics: DiagnosticSet::empty(),
    error_count: 0,
    open_nodes: 0,
    reuse_cursor: None,
    reuse_diagnostics: None,
    reuse_count: 0,
  }
}

///|
/// Construct a ParserContext from indexed accessor closures.
/// Use this to avoid allocating a wrapper Array[TokenInfo[T]] when the
/// caller already has tokens in a different layout (e.g. @token.TokenInfo).
pub fn[T, K] ParserContext::new_indexed(
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
  source : String,
  spec : LanguageSpec[T, K],
) -> ParserContext[T, K] {
  {
    spec,
    token_count,
    get_token,
    get_start,
    get_end,
    source,
    position: 0,
    events: @seam.EventBuffer::new(),
    diagnostics: DiagnosticSet::empty(),
    error_count: 0,
    open_nodes: 0,
    reuse_cursor: None,
    reuse_diagnostics: None,
    reuse_count: 0,
  }
}

///|
/// Return the next non-trivia token without consuming it.
pub fn[T : @seam.IsTrivia, K] ParserContext::peek(
  self : ParserContext[T, K],
) -> T {
  self.peek_nth(0)
}

///|
/// Return the nth non-trivia token (0-indexed) without consuming it.
/// peek_nth(0) is equivalent to peek().
/// Returns eof_token when fewer than n + 1 non-trivia tokens remain.
pub fn[T : @seam.IsTrivia, K] ParserContext::peek_nth(
  self : ParserContext[T, K],
  n : Int,
) -> T {
  if n < 0 {
    return self.peek()
  }
  let mut count = 0
  for pos in self.position..<self.token_count {
    let t = (self.get_token)(pos)
    if !t.is_trivia() {
      if count == n {
        return t
      }
      count = count + 1
    }
  }
  self.spec.eof_token
}

///|
/// Return the first non-trivia token for which `skip` returns false, scanning
/// forward from the current position. Returns the EOF token when all remaining
/// non-trivia tokens match `skip` or no tokens remain. Termination is guaranteed
/// regardless of what `skip` returns for the EOF token — the scan stops at the
/// end of the token buffer without calling `skip` a second time on the same
/// position.
pub fn[T : @seam.IsTrivia, K] ParserContext::peek_while_skip(
  self : ParserContext[T, K],
  skip : (T) -> Bool,
) -> T {
  for pos in self.position..<self.token_count {
    let t = (self.get_token)(pos)
    if t.is_trivia() {
      continue
    }
    if skip(t) {
      continue
    }
    return t
  }
  self.spec.eof_token
}

///|
/// Return the TokenInfo for the next non-trivia token.
pub fn[T : @seam.IsTrivia, K] ParserContext::peek_info(
  self : ParserContext[T, K],
) -> TokenInfo[T] {
  self
  .current_token_position()
  .map_or({ token: self.spec.eof_token, len: 0 }, pos => {
    token: (self.get_token)(pos),
    len: (self.get_end)(pos) - (self.get_start)(pos),
  })
}

///|
/// Return true if the current non-trivia token equals the given token.
pub fn[T : Eq + @seam.IsTrivia, K] ParserContext::at(
  self : ParserContext[T, K],
  token : T,
) -> Bool {
  self.peek() == token
}

///|
/// Return true if the next token equals `expected` AND is contiguous with
/// everything consumed so far — no trivia may separate it from the
/// previously consumed token.
///
/// This is the whitespace-sensitive counterpart of `at`: `at` skips trivia
/// (so `song (` and `song(` look identical), while `at_adjacent` lets a
/// grammar accept `song(` but reject `song (` without hand-rolled offset
/// arithmetic over `current_token_range`. At start of input the first token
/// counts as adjacent only when it starts at offset 0.
///
/// Adjacency requires both checks below: the raw-index check catches
/// interposed zero-width tokens (which offset comparison misses), and the
/// offset check catches unrepresented source gaps — token streams from
/// `LexResult::from_located_tokens` without a `gap_token` skip blank gaps
/// instead of materializing trivia, so consecutive indices alone do not
/// prove contiguity. Trivia already consumed (e.g. via `flush_trivia`)
/// still counts as separation — even zero-width trivia, which offsets
/// cannot see — so the token immediately before the cursor must itself be
/// non-trivia.
pub fn[T : Eq + @seam.IsTrivia, K] ParserContext::at_adjacent(
  self : ParserContext[T, K],
  expected : T,
) -> Bool {
  guard self.position < self.token_count else { return false }
  let next = (self.get_token)(self.position)
  guard !next.is_trivia() && next == expected else { return false }
  // Trivia consumed via flush_trivia still separates — including
  // zero-width trivia, which offsets cannot see — so the token
  // immediately before the cursor must itself be non-trivia. Its end is
  // the frontier (0 before the first token); the next token must start
  // exactly there.
  guard self.position == 0 || !(self.get_token)(self.position - 1).is_trivia() else {
    return false
  }
  let frontier = if self.position == 0 {
    0
  } else {
    (self.get_end)(self.position - 1)
  }
  (self.get_start)(self.position) == frontier
}

///|
/// Return true if at end of input (ignoring trivia).
pub fn[T : @seam.IsTrivia + @seam.IsEof, K] ParserContext::at_eof(
  self : ParserContext[T, K],
) -> Bool {
  self.peek().is_eof()
}

///|
/// Return true once parser diagnostics have reached `max`.
///
/// Intended for bounded recovery loops: `while !ctx.too_many_errors(max) { ... }`.
/// Prefer it over reading `ParserContext.error_count` directly from grammar code.
pub fn[T, K] ParserContext::too_many_errors(
  self : ParserContext[T, K],
  max : Int,
) -> Bool {
  self.error_count >= max
}

///|
/// Return the raw token index of the next non-trivia token.
fn[T : @seam.IsTrivia, K] ParserContext::current_token_position(
  self : ParserContext[T, K],
) -> Int? {
  for pos in self.position..<self.token_count {
    let token = (self.get_token)(pos)
    if !token.is_trivia() {
      return Some(pos)
    }
  }
  None
}

///|
/// Extract source text for the current non-trivia token as a zero-copy view.
///
/// Returns an empty view at EOF or when the current token span is invalid.
pub fn[T : @seam.IsTrivia, K] ParserContext::current_token_text(
  self : ParserContext[T, K],
) -> StringView {
  self
  .current_token_position()
  .map_or(StringView::default(), pos => self.token_text_at(pos))
}

///|
/// Return the source range for the current non-trivia token.
///
/// At EOF, or if the current token span is invalid, this returns a zero-width
/// range at the end of the source.
pub fn[T : @seam.IsTrivia, K] ParserContext::current_token_range(
  self : ParserContext[T, K],
) -> Range {
  self
  .current_token_position()
  .map_or_else(() => Range::new(self.source.length(), self.source.length()), pos => {
    let start = (self.get_start)(pos)
    let end = (self.get_end)(pos)
    if start < 0 || end < start || end > self.source.length() {
      Range::new(self.source.length(), self.source.length())
    } else {
      Range::new(start, end)
    }
  })
}

///|
/// Extract the source text of the token at `pos` as a zero-copy StringView.
///
/// Returns a view into `self.source`. No String allocation.
/// StringView slicing does not validate UTF-16, preserving raw code units
/// for CRDT sync fidelity. Surrogate handling is deferred to point-of-use.
pub fn[T, K] ParserContext::token_text_at(
  self : ParserContext[T, K],
  pos : Int,
) -> StringView {
  if pos < 0 || pos >= self.token_count {
    return ""
  }
  let start = (self.get_start)(pos)
  let end = (self.get_end)(pos)
  if start < 0 || end < start || end > self.source.length() {
    return ""
  }
  self.source.view(start_offset=start, end_offset=end)
}

///|
/// Extract source text at a token index. Internal alias for token_text_at.
fn[T, K] ParserContext::text_at(
  self : ParserContext[T, K],
  pos : Int,
) -> StringView {
  self.token_text_at(pos)
}
