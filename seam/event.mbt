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
  /// A leaf token with the given kind and text.
  Token(RawKind, String)
  /// A reserved-but-unclaimed slot; ignored by `build_tree`.
  /// Created by `EventBuffer::mark` and replaced by `EventBuffer::start_at`.
  Tombstone
  /// Attach a pre-built CST subtree directly, skipping serialize/deserialize.
  /// Used by incremental parsers to avoid re-emitting events for reused nodes.
  /// Builders re-intern the node through their interner(s) to preserve contracts.
  ReuseNode(CstNode)
} derive(Show, Eq)

///|
/// Accumulates parse events for a single parse run.
///
/// ## Invariants
///
/// The only sanctioned ways to add events are:
/// - `push(event)` — append any `ParseEvent` directly
/// - `mark()` — reserve a `Tombstone` slot and return its index
/// - `start_at(mark, kind)` — retroactively fill a `Tombstone` with `StartNode`
///
/// After parsing, call `buf.build_tree(...)` or `buf.build_tree_interned(...)`
/// directly on the buffer. The raw backing array is private to
/// prevent callers from bypassing the mark/start_at contract.
pub struct EventBuffer {
  priv events : Array[ParseEvent]
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
) -> CstNode {
  build_tree(self.events, root_kind, trivia_kind~)
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
) -> CstNode {
  build_tree_fully_interned(
    self.events,
    root_kind,
    interner,
    node_interner,
    trivia_kind~,
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
) -> CstNode {
  build_tree_interned(self.events, root_kind, interner, trivia_kind~)
}

///|
/// Append a `ParseEvent` directly. Use `mark`/`start_at` for retroactive `StartNode` placement.
pub fn EventBuffer::push(self : EventBuffer, event : ParseEvent) -> Unit {
  self.events.push(event)
}

///|
/// Reserve a slot and return its index. Used for retroactive StartNode placement.
/// The slot must either be claimed exactly once via start_at() or remain as
/// Tombstone (which build_tree ignores).
pub fn EventBuffer::mark(self : EventBuffer) -> Int {
  let index = self.events.length()
  self.events.push(Tombstone)
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
    Tombstone => self.events[mark] = StartNode(kind)
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
) -> CstNode {
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      StartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      FinishNode => {
        let children = match stack.pop() {
          Some(c) => c
          None =>
            abort(
              "build_tree_interned: unbalanced FinishNode — no matching StartNode",
            )
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None =>
            abort("build_tree_interned: kind stack underflow on FinishNode")
        }
        let node = CstNode::new(kind, children, trivia_kind~)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort("build_tree_interned: parent stack empty when attaching node")
        }
      }
      Token(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => abort("build_tree_interned: stack empty when adding token")
        }
      }
      ReuseNode(node) =>
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort("build_tree_interned: stack empty when attaching reuse node")
        }
      Tombstone => ()
    }
  }
  if stack.length() != 1 {
    abort(
      "build_tree_interned: unbalanced StartNode — missing FinishNode(s), stack=" +
      stack.length().to_string(),
    )
  }
  CstNode::new(root_kind, stack[0], trivia_kind~)
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
) -> CstNode {
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      StartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      FinishNode => {
        let children = match stack.pop() {
          Some(c) => c
          None =>
            abort(
              "build_tree_fully_interned: unbalanced FinishNode — no matching StartNode",
            )
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None =>
            abort(
              "build_tree_fully_interned: kind stack underflow on FinishNode",
            )
        }
        let node = node_interner.intern_node(
          CstNode::new(kind, children, trivia_kind~),
        )
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort(
              "build_tree_fully_interned: parent stack empty when attaching node",
            )
        }
      }
      Token(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None =>
            abort("build_tree_fully_interned: stack empty when adding token")
        }
      }
      ReuseNode(node) => {
        // Re-intern to preserve the contract that all nodes pass through
        // the node interner. For already-interned nodes this is an O(1) cache hit.
        let interned = node_interner.intern_node(node)
        match stack.last() {
          Some(parent) => parent.push(Node(interned))
          None =>
            abort(
              "build_tree_fully_interned: stack empty when attaching reuse node",
            )
        }
      }
      Tombstone => ()
    }
  }
  if stack.length() != 1 {
    abort(
      "build_tree_fully_interned: unbalanced StartNode — missing FinishNode(s), stack=" +
      stack.length().to_string(),
    )
  }
  node_interner.intern_node(CstNode::new(root_kind, stack[0], trivia_kind~))
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
) -> CstNode {
  // stack and kinds move in lockstep:
  // - StartNode pushes one frame + one kind
  // - FinishNode pops one frame + one kind
  //
  // stack[0] / kinds[0] represent the implicit root passed in root_kind.
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      StartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      FinishNode => {
        let children = match stack.pop() {
          Some(c) => c
          None =>
            abort("build_tree: unbalanced FinishNode — no matching StartNode")
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None => abort("build_tree: kind stack underflow on FinishNode")
        }
        let node = CstNode::new(kind, children, trivia_kind~)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => abort("build_tree: parent stack empty when attaching node")
        }
      }
      Token(kind, text) => {
        let token = CstToken::new(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => abort("build_tree: stack empty when adding token")
        }
      }
      ReuseNode(node) =>
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => abort("build_tree: stack empty when attaching reuse node")
        }
      // Unclaimed marks are expected and intentionally ignored.
      Tombstone => ()
    }
  }
  // If stack is not back to the implicit root frame, we are missing one or
  // more FinishNode events.
  if stack.length() != 1 {
    abort(
      "build_tree: unbalanced StartNode — missing FinishNode(s), stack=" +
      stack.length().to_string(),
    )
  }
  CstNode::new(root_kind, stack[0], trivia_kind~)
}
