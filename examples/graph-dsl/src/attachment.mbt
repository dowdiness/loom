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
  let attempt = match self.watch.read() {
    Ok(attempt) => attempt
    Err(read_error) => {
      let message = "graph projection unavailable: " + read_error.format_path()
      self.state = GraphBlocked
      self.diagnostics = [message]
      self.current = Err(message)
      return
    }
  }
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
pub fn GraphAttachment::dispose(self : GraphAttachment) -> Unit {
  self.scope.dispose()
}
