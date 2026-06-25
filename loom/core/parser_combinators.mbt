// Generic parser infrastructure — grammar combinators

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
/// Try to reuse a regular CST node at the current parse position.
///
/// Use this before retroactive wrappers (`mark`/`wrap_at`) whose stable node
/// boundary begins at the current token but whose fallback parse must first emit
/// a prefix before it can wrap. `node()` cannot express that shape because it
/// opens the wrapper before parsing the prefix; this helper gives those parsers
/// the same reuse fast path without changing their fallback CST event order.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::try_reuse_current_node(
  self : ParserContext[T, K],
  kind : K,
) -> Bool {
  match self.try_reuse(kind) {
    Some(reuse) => {
      self.emit_reused(reuse)
      true
    }
    None => false
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
