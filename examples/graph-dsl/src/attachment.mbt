///|
priv enum GraphProjectionOutcome {
  ParseFailed(Array[String])
  ProjectionFailed(Array[String])
  Projected(RawGraphProjection)
} derive(Eq)

///|
priv struct GraphProjectionAttempt {
  source : String
  outcome : GraphProjectionOutcome
} derive(Eq)

///|
fn compute_graph_attempt(
  parser : @loom.Parser[GraphAst],
) -> GraphProjectionAttempt {
  let source = parser.source().get_or_abort()
  let diagnostics = parser.diagnostics().get_or_abort()
  if !diagnostics.is_empty() {
    return { source, outcome: ParseFailed(diagnostics.format()) }
  }
  let syntax = parser.syntax_tree().get_or_abort()
  match project_graph_raw(source, syntax) {
    Ok(raw) => { source, outcome: Projected(raw) }
    Err(messages) => { source, outcome: ProjectionFailed(messages) }
  }
}

///|
pub enum GraphAttachmentState {
  Current
  ParserBlocked
  ProjectionBlocked
  GraphBlocked
} derive(Eq, Debug)

///|
pub impl Show for GraphAttachmentState with fn output(self, logger) {
  logger.write_string(
    match self {
      Current => "Current"
      ParserBlocked => "ParserBlocked"
      ProjectionBlocked => "ProjectionBlocked"
      GraphBlocked => "GraphBlocked"
    },
  )
}

///|
priv struct GraphListener {
  id : Int
  callback : () -> Unit
}

///|
pub struct GraphAttachment {
  priv parser : @loom.Parser[GraphAst]
  priv scope : @incr.Scope
  priv watch : @incr.Watch[GraphProjectionAttempt]
  priv tracker : @loom.ProjectionIdentityTracker[String]
  priv mut current_source : String
  priv mut state : GraphAttachmentState
  priv mut diagnostics : Array[String]
  priv mut current : Result[GraphDoc, String]
  priv mut last_good : GraphDoc?
  priv mut listeners : Array[GraphListener]
  priv mut next_listener_id : Int
}

///|
pub fn GraphAttachment::GraphAttachment(
  initial_source : String,
) -> GraphAttachment {
  let parser = @loom.new_parser(initial_source, graph_grammar)
  let scope = @incr.Scope::new(parser.runtime())
  let derived = scope.derived(
    fn() { compute_graph_attempt(parser) },
    label="graph_projection",
  )
  let watch = scope.add_watch(derived.watch())
  let self = {
    parser,
    scope,
    watch,
    tracker: @loom.ProjectionIdentityTracker::new(),
    current_source: initial_source,
    state: ParserBlocked,
    diagnostics: [],
    current: Err("not yet settled"),
    last_good: None,
    listeners: [],
    next_listener_id: 0,
  }
  self.settle(None, None)
  self
}

///|
fn GraphAttachment::settle(
  self : GraphAttachment,
  source_before_edit : String?,
  edit : @loom.Edit?,
) -> Unit {
  // Single exit so `notify_listeners` always runs, including the watch-read
  // error path (which previously returned early).
  match self.watch.read() {
    Err(read_error) => {
      let message = "graph projection unavailable: " + read_error.format_path()
      self.state = GraphBlocked
      self.diagnostics = [message]
      self.current = Err(message)
    }
    Ok(attempt) =>
      match attempt.outcome {
        ParseFailed(messages) => {
          self.tracker.record_failed_input_with_optional_edit(
            attempt.source,
            source_before_edit,
            edit,
          )
          self.state = ParserBlocked
          self.diagnostics = messages.copy()
          self.current = Err(messages.join("; "))
        }
        ProjectionFailed(messages) => {
          self.tracker.record_failed_input_with_optional_edit(
            attempt.source,
            source_before_edit,
            edit,
          )
          self.state = ProjectionBlocked
          self.diagnostics = messages.copy()
          self.current = Err(messages.join("; "))
        }
        Projected(raw) => {
          let allocator = match self.tracker.baseline() {
            Some(baseline) =>
              @loom.ProjectionStringIdAllocator::from_baseline(
                baseline, make_node_id,
              )
            None => @loom.ProjectionStringIdAllocator::new(make_node_id)
          }
          let leaves = raw.nodes.map(raw_node_to_leaf)
          let stable = self.tracker.realign_success_with_optional_edit(
            attempt.source,
            leaves,
            fn(leaf) { allocator.allocate(leaf) },
            edit,
          )
          let doc = build_doc_from_stable(raw, stable)
          self.tracker.commit_success(attempt.source, stable)
          self.state = Current
          self.diagnostics = []
          self.current = Ok(doc)
          self.last_good = Some(doc)
        }
      }
  }
  self.notify_listeners()
}

///|
pub fn GraphAttachment::state(self : GraphAttachment) -> GraphAttachmentState {
  self.state
}

///|
pub fn GraphAttachment::current_result(
  self : GraphAttachment,
) -> Result[GraphDoc, String] {
  self.current
}

///|
pub fn GraphAttachment::diagnostics(self : GraphAttachment) -> Array[String] {
  self.diagnostics.copy()
}

///|
pub fn GraphAttachment::last_good(self : GraphAttachment) -> GraphDoc? {
  self.last_good
}

///|
pub fn GraphAttachment::apply_edit(
  self : GraphAttachment,
  edit : @loom.Edit,
  new_source : String,
) -> Unit {
  let source_before_edit = self.current_source
  self.parser.apply_edit(edit, new_source)
  self.current_source = new_source
  self.settle(Some(source_before_edit), Some(edit))
}

///|
pub fn GraphAttachment::set_source(
  self : GraphAttachment,
  new_source : String,
) -> Unit {
  self.parser.set_source(new_source)
  self.current_source = new_source
  self.settle(None, None)
}

///|
/// Subscribe to settle notifications. `listener` is invoked — with no payload —
/// at the end of every `settle`, i.e. after each `apply_edit` / `set_source`
/// has updated `state` / `diagnostics` / `current` / `last_good`, regardless of
/// the projection outcome. It fires for all mutations whatever their origin, so
/// consumers should pull the current value (`current_result` / source) on the
/// ping and dedupe themselves if they only care about real changes.
///
/// The listener runs synchronously inside `apply_edit` / `set_source`; it must
/// not mutate this attachment (doing so would re-enter `settle`). The returned
/// handle detaches the listener via `unsubscribe`.
pub fn GraphAttachment::subscribe(
  self : GraphAttachment,
  listener : () -> Unit,
) -> GraphAttachmentSubscription {
  let id = self.next_listener_id
  self.next_listener_id = id + 1
  self.listeners.push({ id, callback: listener })
  { attachment: self, id }
}

///|
/// Notify every subscribed listener that the attachment has re-settled.
/// Iterates a snapshot so a listener may detach itself without disturbing the
/// in-progress notification.
fn GraphAttachment::notify_listeners(self : GraphAttachment) -> Unit {
  for listener in self.listeners.copy() {
    (listener.callback)()
  }
}

///|
/// Handle returned by `GraphAttachment::subscribe`. `unsubscribe` detaches the
/// listener; it is idempotent and safe to call after the attachment is
/// disposed.
pub struct GraphAttachmentSubscription {
  priv attachment : GraphAttachment
  priv id : Int
}

///|
pub fn GraphAttachmentSubscription::unsubscribe(
  self : GraphAttachmentSubscription,
) -> Unit {
  self.attachment.listeners = self.attachment.listeners.filter(fn(listener) {
    listener.id != self.id
  })
}

///|
pub fn GraphAttachment::dispose(self : GraphAttachment) -> Unit {
  // Drop listeners first so a post-dispose notification can never fire.
  self.listeners = []
  self.scope.dispose()
}
