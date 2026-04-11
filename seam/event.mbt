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
  /// Attach a pre-built CST subtree directly, skipping serialize/deserialize.
  /// Used by incremental parsers to avoid re-emitting events for reused nodes.
  /// Builders re-intern the node through their interner(s) to preserve contracts.
  ReuseNode(CstNode)
} derive(Debug, Eq)

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
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  build_tree(
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
  build_tree_fully_interned(
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
  build_tree_interned(
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
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode raise EventStreamError {
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      StartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      FinishNode => {
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
      Token(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      ReuseNode(node) => {
        let interned = CstElement::Node(node).map(
          elem => {
            match elem {
              Token(t) => Token(interner.intern_token(t.kind, t.text))
              _ => elem
            }
          },
          trivia_kind~,
          error_kind~,
          incomplete_kind~,
        )
        match stack.last() {
          Some(parent) => parent.push(interned)
          None => raise EventStreamError::OrphanedEvent
        }
      }
      Tombstone => ()
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
        let interned = interner.intern_token(t.kind, t.text)
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
  let stack : Array[Array[CstElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      StartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      FinishNode => {
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
      Token(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      ReuseNode(node) => {
        let interned = re_intern_subtree(
          node, interner, node_interner, trivia_kind, error_kind, incomplete_kind,
        )
        match stack.last() {
          Some(parent) => parent.push(Node(interned))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      Tombstone => ()
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
      Token(kind, text) => {
        let token = CstToken::new(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => raise EventStreamError::OrphanedEvent
        }
      }
      ReuseNode(node) => {
        let rebuilt = CstElement::Node(node).map(
          elem => elem,
          trivia_kind~,
          error_kind~,
          incomplete_kind~,
        )
        match stack.last() {
          Some(parent) => parent.push(rebuilt)
          None => raise EventStreamError::OrphanedEvent
        }
      }
      // Unclaimed marks are expected and intentionally ignored.
      Tombstone => ()
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
