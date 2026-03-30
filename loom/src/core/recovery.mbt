// Error recovery combinators for ParserContext.
//
// These build on the existing primitives (bump_error, emit_error_placeholder,
// error, start_node/finish_node) to provide reusable patterns that grammar
// authors can call instead of hand-rolling recovery logic.
//
// All combinators produce well-formed CST subtrees: every error-recovery
// path emits nodes/tokens that the ReuseCursor, diagnostic replay, and
// incr backdating machinery already handle correctly.

// ─── expect ───────────────────────────────────────────────────────────────────

///|
/// Consume the current token if it matches `expected`, otherwise record a
/// diagnostic and emit a zero-width error placeholder.
///
/// Returns true when the token was consumed normally, false when recovery fired.
/// The grammar can branch on the return value when the missing token changes
/// subsequent parse logic (e.g. a missing `)` means "stop parsing arguments").
///
/// Error message is auto-generated from `T : Show`:
///   "expected <expected>, got <actual>"
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::expect(
  self : ParserContext[T, K],
  expected : T,
  kind : K,
) -> Bool {
  if self.at(expected) {
    self.emit_token(kind)
    true
  } else {
    let got = self.peek()
    self.error("expected " + expected.to_string() + ", got " + got.to_string())
    if self.at_eof() {
      self.emit_incomplete_placeholder()
    } else {
      self.emit_error_placeholder()
    }
    false
  }
}

// ─── skip_until ───────────────────────────────────────────────────────────────

///|
/// Skip tokens until `is_sync(token)` returns true or EOF is reached.
///
/// Skipped tokens are wrapped in a single error-kind node so they form one
/// contiguous error region in the CST rather than a sequence of individual
/// error tokens. The wrapping node is only emitted when at least one token
/// is actually skipped (no empty error nodes are produced).
///
/// Returns the number of tokens consumed. Zero means the current token was
/// already a sync point (or EOF), so no recovery was needed.
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until(
  self : ParserContext[T, K],
  is_sync : (T) -> Bool,
) -> Int {
  let mut count = 0
  let needs_wrap = !self.at_eof() && !is_sync(self.peek())
  if needs_wrap {
    self.start_node(self.spec.error_kind)
  }
  while !self.at_eof() && !is_sync(self.peek()) {
    self.bump_error()
    count = count + 1
  }
  if needs_wrap {
    self.finish_node()
  }
  count
}

///|
/// Like skip_until, but guarantees forward progress unless at EOF.
/// If already at a sync point, consumes one token as error so recovery loops
/// cannot spin at the same position.
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until_progress(
  self : ParserContext[T, K],
  is_sync : (T) -> Bool,
) -> Int {
  if self.at_eof() {
    return 0
  }
  if is_sync(self.peek()) {
    self.bump_error()
    return 1
  }
  let n = self.skip_until(is_sync)
  if n == 0 && !self.at_eof() {
    self.bump_error()
    return 1
  }
  n
}

// ─── skip_until_balanced ──────────────────────────────────────────────────────

///|
/// Skip tokens until `is_close(token)` at bracket nesting depth 0, or EOF.
///
/// Respects bracket nesting: encountering `is_open` increments depth,
/// `is_close` decrements it. Only a close at depth 0 stops the skip.
/// Skipped tokens are wrapped in a single error-kind node.
///
/// The closing token itself is NOT consumed — the caller decides whether
/// to emit it (common for `)` recovery) or leave it for the parent.
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until_balanced(
  self : ParserContext[T, K],
  is_open : (T) -> Bool,
  is_close : (T) -> Bool,
) -> Int {
  let mut depth = 0
  let mut count = 0
  let needs_wrap = !self.at_eof() && !is_close(self.peek())
  if needs_wrap {
    self.start_node(self.spec.error_kind)
  }
  while !self.at_eof() {
    let t = self.peek()
    if is_close(t) && depth == 0 {
      break
    }
    if is_open(t) {
      depth = depth + 1
    } else if is_close(t) {
      depth = depth - 1
    }
    self.bump_error()
    count = count + 1
  }
  if needs_wrap {
    self.finish_node()
  }
  count
}

// ─── node_with_recovery ───────────────────────────────────────────────────────

///|
/// Reuse-aware node combinator with automatic recovery on failure.
///
/// `body` returns true on success, false when it cannot make progress.
/// On failure, `skip_until(is_sync)` is called inside the node to consume
/// unexpected tokens before closing it.
///
/// Reuse fast-path: if an old subtree can be reused, `body` and `is_sync`
/// are never called (same semantics as `node()`).
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::node_with_recovery(
  self : ParserContext[T, K],
  kind : K,
  body : () -> Bool,
  is_sync : (T) -> Bool,
) -> Unit {
  if self.try_reuse(kind) is Some(reuse) {
    self.emit_reused(reuse)
    return
  }
  self.start_node(kind)
  let ok = body()
  if !ok {
    let _ = self.skip_until(is_sync)
  }
  self.finish_node()
}

// ─── expect_and_recover ───────────────────────────────────────────────────────

///|
/// Expect a token; on mismatch, skip unexpected tokens until a sync point
/// is found, then try the expectation once more.
///
/// This combines `expect` with `skip_until` for the common pattern where
/// the grammar expects a specific delimiter but the user inserted garbage
/// before it.
///
/// Returns true if the expected token was eventually consumed (possibly
/// after skipping), false if recovery gave up (sync point reached or EOF
/// without finding the expected token).
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::expect_and_recover(
  self : ParserContext[T, K],
  expected : T,
  kind : K,
  is_sync : (T) -> Bool,
) -> Bool {
  if self.at(expected) {
    self.emit_token(kind)
    return true
  }
  // Record diagnostic before skipping
  let got = self.peek()
  self.error("expected " + expected.to_string() + ", got " + got.to_string())
  // Skip garbage
  let _ = self.skip_until(t => t == expected || is_sync(t))
  // Try once more after recovery
  if self.at(expected) {
    self.emit_token(kind)
    true
  } else {
    if self.at_eof() {
      self.emit_incomplete_placeholder()
    } else {
      self.emit_error_placeholder()
    }
    false
  }
}
