///|
/// An exact, immutable grammar-entry context. Tags distinguish grammar-defined
/// meanings; a parent shares enclosing context without copying or hashing it.
/// Use with a LanguageSpec that enables track_reuse_dependencies.
pub struct ReuseContext {
  priv tag : Int
  priv value : Int
  priv parent : ReuseContext?
} derive(Eq)

///|
pub extend ReuseContext with Eq::{equal, not_equal}

///|
pub fn ReuseContext::new(
  tag : Int,
  value : Int,
  parent? : ReuseContext? = None,
) -> ReuseContext {
  { tag, value, parent, }
}

///|
/// Parser-owned dependency information for one accepted CST snapshot. Positions
/// in the occurrence tree are relative; unchanged subtrees are shared without
/// retaining source text or changing CST equality.
pub struct ReuseDependencies {
  priv root : NodeDependency
  priv pending_edit : Edit?
}

///|
priv struct NodeDependency {
  kind : @seam.RawKind
  text_len : Int
  context : ReuseContext?
  read_start : Int
  read_end : Int
  children : Array[DependencyChild]
}

///|
priv struct DependencyChild {
  offset : Int
  // Only interpreted while the containing frame is being built. A reused
  // subtree receives a new placement event; its immutable children stay shared.
  event : Int
  node : NodeDependency
}

///|
priv struct DependencyFrame {
  kind : @seam.RawKind
  start : Int
  event : Int
  context : ReuseContext?
  mut read_start : Int
  mut read_end : Int
  children : Array[DependencyChild]
}

///|
priv struct DependencyBuilder {
  mut frames : Array[DependencyFrame]
  marks : Map[Int, Int]
  mark_events : Array[Int]
  mut observation : DependencyObservation?
  mut next_observation : Int
  mut pending_token_start : Int
  mut pending_token_end : Int
}

///|
priv struct DependencyCheckpoint {
  frames : Array[(DependencyFrame, Int)]
  marks_len : Int
  observation : DependencyObservation
}

///|
priv struct DependencyObservation {
  id : Int
  parent : DependencyObservation?
  mut start : Int
  mut end : Int
}

///|
fn DependencyObservation::observe(
  self : DependencyObservation,
  start : Int,
  end : Int,
) -> Unit {
  self.start = self.start.min(start)
  self.end = self.end.max(end)
}

///|
fn DependencyBuilder::new(kind : @seam.RawKind) -> DependencyBuilder {
  {
    frames: [
      {
        kind,
        start: 0,
        event: -1,
        context: None,
        read_start: 0,
        read_end: 0,
        children: [],
      },
    ],
    marks: {},
    mark_events: [],
    observation: None,
    next_observation: 0,
    pending_token_start: 2147483647,
    pending_token_end: -1,
  }
}

///|
/// Batch token-index observations while the active frame/observer is unchanged.
/// Convert only their extrema before either changes, not on every grammar peek.
fn DependencyBuilder::flush_tokens(
  self : DependencyBuilder,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
) -> Unit {
  if self.pending_token_end >= 0 {
    self.observe(
      get_start(self.pending_token_start),
      get_end(self.pending_token_end),
    )
    self.pending_token_start = 2147483647
    self.pending_token_end = -1
  }
}

///|
fn DependencyBuilder::current(self : DependencyBuilder) -> DependencyFrame {
  self.frames[self.frames.length() - 1]
}

///|
fn DependencyFrame::observe(
  self : DependencyFrame,
  start : Int,
  end : Int,
) -> Unit {
  self.read_start = self.read_start.min(start)
  self.read_end = self.read_end.max(end)
}

///|
fn DependencyBuilder::observe(
  self : DependencyBuilder,
  start : Int,
  end : Int,
) -> Unit {
  self.current().observe(start, end)
  match self.observation {
    Some(observer) => observer.observe(start, end)
    None => ()
  }
}

///|
fn DependencyBuilder::start_node(
  self : DependencyBuilder,
  kind : @seam.RawKind,
  start : Int,
  event : Int,
  context : ReuseContext?,
) -> Unit {
  self.frames.push({
    kind,
    start,
    event,
    context,
    read_start: start,
    read_end: start,
    children: [],
  })
}

///|
fn DependencyBuilder::place(
  self : DependencyBuilder,
  node : NodeDependency,
  start : Int,
  event : Int,
) -> Unit {
  let parent = self.current()
  self.observe(start + node.read_start, start + node.read_end)
  parent.children.push({ offset: start - parent.start, event, node, })
}

///|
fn DependencyBuilder::finish_node(self : DependencyBuilder, end : Int) -> Unit {
  guard self.frames.length() > 1 else { return }
  let frame = self.frames.pop().unwrap()
  frame.observe(frame.start, end)
  self.place(
    {
      kind: frame.kind,
      text_len: end - frame.start,
      context: frame.context,
      read_start: frame.read_start - frame.start,
      read_end: frame.read_end - frame.start,
      children: frame.children,
    },
    frame.start,
    frame.event,
  )
}

///|
fn DependencyBuilder::mark(
  self : DependencyBuilder,
  event : Int,
  start : Int,
) -> Unit {
  self.marks[event] = start
  self.mark_events.push(event)
}

///|
fn DependencyBuilder::start_at(
  self : DependencyBuilder,
  mark : Int,
  kind : @seam.RawKind,
  context : ReuseContext?,
) -> Unit {
  let parent = self.current()
  let start = self.marks.get(mark).unwrap_or(parent.start)
  let children : Array[DependencyChild] = []
  let mut first = parent.children.length()
  while first > 0 && parent.children[first - 1].event >= mark {
    first -= 1
  }
  for i in first..<parent.children.length() {
    let child = parent.children[i]
    children.push({
      offset: parent.start + child.offset - start,
      event: child.event,
      node: child.node,
    })
  }
  parent.children.truncate(first)
  // Retroactive wrappers include observations made before they were opened.
  // The containing frame is a conservative envelope; it also covers failed
  // lookahead that emitted no children between mark() and start_at().
  self.frames.push({
    kind,
    start,
    event: mark,
    context,
    read_start: parent.read_start.min(start),
    read_end: parent.read_end.max(start),
    children,
  })
}

///|
fn DependencyBuilder::checkpoint(
  self : DependencyBuilder,
) -> DependencyCheckpoint {
  let observation = {
    id: self.next_observation,
    parent: self.observation,
    start: 2147483647,
    end: -1,
  }
  self.next_observation += 1
  self.observation = Some(observation)
  {
    frames: self.frames.map(frame => (frame, frame.children.length())),
    marks_len: self.mark_events.length(),
    observation,
  }
}

///|
fn DependencyBuilder::restore(
  self : DependencyBuilder,
  checkpoint : DependencyCheckpoint,
) -> Unit {
  // Reads are evidence, not speculative effects. In particular an unfinished
  // node in a failed branch must not lose the observation that rejected it.
  let observed = checkpoint.observation
  for current = self.observation
      current is Some(observer)
      current = observer.parent {
    if observer.id < observed.id {
      break
    }
    observed.observe(observer.start, observer.end)
  }
  if observed.start <= observed.end {
    checkpoint.frames[checkpoint.frames.length() - 1].0.observe(
      observed.start,
      observed.end,
    )
  }
  // Keep a directly restored checkpoint observing subsequent attempts. The
  // lookahead combinator explicitly releases its private checkpoint afterward.
  self.observation = Some(observed)
  self.frames = checkpoint.frames.map(pair => {
    pair.0.children.truncate(pair.1)
    pair.0
  })
  while self.mark_events.length() > checkpoint.marks_len {
    let event = self.mark_events.pop().unwrap()
    self.marks.remove(event)
  }
}

///|
fn DependencyBuilder::end_lookahead(
  self : DependencyBuilder,
  checkpoint : DependencyCheckpoint,
) -> Unit {
  let observed = checkpoint.observation
  self.observation = observed.parent
  match observed.parent {
    Some(parent) => parent.observe(observed.start, observed.end)
    None => ()
  }
}

///|
fn DependencyBuilder::finish(
  self : DependencyBuilder,
  kind : @seam.RawKind,
  text_len : Int,
) -> ReuseDependencies {
  let frame = self.frames[0]
  let root = if frame.children.length() == 1 &&
    frame.children[0].offset == 0 &&
    frame.children[0].node.kind == kind &&
    frame.children[0].node.text_len == text_len {
    let child = frame.children[0].node
    {
      ..child,
      read_start: child.read_start.min(frame.read_start),
      read_end: child.read_end.max(frame.read_end),
    }
  } else {
    {
      kind,
      text_len,
      context: None,
      read_start: frame.read_start,
      read_end: frame.read_end.max(text_len),
      children: frame.children,
    }
  }
  { root, pending_edit: None, }
}

///|
/// Preserve unaffected dependency subtrees after a grammar-approved block splice.
/// Changed occurrences remain uncertified until parsed again. Pending edits are
/// coalesced into one conservative envelope, so local edits do not walk the tree
/// or accumulate an unbounded history. Does not mutate the previous snapshot.
pub fn ReuseDependencies::after_edit(
  self : ReuseDependencies,
  edit : Edit,
) -> ReuseDependencies {
  { root: self.root, pending_edit: Some(self.combined_edit(edit)), }
}

///|
fn ReuseDependencies::combined_edit(
  self : ReuseDependencies,
  edit : Edit,
) -> Edit {
  match self.pending_edit {
    None => edit
    Some(previous) => {
      let start = previous.start.min(edit.start)
      let old_end = previous.old_end().max(edit.old_end() - previous.delta())
      let old_len = old_end - start
      Edit::new(start, old_len, old_len + previous.delta() + edit.delta())
    }
  }
}

///|
fn ReuseDependencies::base_offset(
  self : ReuseDependencies,
  offset : Int,
) -> Int? {
  match self.pending_edit {
    None => Some(offset)
    Some(edit) =>
      if offset < edit.start {
        Some(offset)
      } else if offset >= edit.new_end() {
        Some(offset - edit.delta())
      } else {
        None
      }
  }
}

///|
fn NodeDependency::has_nested_match(
  self : NodeDependency,
  kind : @seam.RawKind,
) -> Bool {
  for node = self {
    let mut index = node.children.length() - 1
    while index >= 0 && node.children[index].node.text_len == 0 {
      index -= 1
    }
    guard index >= 0 else { break false }
    let child = node.children[index]
    guard child.offset == 0 && child.node.text_len == node.text_len else {
      break false
    }
    if child.node.kind == kind {
      break true
    }
    continue child.node
  }
}

///|
fn NodeDependency::find(
  self : NodeDependency,
  offset : Int,
  kind : @seam.RawKind,
  text_len : Int,
) -> NodeDependency? {
  if offset == 0 && self.kind == kind && self.text_len == text_len {
    // Same-kind wrappers can share a consumed span. Without an unambiguous
    // occurrence, do not certify a descendant using its ancestor's context.
    guard !self.has_nested_match(kind) else { return None }
    return Some(self)
  }
  let end = offset + text_len
  let mut lo = 0
  let mut hi = self.children.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let child = self.children[mid]
    if child.offset + child.node.text_len < end {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  guard lo < self.children.length() else { return None }
  let child = self.children[lo]
  guard child.offset <= offset else { return None }
  child.node.find(offset - child.offset, kind, text_len)
}

///|
/// Scope complete grammar-entry state for every nested node, including nodes
/// whose own helpers do not explicitly receive that state. Parent links are
/// explicit; use current_reuse_context to extend inherited state.
pub fn[T, K, R] ParserContext::with_reuse_context(
  self : ParserContext[T, K],
  context : ReuseContext,
  body : () -> R,
) -> R {
  let previous = self.reuse_context
  self.reuse_context = Some(context)
  let result = body()
  self.reuse_context = previous
  result
}

///|
/// Declare a source observation outside token accessor views. The offsets must
/// be a valid code-unit range in the current source. A zero-width range observes
/// a boundary (including EOF); insertion there invalidates the dependency.
pub fn[T, K] ParserContext::observe_source_range(
  self : ParserContext[T, K],
  start : Int,
  end : Int,
) -> Unit {
  match self.dependency_builder {
    Some(builder) => builder.observe(start, end)
    None => ()
  }
}

///|
fn[T, K] ParserContext::observe_token(
  self : ParserContext[T, K],
  pos : Int,
) -> Unit {
  match self.dependency_builder {
    None => ()
    Some(builder) =>
      if pos >= 0 && pos < self.token_count {
        builder.pending_token_start = builder.pending_token_start.min(pos)
        builder.pending_token_end = builder.pending_token_end.max(pos)
      } else {
        let end = self.source.length()
        builder.observe(end, end)
      }
  }
}

///|
fn[T, K] ParserContext::source_position(self : ParserContext[T, K]) -> Int {
  if self.position < self.token_count {
    (self.get_start)(self.position)
  } else {
    self.source.length()
  }
}

///|
fn[T, K] ReuseCursor::dependencies_match(
  self : ReuseCursor[T, K],
  node : @seam.CstNode,
  old_offset : Int,
  context : ReuseContext?,
) -> Bool {
  self.last_dependency = None
  if !self.spec.track_reuse_dependencies {
    return true
  }
  guard node.text_len() > 0 else { return false }
  guard self.dependencies is Some(dependencies) &&
    self.dependency_damage is Some(damage) else {
    return false
  }
  guard dependencies.base_offset(old_offset) is Some(base_offset) else {
    return false
  }
  guard dependencies.root.find(base_offset, node.kind(), node.text_len())
    is Some(candidate) else {
    return false
  }
  guard candidate.context == context else { return false }
  // Closed observation boundaries deliberately include EOF and insertions at
  // the last observed offset. Consumed-span/token checks still run separately.
  guard base_offset + candidate.read_end < damage.start ||
    base_offset + candidate.read_start > damage.old_end() else {
    return false
  }
  self.last_dependency = Some(candidate)
  true
}

///|
fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] ReuseCursor::try_reuse_in_context(
  self : ReuseCursor[T, K],
  kind : @seam.RawKind,
  offset : Int,
  token_pos : Int,
  context : ReuseContext?,
) -> @seam.CstNode? {
  match self.try_reuse_checked(kind, offset, token_pos, context~) {
    Ok(node) => Some(node)
    Err(_) => None
  }
}

///|
/// Return the immutable ambient key for constructing a child entry context.
/// with_reuse_context replaces the complete key; parent links are explicit.
pub fn[T, K] ParserContext::current_reuse_context(
  self : ParserContext[T, K],
) -> ReuseContext? {
  self.reuse_context
}
