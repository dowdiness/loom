// Generic parser infrastructure — event emission, nodes, and checkpoints

///|
/// Emit all consecutive trivia tokens at current position to the event stream,
/// advancing position past each one. Call this before emitting syntactic tokens,
/// and at the end of the top-level grammar function before returning.
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::flush_trivia(
  self : ParserContext[T, K],
) -> Unit {
  while self.position < self.token_count {
    let token = (self.get_token)(self.position)
    if token.is_trivia() {
      let text = self.text_at(self.position)
      self.events.push(@seam.ParseEvent::Token(token.to_raw(), text))
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
/// Consume consecutive non-trivia tokens matching `pred`, emitting each as
/// `kind` in the CST. Stops at the first non-matching token or at EOF.
/// Use this to absorb a known class of tokens (e.g. soft newlines) before
/// acting on the first non-matching token.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::consume_while_emit(
  self : ParserContext[T, K],
  pred : (T) -> Bool,
  kind : K,
) -> Unit {
  while !self.at_eof() && pred(self.peek()) {
    self.emit_token(kind)
  }
}

///|
/// Consume a run of non-trivia tokens matching `skip_pred`, emitting each as
/// `skip_kind`, only when the first token after the run satisfies `lookahead`.
/// Has no effect when the current token does not match `skip_pred` or when the
/// lookahead fails. Returns true when any tokens were consumed.
///
/// The canonical use case: "consume soft separator tokens before a syntactic
/// category, but never eat structural separators between unrelated constructs."
/// For example, consuming newlines before an expression-starting token without
/// consuming the structural newlines that separate top-level definitions.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::consume_while_emit_if(
  self : ParserContext[T, K],
  skip_pred : (T) -> Bool,
  skip_kind : K,
  lookahead : (T) -> Bool,
) -> Bool {
  if skip_pred(self.peek()) && lookahead(self.peek_while_skip(skip_pred)) {
    self.consume_while_emit(skip_pred, skip_kind)
    true
  } else {
    false
  }
}

///|
/// Consume a contiguous run of delimiter tokens, emitting each with its own
/// mapped kind, and return how many were consumed. Unlike `consume_while_emit`
/// (which emits the whole run as a single kind), this preserves a distinct CST
/// kind per delimiter token — e.g. a block accepting both a newline and a `;`
/// separator emits `NewlineToken` / `SemicolonToken` respectively. The returned
/// count lets callers distinguish "a separator preceded" from "none did"
/// without a pre-consume peek. Stops at the first token absent from `delims` or
/// at EOF.
pub fn[
  T : Eq + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] ParserContext::consume_while_emit_mapped(
  self : ParserContext[T, K],
  delims : Array[(T, K)],
) -> Int {
  let mut count = 0
  while !self.at_eof() {
    match delims.iter().find_first(d => d.0 == self.peek()) {
      Some((_, kind)) => {
        self.emit_token(kind)
        count += 1
      }
      None => break
    }
  }
  count
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
  self.node_stack.push(kind)
  self.events.push(@seam.StartNode(kind.to_raw()))
}

///|
/// Close the most recently opened node.
pub fn[T, K] ParserContext::finish_node(self : ParserContext[T, K]) -> Unit {
  if self.open_nodes <= 0 {
    return
  }
  self.open_nodes = self.open_nodes - 1
  let _ = self.node_stack.pop()
  self.events.push(@seam.FinishNode)
}

///|
/// Reserve a placeholder that can later be claimed by start_at.
/// Used for retroactive wrapping (e.g. binary expressions, applications).
pub fn[T, K] ParserContext::mark(self : ParserContext[T, K]) -> Int {
  self.events.mark()
}

///|
/// Save checkpointed parser execution state: position, events, diagnostic
/// additions, open-node count/stack, reuse cursor/count, and lex mode.
pub fn[T, K] ParserContext::checkpoint(
  self : ParserContext[T, K],
) -> Checkpoint[T, K] {
  let reuse_cursor = self.reuse_cursor.map(cursor => cursor.snapshot())
  let node_stack : Array[K] = []
  for k in self.node_stack {
    node_stack.push(k)
  }
  {
    position: self.position,
    events_len: self.events.length(),
    node_stack_snapshot: node_stack,
    error_count: self.error_count,
    open_nodes: self.open_nodes,
    reuse_cursor,
    reuse_count: self.reuse_count,
    lex_mode: self.lex_mode,
  }
}

///|
/// Restore checkpointed execution state saved by checkpoint().
pub fn[T, K] ParserContext::restore(
  self : ParserContext[T, K],
  cp : Checkpoint[T, K],
) -> Unit {
  self.position = cp.position
  self.events.truncate(cp.events_len)
  self.diagnostics.truncate(cp.error_count)
  self.error_count = cp.error_count
  self.open_nodes = cp.open_nodes
  // Full stack restore — see BLOCKER note
  self.node_stack = []
  for k in cp.node_stack_snapshot {
    self.node_stack.push(k)
  }
  self.reuse_cursor = cp.reuse_cursor.map(cursor => cursor.snapshot())
  self.lex_mode = cp.lex_mode
  self.reuse_count = cp.reuse_count
}

///|
/// Run `body` speculatively, then restore checkpointed parser execution state
/// and return the body's result.
///
/// Use for pure lookahead whose effects are limited to token consumption,
/// events, diagnostic additions, open-node count/stack, reuse cursor/count,
/// and lex mode.
/// It does not roll back in-place diagnostic mutation or parser configuration
/// such as goal sources, goal subsumption checks, or reuse diagnostics.
///
/// Example (Markdown): what is the setext underline depth after the next newline?
///
///   fn depth_after_newline(ctx) -> Int? {
///     ctx.speculative(fn() {
///       ctx.emit_token(NewlineToken)
///       current_setext_depth(ctx)
///     })
///   }
///
/// Closes loom#438.
pub fn[T, K, R] ParserContext::speculative(
  self : ParserContext[T, K],
  body : () -> R,
) -> R {
  let cp = self.checkpoint()
  let result = body()
  self.restore(cp)
  result
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
  self.node_stack.push(kind)
}
