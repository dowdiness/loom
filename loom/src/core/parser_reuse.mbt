// Generic parser infrastructure — incremental CST reuse

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
