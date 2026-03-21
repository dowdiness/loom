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
  length(Self) -> Int
  /// The sort key (code-unit offset) at index i. Must be non-decreasing in i.
  offset_at(Self, Int) -> Int
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
  // reuse support: match old leaves to new tokens
  cst_token_matches : (@seam.RawKind, String, T) -> Bool
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
  cst_token_matches? : (@seam.RawKind, String, T) -> Bool = fn(_, _, _) {
    false
  },
  parse_root? : (ParserContext[T, K]) -> Unit = _ => (),
  reuse_size_threshold? : Int = 64,
) -> LanguageSpec[T, K] {
  {
    whitespace_kind,
    error_kind,
    incomplete_kind,
    root_kind,
    eof_token,
    cst_token_matches,
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
pub struct ParserContext[T, K] {
  spec : LanguageSpec[T, K]
  token_count : Int
  get_token : (Int) -> T
  get_start : (Int) -> Int
  get_end : (Int) -> Int
  source : String
  mut position : Int
  events : @seam.EventBuffer
  errors : Array[Diagnostic[T]]
  mut error_count : Int
  mut open_nodes : Int
  // Incremental reuse — None on a fresh parse, Some(cursor) for incremental.
  mut reuse_cursor : ReuseCursor[T, K]?
  // Diagnostics from the previous parse (optional). When present, reuse hits
  // replay matching diagnostics by code-unit span to preserve exact messages.
  mut reuse_diagnostics : Array[Diagnostic[T]]?
  mut reuse_count : Int
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
    errors: [],
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
    errors: [],
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
  let mut pos = self.position
  let mut count = 0
  while pos < self.token_count {
    let t = (self.get_token)(pos)
    if t.is_trivia() {
      pos = pos + 1
    } else {
      if count == n {
        return t
      }
      count = count + 1
      pos = pos + 1
    }
  }
  self.spec.eof_token
}

///|
/// Return the TokenInfo for the next non-trivia token.
pub fn[T : @seam.IsTrivia, K] ParserContext::peek_info(
  self : ParserContext[T, K],
) -> TokenInfo[T] {
  let mut pos = self.position
  while pos < self.token_count {
    let token = (self.get_token)(pos)
    if token.is_trivia() {
      pos = pos + 1
    } else {
      let len = (self.get_end)(pos) - (self.get_start)(pos)
      return { token, len }
    }
  }
  { token: self.spec.eof_token, len: 0 }
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
/// Return true if at end of input (ignoring trivia).
pub fn[T : @seam.IsTrivia + @seam.IsEof, K] ParserContext::at_eof(
  self : ParserContext[T, K],
) -> Bool {
  self.peek().is_eof()
}

///|
/// Extract source text for a token at a given position index.
/// Returns "" on invalid indices/spans rather than aborting — span errors
/// (whether from a tokenizer bug or a grammar invariant violation) produce an
/// empty leaf in the tree instead of crashing a long-running host process or
/// LSP.
pub fn[T, K] ParserContext::token_text_at(
  self : ParserContext[T, K],
  pos : Int,
) -> String {
  if pos < 0 || pos >= self.token_count {
    return ""
  }
  let start = (self.get_start)(pos)
  let end = (self.get_end)(pos)
  if start < 0 || end < start || end > self.source.length() {
    return ""
  }
  let slice : StringView = self.source[start:end]
  slice.to_string()
}

///|
/// Extract source text at a token index. Internal alias for token_text_at.
fn[T, K] ParserContext::text_at(
  self : ParserContext[T, K],
  pos : Int,
) -> String {
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
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::emit_token(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.flush_trivia()
  if self.at_eof() {
    self.error("emit_token: unexpected EOF")
    self.events.push(@seam.ParseEvent::Token(kind.to_raw(), ""))
    return
  }
  let text = self.text_at(self.position)
  self.events.push(@seam.ParseEvent::Token(kind.to_raw(), text))
  self.position = self.position + 1
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
  let reuse_cursor = match self.reuse_cursor {
    Some(cursor) => Some(cursor.snapshot())
    None => None
  }
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
  while self.errors.length() > 0 && self.error_count > cp.error_count {
    let _ = self.errors.pop()
    self.error_count = self.error_count - 1
  }
  self.open_nodes = cp.open_nodes
  self.reuse_cursor = match cp.reuse_cursor {
    Some(cursor) => Some(cursor.snapshot())
    None => None
  }
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
/// Record a diagnostic at the current position. Does not consume a token.
/// Captures the offending token so consumers never need to re-tokenize.
/// If an equivalent diagnostic (same message/start/end) already exists, this
/// updates the stored token payload instead of appending a duplicate entry.
pub fn[T : @seam.IsTrivia, K] ParserContext::error(
  self : ParserContext[T, K],
  msg : String,
) -> Unit {
  // Find the next non-trivia token and compute its position directly.
  let mut pos = self.position
  while pos < self.token_count {
    let token = (self.get_token)(pos)
    if token.is_trivia() {
      pos = pos + 1
    } else {
      let start = (self.get_start)(pos)
      let end = (self.get_end)(pos)
      let _ = self.push_diagnostic_unique({
        message: msg,
        start,
        end,
        got_token: token,
      })
      return
    }
  }
  let eof = self.source.length()
  let _ = self.push_diagnostic_unique({
    message: msg,
    start: eof,
    end: eof,
    got_token: self.spec.eof_token,
  })
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
  self.events.push(@seam.ParseEvent::Token(kind.to_raw(), ""))
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
/// spans fall within the reused node are replayed into self.errors.
pub fn[T, K] ParserContext::set_reuse_diagnostics(
  self : ParserContext[T, K],
  diagnostics : Array[Diagnostic[T]],
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
fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::try_reuse(
  self : ParserContext[T, K],
  kind : K,
) -> @seam.CstNode? {
  if self.position >= self.token_count {
    return None
  }
  let byte_offset = (self.get_start)(self.position)
  // Skip trivia to find the logical token position for leading-token matching.
  let mut token_pos = self.position
  while token_pos < self.token_count && (self.get_token)(token_pos).is_trivia() {
    token_pos = token_pos + 1
  }
  match self.reuse_cursor {
    None => None
    Some(cursor) => cursor.try_reuse(kind.to_raw(), byte_offset, token_pos)
  }
}

///|
/// Advance position past all tokens (trivia + non-trivia) covered by node.
/// Offset-based advancing avoids over-consuming when reused subtrees contain
/// zero-width non-trivia leaves (e.g. error placeholders).
fn[T, K] ParserContext::advance_past_reused(
  self : ParserContext[T, K],
  node : @seam.CstNode,
) -> Unit {
  if self.position >= self.token_count {
    return
  }
  let node_end = (self.get_start)(self.position) + node.text_len
  while self.position < self.token_count &&
        (self.get_start)(self.position) < node_end {
    self.position = self.position + 1
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
  let mut pos = from_pos
  while pos < self.token_count {
    let start = (self.get_start)(pos)
    let end = (self.get_end)(pos)
    if start >= byte_offset || end > byte_offset {
      return { token: (self.get_token)(pos), len: end - start }
    }
    pos = pos + 1
  }
  { token: self.spec.eof_token, len: 0 }
}

///|
/// Add a diagnostic unless an equivalent one already exists.
/// Equivalence: same message and span. If found, update got_token to the latest.
/// Returns true if newly added, false if an existing diagnostic was updated.
fn[T, K] ParserContext::push_diagnostic_unique(
  self : ParserContext[T, K],
  diag : Diagnostic[T],
) -> Bool {
  for i, existing in self.errors.iter2() {
    if existing.message == diag.message &&
      existing.start == diag.start &&
      existing.end == diag.end {
      // Keep a single logical diagnostic per message/span, but refresh token
      // with the most recent parse emission.
      self.errors[i] = diag
      return false
    }
  }
  self.errors.push(diag)
  self.error_count = self.error_count + 1
  true
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
      for d in prev {
        // Half-open containment: [node_start, node_end), with one exception:
        // keep zero-width diagnostics at node_end only when this reused node
        // itself owns a zero-width error at that boundary (structural check),
        // OR when the node ends at EOF and no error-bearing sibling follows
        // (handles ctx.error at EOF without emit_error_placeholder).
        let keep_right_boundary = d.start == node_end &&
          d.end == node_end &&
          (
            owns_right_boundary_zero_width_error ||
            (allow_eof_boundary && node_end >= self.source.length())
          )
        if d.start >= node_start &&
          d.end <= node_end &&
          (d.start < node_end || keep_right_boundary) {
          if self.push_diagnostic_unique(d) {
            replayed_any = true
          }
        }
      }
  }
  replayed_any
}

///|
/// If previous diagnostics are unavailable, synthesize diagnostics from
/// pre-collected error spans in the reused subtree.
fn[T, K] ParserContext::synthesize_reused_diagnostics(
  self : ParserContext[T, K],
  spans : Array[ReusedErrorSpan],
) -> Unit {
  for span in spans {
    let info = self.token_info_at_or_after(self.position, span.start)
    let _ = self.push_diagnostic_unique({
      message: "reused syntax error",
      start: span.start,
      end: span.end,
      got_token: info.token,
    })
  }
}

///|
/// Emit a reused node, replay its diagnostics, and advance both positions
/// past it. Order matters:
///   1. ReuseNode event    — attach pre-built subtree directly (no serialize)
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
fn[T, K : @seam.ToRawKind] ParserContext::emit_reused(
  self : ParserContext[T, K],
  node : @seam.CstNode,
) -> Unit {
  let node_start = if self.position < self.token_count {
    (self.get_start)(self.position)
  } else {
    self.source.length()
  }
  let node_end = node_start + node.text_len
  self.events.push(@seam.ParseEvent::ReuseNode(node))
  let allow_eof_boundary = match self.reuse_cursor {
    None => true
    Some(cursor) => not(cursor.next_sibling_has_error())
  }
  if node.has_any_error {
    // Slow path: node has errors — collect spans and replay/synthesize diagnostics.
    let error_spans : Array[ReusedErrorSpan] = []
    let _ = collect_reused_error_spans(node, node_start, self.spec, error_spans)
    let owns_right_boundary = error_spans
      .iter()
      .any(s => s.start == node_end && s.end == node_end)
    if not(
        self.replay_reused_diagnostics(
          node_start, node_end, owns_right_boundary, allow_eof_boundary,
        ),
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
  self.advance_past_reused(node)
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
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::node(
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
    // Errors recorded inside body() accumulate in self.errors as usual.
    self.start_node(kind)
    body()
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
/// finish_node events are pushed; the ReuseNode event reattaches the
/// pre-built balanced tree as-is.
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::try_reuse_repeat_group(
  self : ParserContext[T, K],
) -> Bool {
  if self.position >= self.token_count {
    return false
  }
  let byte_offset = (self.get_start)(self.position)
  let mut token_pos = self.position
  while token_pos < self.token_count && (self.get_token)(token_pos).is_trivia() {
    token_pos = token_pos + 1
  }
  match self.reuse_cursor {
    None => false
    Some(cursor) =>
      match cursor.try_reuse_repeat_group(byte_offset, token_pos) {
        None => false
        Some(node) => {
          self.emit_reused(node)
          true
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
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] parse_with(
  source : String,
  spec : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, Array[Diagnostic[T]]) {
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
  )
  (tree, ctx.errors)
}

///|
/// Build the CST from an event buffer using spec metadata for root and trivia kinds.
/// Always uses the module-level global interners from core/interners.mbt.
fn[T, K : @seam.ToRawKind] build_tree_generic(
  buf : @seam.EventBuffer,
  spec : LanguageSpec[T, K],
) -> @seam.CstNode {
  let ws = spec.whitespace_kind.to_raw()
  let root = spec.root_kind.to_raw()
  buf.build_tree_fully_interned(
    root,
    core_interner,
    get_core_node_interner(ws),
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
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] parse_tokens_indexed(
  source : String,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
  spec : LanguageSpec[T, K],
  cursor? : ReuseCursor[T, K]? = None,
  prev_diagnostics? : Array[Diagnostic[T]]? = None,
) -> (@seam.CstNode, Array[Diagnostic[T]], Int) {
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
  (build_tree_generic(ctx.events, spec), ctx.errors, ctx.reuse_count)
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
  syntax_node(Self) -> @seam.SyntaxNode
}
