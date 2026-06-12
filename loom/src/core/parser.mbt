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

///|
/// Emit all consecutive trivia tokens at current position to the event stream,
/// advancing position past each one. Call this before emitting syntactic tokens,
/// and at the end of the top-level grammar function before returning.
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] ParserContext::flush_trivia(
  self : ParserContext[T, K],
) -> Unit {
  while self.position < self.token_count {
    let token = (self.get_token)(self.position)
    if token.is_trivia() {
      let text = self.text_at(self.position)
      self.events.push(
        @seam.ParseEvent::Token(self.spec.whitespace_kind.to_raw(), text),
      )
      self.position = self.position + 1
    } else {
      break
    }
  }
}

///|
/// Consume the current token and emit it as a leaf in the CST.
/// Automatically flushes leading trivia before the token.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_token(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.flush_trivia()
  match self.current_token_position() {
    Some(pos) if !(self.get_token)(pos).is_eof() => {
      let text = self.text_at(pos)
      self.events.push(@seam.ParseEvent::Token(kind.to_raw(), text))
      self.position = pos + 1
    }
    _ => {
      self.error("emit_token: unexpected EOF")
      self.events.push_parser_synthetic_zero_width_token(kind.to_raw())
    }
  }
}

///|
/// Consume the current token and emit it using the token's own raw kind.
///
/// Use this only for grammars where the token raw kind is also the CST leaf
/// kind. Grammars with a distinct syntax-kind layer should keep mapping
/// `ctx.peek()` to a `K` and call `emit_token(kind)` instead.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_current_token(
  self : ParserContext[T, K],
) -> Unit {
  self.flush_trivia()
  match self.current_token_position() {
    Some(pos) if !(self.get_token)(pos).is_eof() => {
      let token = (self.get_token)(pos)
      let text = self.text_at(pos)
      self.events.push(@seam.ParseEvent::Token(token.to_raw(), text))
      self.position = pos + 1
    }
    _ => {
      self.error("emit_current_token: unexpected EOF")
      self.emit_incomplete_placeholder()
    }
  }
}

///|
/// Open a new node. Must be followed by finish_node().
pub fn[T, K : @seam.ToRawKind] ParserContext::start_node(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.open_nodes = self.open_nodes + 1
  self.events.push(@seam.StartNode(kind.to_raw()))
}

///|
/// Close the most recently opened node.
pub fn[T, K] ParserContext::finish_node(self : ParserContext[T, K]) -> Unit {
  if self.open_nodes <= 0 {
    return
  }
  self.open_nodes = self.open_nodes - 1
  self.events.push(@seam.FinishNode)
}

///|
/// Reserve a placeholder that can later be claimed by start_at.
/// Used for retroactive wrapping (e.g. binary expressions, applications).
pub fn[T, K] ParserContext::mark(self : ParserContext[T, K]) -> Int {
  self.events.mark()
}

///|
/// Save the current parse state for speculative parsing.
pub fn[T, K] ParserContext::checkpoint(
  self : ParserContext[T, K],
) -> Checkpoint[T, K] {
  let reuse_cursor = self.reuse_cursor.map(cursor => cursor.snapshot())
  {
    position: self.position,
    events_len: self.events.length(),
    error_count: self.error_count,
    open_nodes: self.open_nodes,
    reuse_cursor,
    reuse_count: self.reuse_count,
  }
}

///|
/// Restore parser state saved by checkpoint().
pub fn[T, K] ParserContext::restore(
  self : ParserContext[T, K],
  cp : Checkpoint[T, K],
) -> Unit {
  self.position = cp.position
  self.events.truncate(cp.events_len)
  self.diagnostics.truncate(cp.error_count)
  self.error_count = cp.error_count
  self.open_nodes = cp.open_nodes
  self.reuse_cursor = cp.reuse_cursor.map(cursor => cursor.snapshot())
  self.reuse_count = cp.reuse_count
}

///|
/// Retroactively open a node at a previously marked position.
pub fn[T, K : @seam.ToRawKind] ParserContext::start_at(
  self : ParserContext[T, K],
  mark : Int,
  kind : K,
) -> Unit {
  self.events.start_at(mark, kind.to_raw())
  self.open_nodes = self.open_nodes + 1
}

///|
/// Build a parser diagnostic for a known token span. The token payload is
/// erased immediately so consumers never need to re-tokenize for evidence.
fn[T : @seam.ToRawKind] make_parser_diagnostic(
  msg : String,
  start : Int,
  end : Int,
  token : T,
  code? : DiagnosticCode? = None,
) -> Diagnostic {
  let (primary, notes) : (TextRange?, Array[String]) = try
    TextRange::from_offsets(start, end)
  catch {
    error =>
      (
        None,
        ["invalid diagnostic range preserved as " + @debug.to_string(error)],
      )
  } noraise {
    range => (Some(range), [])
  }
  let evidence = primary.map(range => { kind: token.to_raw(), range })
  Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    code~,
    message=msg,
    primary~,
    notes~,
    token=evidence,
  )
}

///|
/// Report an already-structured diagnostic through parser diagnostic
/// collection. Equivalent parser diagnostics refresh token evidence instead of
/// creating duplicates.
pub fn[T, K] ParserContext::report(
  self : ParserContext[T, K],
  diagnostic : Diagnostic,
) -> Unit {
  let _ = self.push_diagnostic_unique(diagnostic)
}

///|
/// Report a parser error with an explicit optional range.
pub fn[T, K] ParserContext::report_error(
  self : ParserContext[T, K],
  message~ : String,
  code? : DiagnosticCode? = None,
  range? : TextRange? = None,
) -> Unit {
  self.report(
    Diagnostic(
      source=DiagnosticSource::parser(),
      severity=Error,
      code~,
      message~,
      primary=range,
    ),
  )
}

///|
/// Report a parser error at the current non-trivia token, or at EOF when no
/// token remains. The token type is erased through `ToRawKind`.
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::report_at_current(
  self : ParserContext[T, K],
  message~ : String,
  code? : DiagnosticCode? = None,
) -> Unit {
  let diagnostic = self
    .current_token_position()
    .map_or_else(
      () => {
        let eof = self.source.length()
        make_parser_diagnostic(message, eof, eof, self.spec.eof_token, code~)
      },
      pos => {
        make_parser_diagnostic(
          message,
          (self.get_start)(pos),
          (self.get_end)(pos),
          (self.get_token)(pos),
          code~,
        )
      },
    )
  let _ = self.push_diagnostic_unique(diagnostic)
}

///|
/// Report a simple "expected ..." parser diagnostic at the current token.
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::report_expected(
  self : ParserContext[T, K],
  expected~ : String,
  code? : DiagnosticCode? = None,
) -> Unit {
  self.report_at_current(message="expected " + expected, code~)
}

///|
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::error(
  self : ParserContext[T, K],
  msg : String,
) -> Unit {
  self.report_at_current(message=msg)
}

///|
/// Consume the current token and emit it as an error token (for error recovery).
/// Automatically flushes leading trivia before the token.
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] ParserContext::bump_error(
  self : ParserContext[T, K],
) -> Unit {
  self.flush_trivia()
  let text = self.text_at(self.position)
  self.events.push(@seam.ParseEvent::Token(self.spec.error_kind.to_raw(), text))
  self.position = self.position + 1
}

///|
/// Emit a zero-width token (no source text consumed, position unchanged).
/// Use this for synthetic tokens inserted during error recovery when the
/// grammar needs to represent a missing token without consuming input.
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_zero_width(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.events.push_parser_synthetic_zero_width_token(kind.to_raw())
}

///|
/// Emit a zero-width error placeholder (no source text consumed).
/// Shorthand for emit_zero_width(spec.error_kind). Use this in grammar code
/// to represent a missing or erroneous token without consuming input.
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_error_placeholder(
  self : ParserContext[T, K],
) -> Unit {
  self.emit_zero_width(self.spec.error_kind)
}

///|
/// Emit a zero-width incomplete placeholder (no source text consumed).
/// Use this when the grammar expects more input but has reached EOF.
/// Distinct from emit_error_placeholder: signals "incomplete input" rather
/// than "unexpected token", enabling IDE consumers to show different UX
/// (e.g. grey indicator vs red squiggly).
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_incomplete_placeholder(
  self : ParserContext[T, K],
) -> Unit {
  self.emit_zero_width(self.spec.incomplete_kind)
}

// ─── Incremental reuse ────────────────────────────────────────────────────────

///|
/// Attach a reuse cursor to an existing ParserContext, enabling incremental parsing.
/// Called by entry points (parse_cst_with_cursor etc.) after construction.
pub fn[T, K] ParserContext::set_reuse_cursor(
  self : ParserContext[T, K],
  cursor : ReuseCursor[T, K],
) -> Unit {
  self.reuse_cursor = Some(cursor)
}

///|
/// Attach diagnostics from the previous parse. On reuse hits, diagnostics whose
/// spans fall within the reused node are replayed into self.diagnostics.
pub fn[T, K] ParserContext::set_reuse_diagnostics(
  self : ParserContext[T, K],
  diagnostics : DiagnosticSet,
) -> Unit {
  self.reuse_diagnostics = Some(diagnostics)
}

///|
/// Try to reuse an old CST node of `kind` at the current parse position.
///
/// byte_offset uses self.position directly (including any leading trivia) because
/// seek_node_at matches nodes by their absolute start, and nodes store trivia as
/// their first children — so the node's start offset is the trivia's start offset.
///
/// token_pos must skip past trivia first. leading_token_matches compares the
/// node's first *non-trivia* token against the token at token_pos in the new
/// stream. Passing a trivia index causes systematic false-negative reuse for
/// all whitespace-separated constructs (the common case).
///
/// Returns None immediately if no cursor is attached (non-incremental parse).
fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::try_reuse(
  self : ParserContext[T, K],
  kind : K,
) -> @seam.CstNode? {
  if self.position >= self.token_count {
    return None
  }
  let byte_offset = (self.get_start)(self.position)
  // Skip trivia to find the logical token position for leading-token matching.
  let token_pos = self.current_token_position().unwrap_or(self.token_count)
  match self.reuse_cursor {
    None => None
    Some(cursor) =>
      match cursor.try_reuse(kind.to_raw(), byte_offset, token_pos) {
        None => None
        Some(node) => {
          let old_node_end = cursor.current_offset + node.text_len
          let new_node_end = byte_offset + node.text_len
          let old_boundary_tokens = cursor.old_zero_width_tokens_at_boundary(
            new_node_end,
          )
          if self.reused_boundary_zero_width_tokens_match(
              node, old_node_end, new_node_end, old_boundary_tokens,
            ) {
            Some(node)
          } else {
            None
          }
        }
      }
  }
}

///|
/// True when a CST leaf is a source-backed zero-width lexer token
/// structurally owned by a reused node's right boundary.
///
/// This is the single boundary-ownership predicate for reused zero-width CST
/// leaves. It intentionally combines token provenance with accumulated child
/// offsets from the right-edge walk: parser-synthetic placeholders also have
/// empty text, but `is_source_backed() == false`, so they must not advance the
/// lexer stream. Stored `CstToken::start_offset()` / `end_offset()` backing
/// spans are intentionally ignored because interned source-backed empty tokens
/// may carry canonical spans that differ from this tree position.
fn is_source_backed_zero_width_token_owned_by_reused_boundary(
  token : @seam.CstToken,
  child_start : Int,
  child_end : Int,
  boundary : Int,
) -> Bool {
  token.is_source_backed() &&
  token.text_len() == 0 &&
  child_start == boundary &&
  child_end == boundary
}

///|
/// Push source-backed zero-width leaves that sit at the reused node's right
/// boundary, in reverse source order. Parser-owned placeholders use synthetic
/// empty text and must not advance the lexer stream; source-backed leaves
/// represent real lexer tokens whose structural child offsets equal the node
/// end. Stored token spans are intentionally ignored because interned tokens
/// carry canonical backing spans that may not equal their tree position.
///
/// This walks only the right edge plus trailing zero-width siblings so reuse
/// remains proportional to boundary ambiguity, not reused subtree size.
fn push_reused_boundary_zero_width_tokens_reversed(
  node : @seam.CstNode,
  boundary : Int,
  out : Array[@seam.CstToken],
) -> Unit {
  let mut child_end = boundary
  let mut i = node.children.length() - 1
  while i >= 0 {
    let child = node.children[i]
    let child_len = child.text_len()
    let child_start = child_end - child_len
    match child {
      @seam.CstElement::Token(token) => {
        if child_len != 0 {
          break
        }
        if is_source_backed_zero_width_token_owned_by_reused_boundary(
            token, child_start, child_end, boundary,
          ) {
          out.push(token)
        }
      }
      @seam.CstElement::Node(child_node) => {
        push_reused_boundary_zero_width_tokens_reversed(
          child_node, child_end, out,
        )
        if child_len != 0 {
          break
        }
      }
    }
    child_end = child_start
    i = i - 1
  }
}

///|
fn[T : @seam.IsEof, K] ParserContext::has_unmatched_zero_width_boundary_token(
  self : ParserContext[T, K],
  position : Int,
  boundary : Int,
) -> Bool {
  position < self.token_count &&
  (self.get_start)(position) == boundary &&
  (self.get_end)(position) == boundary &&
  !(self.get_token)(position).is_eof()
}

///|
fn[T : @seam.IsEof + @seam.ToRawKind, K] ParserContext::reused_boundary_zero_width_tokens_match(
  self : ParserContext[T, K],
  node : @seam.CstNode,
  old_node_end : Int,
  new_node_end : Int,
  old_boundary_tokens : Array[OldToken],
) -> Bool {
  let owned_boundary_tokens : Array[@seam.CstToken] = []
  push_reused_boundary_zero_width_tokens_reversed(
    node, old_node_end, owned_boundary_tokens,
  )
  if owned_boundary_tokens.length() > old_boundary_tokens.length() {
    return false
  }
  for i in 0..<owned_boundary_tokens.length() {
    let owned = owned_boundary_tokens[owned_boundary_tokens.length() - i - 1]
    let old = old_boundary_tokens[i]
    if owned.kind != old.kind || owned.text() != old.text {
      return false
    }
  }
  let mut position = self.position
  while position < self.token_count && (self.get_start)(position) < new_node_end {
    position = position + 1
  }
  for old in old_boundary_tokens {
    if position >= self.token_count ||
      (self.get_start)(position) != new_node_end ||
      (self.get_end)(position) != new_node_end ||
      (self.get_token)(position).to_raw() != old.kind ||
      self.token_text_at(position) != old.text {
      return false
    }
    position = position + 1
  }
  if self.has_unmatched_zero_width_boundary_token(position, new_node_end) {
    return false
  }
  true
}

///|
/// Advance position past all tokens (trivia + non-trivia) covered by node.
/// Offset-based advancing avoids over-consuming when reused subtrees contain
/// parser-owned zero-width leaves (e.g. error placeholders). Source-backed
/// zero-width lexer leaves at the reused node's right boundary are then matched
/// explicitly so they are not left behind.
fn[T : @seam.ToRawKind, K] ParserContext::advance_past_reused(
  self : ParserContext[T, K],
  node : @seam.CstNode,
  old_node_end : Int,
) -> Unit {
  if self.position >= self.token_count {
    return
  }
  let node_start = (self.get_start)(self.position)
  let node_end = node_start + node.text_len
  while self.position < self.token_count &&
        (self.get_start)(self.position) < node_end {
    self.position = self.position + 1
  }
  let boundary_tokens : Array[@seam.CstToken] = []
  push_reused_boundary_zero_width_tokens_reversed(
    node, old_node_end, boundary_tokens,
  )
  let mut i = boundary_tokens.length() - 1
  while i >= 0 {
    let token = boundary_tokens[i]
    if self.position >= self.token_count ||
      (self.get_start)(self.position) != node_end ||
      (self.get_end)(self.position) != node_end {
      break
    }
    if (self.get_token)(self.position).to_raw() == token.kind &&
      self.text_at(self.position) == token.text() {
      self.position = self.position + 1
    } else {
      break
    }
    i = i - 1
  }
}

///|
/// Collect error and incomplete spans from a CST subtree.
/// Returns the number of spans added into `out`.
fn[T, K : @seam.ToRawKind] collect_reused_error_spans(
  node : @seam.CstNode,
  node_start : Int,
  spec : LanguageSpec[T, K],
  out : Array[ReusedErrorSpan],
) -> Int {
  let error_raw = spec.error_kind.to_raw()
  let incomplete_raw = spec.incomplete_kind.to_raw()
  let mut offset = node_start
  let mut added = 0
  for child in node.children {
    match child {
      @seam.CstElement::Token(t) => {
        let end = offset + t.text_len()
        if t.kind == error_raw || t.kind == incomplete_raw {
          out.push({ start: offset, end })
          added = added + 1
        }
        offset = end
      }
      @seam.CstElement::Node(n) => {
        let child_added = collect_reused_error_spans(n, offset, spec, out)
        if child_added == 0 && (n.kind == error_raw || n.kind == incomplete_raw) {
          out.push({ start: offset, end: offset + n.text_len })
          added = added + 1
        } else {
          added = added + child_added
        }
        offset = offset + n.text_len
      }
    }
  }
  added
}

///|
/// Return the first token that starts at or after byte_offset, or overlaps it
/// (end > byte_offset). Overlap handling covers zero-width tokens and error
/// spans that fall mid-token. Scans forward from from_pos.
fn[T, K] ParserContext::token_info_at_or_after(
  self : ParserContext[T, K],
  from_pos : Int,
  byte_offset : Int,
) -> TokenInfo[T] {
  for pos in from_pos..<self.token_count {
    let start = (self.get_start)(pos)
    let end = (self.get_end)(pos)
    if start >= byte_offset || end > byte_offset {
      return { token: (self.get_token)(pos), len: end - start }
    }
  }
  { token: self.spec.eof_token, len: 0 }
}

///|
/// Add a diagnostic unless an equivalent parser error already exists.
/// Equivalence uses the stable logical key and refreshes volatile evidence.
/// Returns true if newly added, false if an existing diagnostic was updated.
fn[T, K] ParserContext::push_diagnostic_unique(
  self : ParserContext[T, K],
  diag : Diagnostic,
) -> Bool {
  if self.diagnostics.push_parser_unique(diag) {
    self.error_count = self.error_count + 1
    true
  } else {
    false
  }
}

///|
/// Replay previous diagnostics that fall fully within [node_start, node_end).
///
/// allow_eof_boundary: pass true when the reused node has no error-bearing
/// next sibling — meaning a zero-width diagnostic at node_end that is also
/// at EOF was emitted by this node's grammar (ctx.error without placeholder).
/// Pass false when the next sibling has error content, meaning the boundary
/// diagnostic belongs to that sibling, not this node.
fn[T, K] ParserContext::replay_reused_diagnostics(
  self : ParserContext[T, K],
  node_start : Int,
  node_end : Int,
  owns_right_boundary_zero_width_error : Bool,
  allow_eof_boundary : Bool,
) -> Bool {
  let mut replayed_any = false
  match self.reuse_diagnostics {
    None => ()
    Some(prev) =>
      for d in prev.items() {
        // Half-open containment: [node_start, node_end), with one exception:
        // keep zero-width diagnostics at node_end only when this reused node
        // itself owns a zero-width error at that boundary (structural check),
        // OR when the node ends at EOF and no error-bearing sibling follows
        // (handles ctx.error at EOF without emit_error_placeholder).
        match d.primary {
          Some(range) => {
            let start = range.start().value()
            let end = range.end().value()
            let keep_right_boundary = start == node_end &&
              end == node_end &&
              (
                owns_right_boundary_zero_width_error ||
                (allow_eof_boundary && node_end >= self.source.length())
              )
            if start >= node_start &&
              end <= node_end &&
              (start < node_end || keep_right_boundary) {
              if self.push_diagnostic_unique(d) {
                replayed_any = true
              }
            }
          }
          None => ()
        }
      }
  }
  replayed_any
}

///|
/// If previous diagnostics are unavailable, synthesize diagnostics from
/// pre-collected error spans in the reused subtree.
fn[T : @seam.ToRawKind, K] ParserContext::synthesize_reused_diagnostics(
  self : ParserContext[T, K],
  spans : Array[ReusedErrorSpan],
) -> Unit {
  for span in spans {
    let info = self.token_info_at_or_after(self.position, span.start)
    let _ = self.push_diagnostic_unique(
      make_parser_diagnostic(
        "reused syntax error",
        span.start,
        span.end,
        info.token,
      ),
    )
  }
}

///|
/// Emit a reused node, replay its diagnostics, and advance both positions
/// past it. Order matters:
///   1. reuse event        — rebuild reused tokens against the current source
///   2. replay/synthesize  — restore diagnostics while self.position still
///                           points at node start (token_info_at_or_after needs it)
///   3. advance_past_reused — advance self.position through the new token stream
///   4. cursor.advance_past — advance cursor.current_offset through the old tree
///
/// Two separate advance calls because there are two independent positions:
///   advance_past_reused — walks self.position through the *new* token stream
///   cursor.advance_past  — walks cursor.current_offset through the *old* tree
/// Both must stay in sync; without cursor.advance_past, subsequent seeks would
/// detect false backward movement and reset the cursor to the root.
///
/// The None arm is unreachable in practice: emit_reused is only called when
/// try_reuse returns Some, which requires reuse_cursor to be Some. It is
/// handled defensively to keep the match exhaustive.
fn[T : @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_reused(
  self : ParserContext[T, K],
  node : @seam.CstNode,
) -> Unit {
  let node_start = if self.position < self.token_count {
    (self.get_start)(self.position)
  } else {
    self.source.length()
  }
  let old_node_start = match self.reuse_cursor {
    Some(cursor) => cursor.current_offset
    None => node_start
  }
  let node_end = node_start + node.text_len
  self.events.push_parser_reuse_node_rebased_unchecked(
    node,
    self.source,
    node_start,
  )
  let allow_eof_boundary = match self.reuse_cursor {
    None => true
    Some(cursor) => !cursor.next_sibling_has_error()
  }
  if node.has_any_error {
    // Slow path: node has errors — collect spans and replay/synthesize diagnostics.
    let error_spans : Array[ReusedErrorSpan] = []
    let _ = collect_reused_error_spans(node, node_start, self.spec, error_spans)
    let owns_right_boundary = error_spans
      .iter()
      .any(s => s.start == node_end && s.end == node_end)
    if !self.replay_reused_diagnostics(
        node_start, node_end, owns_right_boundary, allow_eof_boundary,
      ) {
      self.synthesize_reused_diagnostics(error_spans)
    }
  } else {
    // Fast path: healthy node — skip error span collection entirely.
    // Still replay diagnostics (e.g. zero-width ctx.error at EOF).
    let _ = self.replay_reused_diagnostics(
      node_start, node_end, false, allow_eof_boundary,
    )
  }
  self.advance_past_reused(node, old_node_start + node.text_len)
  match self.reuse_cursor {
    Some(cursor) => cursor.advance_past(node)
    None => () // unreachable — no cursor means try_reuse always returns None
  }
  self.reuse_count = self.reuse_count + 1
}

///|
/// Reuse-aware node combinator. The core grammar API.
/// On reuse hit: emits the old node and skips body entirely — O(1) per node.
/// On miss: start_node → body() → finish_node — standard parse path.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::node(
  self : ParserContext[T, K],
  kind : K,
  body : () -> Unit,
) -> Unit {
  if self.try_reuse(kind) is Some(reuse) {
    // Fast path — reuse hit:
    // Replays the old subtree's events and advances position past it.
    // `body` is never called: the closure is allocated but not invoked.
    // reuse_count increments; no start_node/finish_node are pushed.
    self.emit_reused(reuse)
  } else {
    // Slow path — cache miss:
    // Runs the grammar body and wraps its output in a new node.
    // Every token consumed inside body() advances position normally.
    // Errors recorded inside body() accumulate in self.diagnostics as usual.
    self.start_node(kind)
    body()
    self.finish_node()
  }
}

///|
/// Parse a separator-delimited list. By default each parsed element is wrapped
/// in an `element_kind` node so the CST records element boundaries. Returns the
/// number of element slots emitted.
///
/// `parse_element` returns `true` iff it consumed or emitted an element body;
/// `false` means "no element starts here" and must not consume tokens. Error
/// recovery *inside* a malformed element is `parse_element`'s responsibility.
///
/// `element_start` is optional non-consuming lookahead for missing-separator
/// recovery. When a slot was parsed/reused, no literal separator follows, and
/// `element_start()` is true, the combinator emits a zero-width error
/// placeholder for the missing separator, reports "expected separator", and
/// continues with the next slot. The default `false` preserves the original
/// separator-only stopping behavior.
///
/// Boundary contract — an empty element slot exists iff it is adjacent to a
/// separator: leading, doubled, and trailing separators each produce an
/// `element_kind` node containing a zero-width error placeholder plus an
/// "expected element" diagnostic. Empty input emits nothing and returns 0.
/// In `wrap_element=false` mode, parsed element events are left as emitted by
/// `parse_element`, combinator-level element reuse is disabled, and empty slots
/// emit the zero-width error placeholder directly (no wrapper node).
///
/// Elements are wrapped retroactively (`mark`/`start_at`), never rolled back:
/// the combinator does not use `checkpoint`/`restore`, so caller-owned
/// recovery and delimiter handling are unaffected. The combinator owns no
/// open/close delimiters. In wrapped mode, each element slot first tries
/// incremental subtree reuse of `element_kind`.
///
/// Terminates defensively if `parse_element` reports success without
/// consuming tokens (contract violation): the slot is discarded and the list
/// ends.
pub fn[
  T : Eq + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] ParserContext::separated_list(
  self : ParserContext[T, K],
  element_kind : K,
  separator : T,
  parse_element : () -> Bool,
  element_start? : () -> Bool = () => false,
  wrap_element? : Bool = true,
) -> Int {
  // State machine over element slots: `count` and `after_separator` are the
  // loop state. `slot_progressed` is intentionally imperative loop state: it
  // gates zero-width missing-separator recovery so inconsistent lookahead
  // predicates cannot spin forever at the same token.
  let mut count = 0
  let mut after_separator = false
  while true {
    let mut slot_progressed = false
    if self.at(separator) {
      // Empty slot adjacent to the upcoming separator (leading or doubled).
      self.emit_empty_element(element_kind, wrap_element)
      count = count + 1
    } else if wrap_element && self.try_reuse(element_kind) is Some(reuse) {
      // Reuse fast path — same as node(): replay the old subtree, skip the body.
      let before = self.position
      self.emit_reused(reuse)
      slot_progressed = self.position > before
      count = count + 1
    } else {
      let before = self.position
      let mark = if wrap_element { Some(self.mark()) } else { None }
      if parse_element() {
        guard self.position > before else { break } // defensive: no progress
        match mark {
          Some(mark) => {
            self.start_at(mark, element_kind)
            self.finish_node()
          }
          None => ()
        }
        slot_progressed = true
        count = count + 1
      } else if after_separator {
        // Separator-adjacent absence: trailing separator.
        self.emit_empty_element(element_kind, wrap_element)
        count = count + 1
      } else {
        // No list here at all: in wrapped mode, the unclaimed mark stays a
        // tombstone, so nothing reaches the tree.
        break
      }
    }
    if self.at(separator) {
      self.emit_current_token()
      after_separator = true
    } else if slot_progressed && element_start() {
      self.report_expected(expected="separator")
      self.emit_error_placeholder()
      after_separator = true
    } else {
      break
    }
  }
  count
}

///|
/// Emit an empty separated-list slot with an "expected element" diagnostic at
/// the current token. Wrapped mode stores the placeholder inside
/// `element_kind`; wrapper-free mode emits the placeholder directly so existing
/// grammars can keep parser-owned element nodes as direct children.
fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_empty_element(
  self : ParserContext[T, K],
  element_kind : K,
  wrap_element : Bool,
) -> Unit {
  if wrap_element {
    self.start_node(element_kind)
  }
  self.report_expected(expected="element")
  self.emit_error_placeholder()
  if wrap_element {
    self.finish_node()
  }
}

///|
/// Try to reuse an entire RepeatGroup subtree at the current position.
///
/// Grammar code calls this before each iteration of a repeat loop (e.g.
/// `while peek() == Let`) to skip entire balanced groups of siblings.
/// Returns true if a RepeatGroup was reused (position advanced past it).
///
/// When true is returned, the grammar should re-check its loop condition —
/// the next token will be whatever follows the group. No start_node or
/// finish_node events are pushed; the reuse event carries the pre-built
/// balanced tree shape and rebases token spans during tree build.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::try_reuse_repeat_group(
  self : ParserContext[T, K],
) -> Bool {
  if self.position >= self.token_count {
    return false
  }
  let byte_offset = (self.get_start)(self.position)
  let token_pos = self.current_token_position().unwrap_or(self.token_count)
  match self.reuse_cursor {
    None => false
    Some(cursor) =>
      match cursor.try_reuse_repeat_group(byte_offset, token_pos) {
        None => false
        Some(node) => {
          let old_node_end = cursor.current_offset + node.text_len
          let new_node_end = byte_offset + node.text_len
          let old_boundary_tokens = cursor.old_zero_width_tokens_at_boundary(
            new_node_end,
          )
          if self.reused_boundary_zero_width_tokens_match(
              node, old_node_end, new_node_end, old_boundary_tokens,
            ) {
            self.emit_reused(node)
            true
          } else {
            false
          }
        }
      }
  }
}

///|
/// Retroactive node wrapper for expressions built via mark()/start_at().
/// Reuse is not attempted here — the prefix is already emitted.
/// Inner node() calls within body() still benefit from reuse.
pub fn[T, K : @seam.ToRawKind] ParserContext::wrap_at(
  self : ParserContext[T, K],
  mark : Int,
  kind : K,
  body : () -> Unit,
) -> Unit {
  self.start_at(mark, kind)
  body()
  self.finish_node()
}

// ─── parse_with ───────────────────────────────────────────────────────────────

///|
/// Parse a source string using the given language spec and grammar function.
/// Returns the immutable CST and any parse diagnostics.
///
/// tokenize — converts source to a flat token array (including trivia tokens)
/// grammar  — the entry-point parse function; calls ctx methods to build the tree
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] parse_with(
  source : String,
  spec : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, DiagnosticSet) {
  let tokens = tokenize(source)
  let ctx = ParserContext::new(tokens, source, spec)
  grammar(ctx)
  ctx.flush_trivia()
  while ctx.open_nodes > 0 {
    ctx.error("unclosed node (auto-closed)")
    ctx.open_nodes = ctx.open_nodes - 1
    ctx.events.push(@seam.FinishNode)
  }
  let tree = ctx.events.build_tree(
    spec.root_kind.to_raw(),
    trivia_kind=Some(spec.whitespace_kind.to_raw()),
    error_kind=Some(spec.error_kind.to_raw()),
    incomplete_kind=Some(spec.incomplete_kind.to_raw()),
  ) catch {
    e => {
      ctx.error("internal: malformed event stream: " + @debug.to_string(e))
      make_error_tree(spec)
    }
  }
  (tree, ctx.diagnostics)
}

///|
/// Construct a minimal error CST: root_kind( error_kind() ).
/// Preserves root kind and sets has_any_error via the error child.
fn[T, K : @seam.ToRawKind] make_error_tree(
  spec : LanguageSpec[T, K],
) -> @seam.CstNode {
  let err_raw = spec.error_kind.to_raw()
  let error_child = @seam.CstNode::new(err_raw, [], error_kind=Some(err_raw))
  @seam.CstNode::new(
    spec.root_kind.to_raw(),
    [@seam.CstElement::Node(error_child)],
    trivia_kind=Some(spec.whitespace_kind.to_raw()),
    error_kind=Some(err_raw),
    incomplete_kind=Some(spec.incomplete_kind.to_raw()),
  )
}

///|
/// Build the CST from an event buffer using spec metadata for root and trivia kinds.
///
/// The generic parser intentionally uses the non-interned builder so tokens keep
/// zero-copy source spans. Parser-owned reuse events rebase reused token spans
/// onto the current source buffer, avoiding process-global interners and old
/// source-buffer retention.
///
/// Source-span rebasing necessarily constructs fresh CST nodes, so generic
/// parser clients must not rely on stable physical identity for unchanged
/// subtrees across parses. Use structural equality or projection/domain
/// identity for downstream change detection.
fn[T, K : @seam.ToRawKind] build_tree_generic(
  buf : @seam.EventBuffer,
  spec : LanguageSpec[T, K],
) -> @seam.CstNode raise @seam.EventStreamError {
  let ws = spec.whitespace_kind.to_raw()
  buf.build_tree(
    spec.root_kind.to_raw(),
    trivia_kind=Some(ws),
    error_kind=Some(spec.error_kind.to_raw()),
    incomplete_kind=Some(spec.incomplete_kind.to_raw()),
  )
}

///|
/// Generic incremental parse driver. Replaces the lambda-specific
/// `run_parse` / `run_parse_incremental` pair in `src/parser/`.
///
/// Accepts indexed token accessors (avoids O(n) Array[TokenInfo[T]] allocation
/// when the caller already has tokens in a language-specific layout).
/// Uses `spec.parse_root` as the grammar entry point.
///
/// Returns `(CstNode, diagnostics, reuse_count)`.
/// reuse_count is 0 for non-incremental calls (cursor=None).
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] parse_tokens_indexed(
  source : String,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
  spec : LanguageSpec[T, K],
  cursor? : ReuseCursor[T, K]? = None,
  prev_diagnostics? : DiagnosticSet? = None,
) -> (@seam.CstNode, DiagnosticSet, Int) {
  let ctx = ParserContext::new_indexed(
    token_count, get_token, get_start, get_end, source, spec,
  )
  match cursor {
    Some(c) => {
      ctx.set_reuse_cursor(c)
      match prev_diagnostics {
        Some(prev) => ctx.set_reuse_diagnostics(prev)
        None => ()
      }
    }
    None => ()
  }
  (spec.parse_root)(ctx)
  ctx.flush_trivia()
  while ctx.open_nodes > 0 {
    ctx.error("unclosed node (auto-closed)")
    ctx.open_nodes = ctx.open_nodes - 1
    ctx.events.push(@seam.FinishNode)
  }
  let tree = build_tree_generic(ctx.events, spec) catch {
    e => {
      ctx.error("internal: malformed event stream: " + @debug.to_string(e))
      make_error_tree(spec)
    }
  }
  (tree, ctx.diagnostics, ctx.reuse_count)
}

///|
/// Marker trait for typed SyntaxNode view types.
///
/// Every view type in your language package should implement this trait
/// and also provide a `pub fn ViewType::cast(n : @seam.SyntaxNode) -> Self?`
/// static function (can't be in the trait — MoonBit traits require self
/// as first parameter).
///
/// Example:
///   pub struct LambdaExprView { node : @seam.SyntaxNode }
///   pub impl AstView for LambdaExprView with syntax_node(self) { self.node }
///   pub fn LambdaExprView::cast(n : @seam.SyntaxNode) -> LambdaExprView? { ... }
pub(open) trait AstView {
  /// Return the underlying raw SyntaxNode.
  fn syntax_node(Self) -> @seam.SyntaxNode
}
