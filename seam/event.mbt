///|
/// A single event in the parse event stream.
///
/// Events are produced by a parser and consumed by `build_tree` /
/// `build_tree_interned` to construct a `CstNode` tree.
///
/// Invariant: the event stream must be balanced — every `StartNode`
/// must have exactly one matching `FinishNode` that follows it.
/// Unclaimed `Tombstone` slots are silently skipped by `build_tree`.
pub(all) enum ParseEvent {
  /// Begin a new interior node of the given kind.
  StartNode(RawKind)
  /// Close the most recently opened interior node.
  FinishNode
  /// A leaf token with the given kind and source text view.
  Token(RawKind, StringView)
  /// A reserved-but-unclaimed slot; ignored by `build_tree`.
  /// Created by `EventBuffer::mark` and replaced by `EventBuffer::start_at`.
  Tombstone
  /// Attach a pre-built CST subtree, skipping parse-time re-emission.
  ///
  /// Public builders rebuild the subtree's nodes under the current
  /// trivia/error metadata and copy token text into per-token backing strings,
  /// so a source-backed reused subtree does not retain or expose an old full
  /// source buffer. Parser-owned reuse that can prove the current source span
  /// should use `EventBuffer::push_parser_reuse_node_rebased` for zero-copy
  /// rebasing.
  ReuseNode(CstNode)
} derive(Debug, Eq)

///|
/// Private event representation used by `EventBuffer`.
///
/// The public `ParseEvent` type intentionally has no source-bearing reuse
/// variant: callers should not be able to smuggle old full source buffers into
/// a finished tree by direct-splicing source-backed tokens. Parser internals can
/// append `BufferedReuseNodeAt` only through
/// `EventBuffer::push_parser_reuse_node_rebased`, where they also provide the
/// current source and start offset. The unchecked variant is reserved for
/// parser code that has already validated the reused node against the current
/// token stream.
enum BufferedEvent {
  BufferedStartNode(RawKind)
  BufferedFinishNode
  BufferedToken(RawKind, StringView)
  BufferedTombstone
  BufferedReuseNode(CstNode)
  BufferedReuseNodeAt(CstNode, String, Int)
  BufferedReuseNodeAtUnchecked(CstNode, String, Int)
} derive(Debug, Eq)

///|
fn buffered_event_of_parse_event(event : ParseEvent) -> BufferedEvent {
  match event {
    StartNode(kind) => BufferedStartNode(kind)
    FinishNode => BufferedFinishNode
    Token(kind, text) => BufferedToken(kind, text)
    Tombstone => BufferedTombstone
    ReuseNode(node) => BufferedReuseNode(node)
  }
}

///|
fn buffered_events_of_parse_events(
  events : Array[ParseEvent],
) -> Array[BufferedEvent] {
  let buffered : Array[BufferedEvent] = Array::new(capacity=events.length())
  for event in events {
    buffered.push(buffered_event_of_parse_event(event))
  }
  buffered
}

///|
/// Accumulates parse events for a single parse run.
///
/// ## Invariants
///
/// The only sanctioned ways to add events are:
/// - `push(event)` — append any `ParseEvent` directly
/// - `push_parser_reuse_node_rebased(node, source, start)` — append parser-
///   owned reuse rebased to the current source buffer, falling back to owned
///   token text if the source span does not match
/// - `push_parser_reuse_node_rebased_unchecked(node, source, start)` — append
///   parser-validated reuse and skip redundant text validation during tree build
/// - `mark()` — reserve a `Tombstone` slot and return its index
/// - `start_at(mark, kind)` — retroactively fill a `Tombstone` with `StartNode`
///
/// After parsing, call `buf.build_tree(...)` or `buf.build_tree_interned(...)`
/// directly on the buffer. The raw backing array is private to
/// prevent callers from bypassing the mark/start_at contract.
pub struct EventBuffer {
  priv events : Array[BufferedEvent]
}

///|
/// Create an empty `EventBuffer`.
pub fn EventBuffer::new() -> EventBuffer {
  { events: [] }
}

///|
/// Build a CST from this buffer's accumulated events.
///
/// Shorthand for `build_tree(buf, root_kind, ...)` that never exposes the
/// backing array, preserving the push/mark/start_at write invariants.
pub fn EventBuffer::build_tree(
  self : EventBuffer,
  root_kind : RawKind,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  build_tree_buffered(
    self.events,
    root_kind,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
/// Build a fully-interned CST from this buffer's accumulated events,
/// deduplicating both tokens (via `interner`) and interior nodes (via `node_interner`).
pub fn EventBuffer::build_tree_fully_interned(
  self : EventBuffer,
  root_kind : RawKind,
  interner : Interner,
  node_interner : NodeInterner,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  build_tree_fully_interned_buffered(
    self.events,
    root_kind,
    interner,
    node_interner,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
/// Build an interned CST from this buffer's accumulated events.
///
/// Shorthand for `build_tree_interned(buf, root_kind, interner, ...)` that
/// never exposes the backing array.
pub fn EventBuffer::build_tree_interned(
  self : EventBuffer,
  root_kind : RawKind,
  interner : Interner,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  build_tree_interned_buffered(
    self.events,
    root_kind,
    interner,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
/// Append a `ParseEvent` directly. Use `mark`/`start_at` for retroactive `StartNode` placement.
pub fn EventBuffer::push(self : EventBuffer, event : ParseEvent) -> Unit {
  self.events.push(buffered_event_of_parse_event(event))
}

///|
/// Append a parser-owned reused subtree rebased onto the current source.
///
/// UNSTABLE/TRUSTED PARSER-OWNED API (#186): public only because parser
/// internals live outside the `seam` module. Application code should prefer
/// `push(ParseEvent::ReuseNode(node))`, which copies token text and does not
/// expose backing-source ownership. This hook is specifically for parser code
/// that owns the current source buffer and wants source-span rebasing.
///
/// `source_start` is the subtree's start offset in `source`. During tree build,
/// matching reused token text is rebuilt as `StringView`s into `source`,
/// preserving zero-copy token text without retaining the old source buffer that
/// originally backed `node`. If the provided source span does not match the
/// reused subtree text, tree build falls back to owned token text.
#alias(push_reuse_node_at, deprecated="Use EventBuffer::push_parser_reuse_node_rebased for parser-owned source-span rebasing; application code should use push(ParseEvent::ReuseNode(...))")
pub fn EventBuffer::push_parser_reuse_node_rebased(
  self : EventBuffer,
  node : CstNode,
  source : String,
  source_start : Int,
) -> Unit {
  self.events.push(BufferedReuseNodeAt(node, source, source_start))
}

///|
/// Append a parser-validated reused subtree rebased onto the current source.
///
/// UNSTABLE/TRUSTED PARSER-OWNED API (#187/#186): public only because parser
/// internals live outside the `seam` module. Use this only after the parser has
/// already proven that `node` is valid at `source_start` in `source` (outside
/// the damage range, with matching leading/trailing token context). The
/// non-interned builder still constructs fresh `CstToken`s and `CstNode`s with
/// current-source spans and recomputed metadata; interned builders rebase before
/// their normal interning step. No builder direct-splices the old node, so this
/// path does not retain the old source buffer.
#alias(push_reuse_node_at_unchecked, deprecated="Use EventBuffer::push_parser_reuse_node_rebased_unchecked for parser-validated source-span rebasing")
pub fn EventBuffer::push_parser_reuse_node_rebased_unchecked(
  self : EventBuffer,
  node : CstNode,
  source : String,
  source_start : Int,
) -> Unit {
  self.events.push(BufferedReuseNodeAtUnchecked(node, source, source_start))
}

///|
/// Reserve a slot and return its index. Used for retroactive StartNode placement.
/// The slot must either be claimed exactly once via start_at() or remain as
/// Tombstone (which build_tree ignores).
pub fn EventBuffer::mark(self : EventBuffer) -> Int {
  let index = self.events.length()
  self.events.push(BufferedTombstone)
  index
}

///|
/// Retroactively fill a Tombstone slot with StartNode(kind).
/// This function enforces the mark/start_at contract:
/// - mark must be in bounds
/// - mark must still point to Tombstone
pub fn EventBuffer::start_at(
  self : EventBuffer,
  mark : Int,
  kind : RawKind,
) -> Unit {
  if mark < 0 || mark >= self.events.length() {
    abort(
      "EventBuffer::start_at: mark out of bounds, mark=" +
      mark.to_string() +
      ", len=" +
      self.events.length().to_string(),
    )
  }
  match self.events[mark] {
    BufferedTombstone => self.events[mark] = BufferedStartNode(kind)
    _ =>
      abort(
        "EventBuffer::start_at: mark does not point to Tombstone, mark=" +
        mark.to_string(),
      )
  }
}

///|
/// Current number of events in the buffer.
pub fn EventBuffer::length(self : EventBuffer) -> Int {
  self.events.length()
}

///|
/// Truncate the buffer to the first `n` events, discarding the rest.
/// No-op when n is outside [0, length].
pub fn EventBuffer::truncate(self : EventBuffer, n : Int) -> Unit {
  let keep = if n < 0 {
    0
  } else if n > self.events.length() {
    self.events.length()
  } else {
    n
  }
  while self.events.length() > keep {
    let _ = self.events.pop()
  }
}

///|
/// Rebuild a reused subtree with per-token owned backing strings.
///
/// This is the safe public `ParseEvent::ReuseNode` path: callers can reuse a
/// shape without retaining or exposing the old full source string that backed a
/// source-span token.
fn rebuild_subtree_owned(
  node : CstNode,
  trivia_kind : RawKind?,
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
) -> CstNode {
  let children : Array[CstElement] = []
  for child in node.children {
    match child {
      CstElement::Token(t) => {
        let owned = t.text().to_owned()
        children.push(CstElement::Token(CstToken::CstToken(t.kind, owned)))
      }
      CstElement::Node(n) => {
        let rebuilt = rebuild_subtree_owned(
          n, trivia_kind, error_kind, incomplete_kind,
        )
        children.push(CstElement::Node(rebuilt))
      }
    }
  }
  CstNode::new(node.kind, children, trivia_kind~, error_kind~, incomplete_kind~)
}

///|
/// True when `node`'s token text matches `source` at `source_start`.
///
/// Used to make the public parser-owned reuse hook total: trusted parser calls
/// get zero-copy rebased spans, while accidental wrong-source calls fall back to
/// owned token text instead of silently producing wrong tokens or slicing out of
/// bounds.
fn subtree_matches_source(
  node : CstNode,
  source : String,
  source_start : Int,
) -> Bool {
  if source_start < 0 || source_start + node.text_len > source.length() {
    return false
  }
  let mut offset = source_start
  for child in node.children {
    match child {
      CstElement::Token(t) => {
        let end = offset + t.text_len()
        if source.view(start_offset=offset, end_offset=end) != t.text() {
          return false
        }
        offset = end
      }
      CstElement::Node(n) => {
        if !subtree_matches_source(n, source, offset) {
          return false
        }
        offset = offset + n.text_len
      }
    }
  }
  true
}

///|
/// Rebuild a reused subtree with token spans into the current source buffer.
///
/// Precondition: `subtree_matches_source(node, source, source_start)` is true.
fn rebase_subtree_to_source_unchecked(
  node : CstNode,
  source : String,
  source_start : Int,
  trivia_kind : RawKind?,
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
) -> CstNode {
  let children : Array[CstElement] = []
  let mut offset = source_start
  for child in node.children {
    match child {
      CstElement::Token(t) => {
        let end = offset + t.text_len()
        let token = CstToken::CstToken(
          t.kind,
          source.view(start_offset=offset, end_offset=end),
        )
        children.push(CstElement::Token(token))
        offset = end
      }
      CstElement::Node(n) => {
        let rebuilt = rebase_subtree_to_source_unchecked(
          n, source, offset, trivia_kind, error_kind, incomplete_kind,
        )
        children.push(CstElement::Node(rebuilt))
        offset = offset + n.text_len
      }
    }
  }
  CstNode::new(node.kind, children, trivia_kind~, error_kind~, incomplete_kind~)
}

///|
/// Rebuild a reused subtree against `source` when the text matches, otherwise
/// fall back to owned token text.
fn rebuild_subtree_for_source(
  node : CstNode,
  source : String,
  source_start : Int,
  trivia_kind : RawKind?,
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
) -> CstNode {
  if subtree_matches_source(node, source, source_start) {
    rebase_subtree_to_source_unchecked(
      node, source, source_start, trivia_kind, error_kind, incomplete_kind,
    )
  } else {
    rebuild_subtree_owned(node, trivia_kind, error_kind, incomplete_kind)
  }
}

///|
/// Build a concrete syntax tree from a flat event stream, interning all tokens through
/// the provided Interner. Structurally identical to build_tree; differs only
/// in that Token events are deduplicated via intern_token.
///
/// Use this variant when tokens will be reused across multiple parses of the
/// same document (e.g. in IncrementalParser).
///
/// `trivia_kind`: forwarded to every `CstNode::new` call; leaf tokens with
/// this kind are excluded from each node's `token_count`.
pub fn build_tree_interned(
  events : Array[ParseEvent],
  root_kind : RawKind,
  interner : Interner,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  build_tree_interned_buffered(
    buffered_events_of_parse_events(events),
    root_kind,
    interner,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
fn intern_reuse_tokens_only(
  node : CstNode,
  interner : Interner,
  trivia_kind : RawKind?,
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
) -> CstElement {
  CstElement::Node(node).map(
    elem => {
      match elem {
        Token(t) => Token(interner.intern_token(t.kind, t.text()))
        _ => elem
      }
    },
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
fn build_tree_interned_buffered(
  events : Array[BufferedEvent],
  root_kind : RawKind,
  interner : Interner,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      BufferedStartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      BufferedFinishNode => {
        let raw_children = match stack.pop() {
          Some(c) => c
          None => raise EventStreamError::UnbalancedFinish
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None => raise EventStreamError::UnbalancedFinish
        }
        let children = balance_children(
          raw_children, trivia_kind, error_kind, incomplete_kind,
        )
        let node = CstNode::new(
          kind,
          children,
          trivia_kind~,
          error_kind~,
          incomplete_kind~,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => raise EventStreamError::UnbalancedFinish
        }
      }
      BufferedToken(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNode(node) => {
        let interned = intern_reuse_tokens_only(
          node, interner, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(interned)
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNodeAt(node, source, source_start) => {
        let rebased = rebuild_subtree_for_source(
          node, source, source_start, trivia_kind, error_kind, incomplete_kind,
        )
        let interned = intern_reuse_tokens_only(
          rebased, interner, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(interned)
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNodeAtUnchecked(node, source, source_start) => {
        let rebased = rebase_subtree_to_source_unchecked(
          node, source, source_start, trivia_kind, error_kind, incomplete_kind,
        )
        let interned = intern_reuse_tokens_only(
          rebased, interner, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(interned)
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedTombstone => ()
    }
  }
  if stack.length() != 1 {
    raise EventStreamError::UnbalancedStart(missing_finishes=stack.length() - 1)
  }
  let root_children = balance_children(
    stack[0],
    trivia_kind,
    error_kind,
    incomplete_kind,
  )
  CstNode::new(
    root_kind,
    root_children,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
/// Recursively re-intern a CstNode subtree: every token passes through
/// intern_token, every node through intern_node. For already-interned trees
/// (from a previous build_tree_fully_interned call), all lookups are O(1)
/// cache hits via physical_equal. For non-interned trees, this ensures the
/// result is fully canonical.
fn re_intern_subtree(
  node : CstNode,
  interner : Interner,
  node_interner : NodeInterner,
  trivia_kind : RawKind?,
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
) -> CstNode {
  let children : Array[CstElement] = []
  for child in node.children {
    match child {
      CstElement::Token(t) => {
        let interned = interner.intern_token(t.kind, t.text())
        children.push(CstElement::Token(interned))
      }
      CstElement::Node(n) => {
        let interned = re_intern_subtree(
          n, interner, node_interner, trivia_kind, error_kind, incomplete_kind,
        )
        children.push(CstElement::Node(interned))
      }
    }
  }
  node_interner.intern_node(
    CstNode::new(
      node.kind,
      children,
      trivia_kind~,
      error_kind~,
      incomplete_kind~,
    ),
  )
}

///|
/// Build a CST from a flat event stream, interning both tokens (via `interner`)
/// and interior nodes (via `node_interner`). Identical subtrees share a single
/// canonical CstNode reference in memory.
///
/// Construction is bottom-up: children are interned before their parent, so
/// the parent's equality check terminates at hash match without deep recursion.
///
/// `trivia_kind`: forwarded to every `CstNode::new` call; leaf tokens with
/// this kind are excluded from each node's `token_count`.
pub fn build_tree_fully_interned(
  events : Array[ParseEvent],
  root_kind : RawKind,
  interner : Interner,
  node_interner : NodeInterner,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  build_tree_fully_interned_buffered(
    buffered_events_of_parse_events(events),
    root_kind,
    interner,
    node_interner,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
fn build_tree_fully_interned_buffered(
  events : Array[BufferedEvent],
  root_kind : RawKind,
  interner : Interner,
  node_interner : NodeInterner,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      BufferedStartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      BufferedFinishNode => {
        let raw_children = match stack.pop() {
          Some(c) => c
          None => raise EventStreamError::UnbalancedFinish
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None => raise EventStreamError::UnbalancedFinish
        }
        let children = balance_children(
          raw_children, trivia_kind, error_kind, incomplete_kind,
        )
        let node = node_interner.intern_node(
          CstNode::new(
            kind,
            children,
            trivia_kind~,
            error_kind~,
            incomplete_kind~,
          ),
        )
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => raise EventStreamError::UnbalancedFinish
        }
      }
      BufferedToken(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNode(node) => {
        let interned = re_intern_subtree(
          node, interner, node_interner, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(interned))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNodeAt(node, source, source_start) => {
        let rebased = rebuild_subtree_for_source(
          node, source, source_start, trivia_kind, error_kind, incomplete_kind,
        )
        let interned = re_intern_subtree(
          rebased, interner, node_interner, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(interned))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNodeAtUnchecked(node, source, source_start) => {
        let rebased = rebase_subtree_to_source_unchecked(
          node, source, source_start, trivia_kind, error_kind, incomplete_kind,
        )
        let interned = re_intern_subtree(
          rebased, interner, node_interner, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(interned))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedTombstone => ()
    }
  }
  if stack.length() != 1 {
    raise EventStreamError::UnbalancedStart(missing_finishes=stack.length() - 1)
  }
  let root_children = balance_children(
    stack[0],
    trivia_kind,
    error_kind,
    incomplete_kind,
  )
  node_interner.intern_node(
    CstNode::new(
      root_kind,
      root_children,
      trivia_kind~,
      error_kind~,
      incomplete_kind~,
    ),
  )
}

///|
/// Build a concrete syntax tree from a flat event stream.
/// root_kind is the kind of the implicit root node (e.g., SourceFile).
///
/// `trivia_kind`: forwarded to every `CstNode::new` call; leaf tokens with
/// this kind are excluded from each node's `token_count`.
pub fn build_tree(
  events : Array[ParseEvent],
  root_kind : RawKind,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  build_tree_buffered(
    buffered_events_of_parse_events(events),
    root_kind,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
fn build_tree_buffered(
  events : Array[BufferedEvent],
  root_kind : RawKind,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  // stack and kinds move in lockstep:
  // - StartNode pushes one frame + one kind
  // - FinishNode pops one frame + one kind
  //
  // stack[0] / kinds[0] represent the implicit root passed in root_kind.
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      BufferedStartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      BufferedFinishNode => {
        let raw_children = match stack.pop() {
          Some(c) => c
          None => raise EventStreamError::UnbalancedFinish
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None => raise EventStreamError::UnbalancedFinish
        }
        let children = balance_children(
          raw_children, trivia_kind, error_kind, incomplete_kind,
        )
        let node = CstNode::new(
          kind,
          children,
          trivia_kind~,
          error_kind~,
          incomplete_kind~,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => raise EventStreamError::UnbalancedFinish
        }
      }
      BufferedToken(kind, text) => {
        let token = CstToken::CstToken(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNode(node) => {
        let rebuilt = rebuild_subtree_owned(
          node, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(rebuilt))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNodeAt(node, source, source_start) => {
        let rebased = rebuild_subtree_for_source(
          node, source, source_start, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(rebased))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      BufferedReuseNodeAtUnchecked(node, source, source_start) => {
        let rebased = rebase_subtree_to_source_unchecked(
          node, source, source_start, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(rebased))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      // Unclaimed marks are expected and intentionally ignored.
      BufferedTombstone => ()
    }
  }
  if stack.length() != 1 {
    raise EventStreamError::UnbalancedStart(missing_finishes=stack.length() - 1)
  }
  let root_children = balance_children(
    stack[0],
    trivia_kind,
    error_kind,
    incomplete_kind,
  )
  CstNode::new(
    root_kind,
    root_children,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
}

///|
/// Minimum run length to trigger grouping. Runs of same-kind node siblings
/// shorter than this are left as flat children.
let balance_threshold : Int = 8

///|
/// Balance long runs of consecutive same-kind node siblings into a binary
/// tree of RepeatGroup sub-nodes. Token children and short or mixed runs
/// are left untouched.
///
/// Separator tokens between same-kind nodes are absorbed into the group.
/// This allows `LetDef \n LetDef \n ...` patterns to form balanced trees
/// even though delimiter tokens interleave the nodes.
///
/// This reduces O(n) reuse checks during incremental parsing to O(log n)
/// by letting the incremental parser skip entire groups as single units.
fn balance_children(
  children : Array[CstElement],
  trivia_kind : RawKind?,
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
) -> Array[CstElement] {
  if children.length() <= balance_threshold {
    return children
  }
  let result : Array[CstElement] = []
  let mut i = 0
  while i < children.length() {
    // Check if this child is a Node (not Token)
    match children[i] {
      CstElement::Node(n) => {
        // Find the run of consecutive Node children with the same kind,
        // absorbing interleaved separator tokens into the run.
        let run_kind = n.kind
        let run_start = i
        let mut node_count = 1
        i = i + 1
        while i < children.length() {
          match children[i] {
            CstElement::Node(m) =>
              if m.kind == run_kind {
                node_count = node_count + 1
                i = i + 1
              } else {
                break
              }
            CstElement::Token(_) =>
              // Absorb separator token if followed by another same-kind node.
              // Peek ahead to decide whether to include the token in the run.
              if i + 1 < children.length() {
                match children[i + 1] {
                  CstElement::Node(m) =>
                    if m.kind == run_kind {
                      i = i + 1 // absorb the separator token
                    } else {
                      break
                    }
                  _ => break
                }
              } else {
                break
              }
          }
        }
        if node_count > balance_threshold {
          // Build balanced groups from the run (index-based, no copy)
          build_balanced_group(
            children, run_start, i, trivia_kind, error_kind, incomplete_kind, result,
          )
        } else {
          // Short run — copy as-is
          for j = run_start; j < i; j = j + 1 {
            result.push(children[j])
          }
        }
      }
      CstElement::Token(_) => {
        result.push(children[i])
        i = i + 1
      }
    }
  }
  result
}

///|
/// Recursively split a range of elements into balanced binary RepeatGroup
/// sub-nodes until each group has at most `balance_threshold` elements.
/// Appends the resulting RepeatGroup wrapper node(s) to `out`.
/// Operates on index ranges [start, end) to avoid intermediate array copies.
fn build_balanced_group(
  elements : Array[CstElement],
  start : Int,
  end : Int,
  trivia_kind : RawKind?,
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
  out : Array[CstElement],
) -> Unit {
  let len = end - start
  if len <= balance_threshold {
    // Base case: copy this range into a single RepeatGroup
    let children : Array[CstElement] = Array::new(capacity=len)
    for j = start; j < end; j = j + 1 {
      children.push(elements[j])
    }
    let group = CstNode::new(
      repeat_group_kind,
      children,
      trivia_kind~,
      error_kind~,
      incomplete_kind~,
    )
    out.push(CstElement::Node(group))
    return
  }
  // Split in half — find the nearest node boundary at or after midpoint
  let mut mid = start + len / 2
  while mid < end {
    match elements[mid] {
      CstElement::Node(_) => break
      CstElement::Token(_) => mid = mid + 1
    }
  }
  if mid >= end {
    mid = start + len / 2
  }
  // Recurse into left and right halves, collecting into a shared buffer
  let group_children : Array[CstElement] = []
  build_balanced_group(
    elements, start, mid, trivia_kind, error_kind, incomplete_kind, group_children,
  )
  build_balanced_group(
    elements, mid, end, trivia_kind, error_kind, incomplete_kind, group_children,
  )
  let group = CstNode::new(
    repeat_group_kind,
    group_children,
    trivia_kind~,
    error_kind~,
    incomplete_kind~,
  )
  out.push(CstElement::Node(group))
}
