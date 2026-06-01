// settings_attachment.mbt — pure derived cell + imperative last-good policy.
//
// This is the checked counterpart of the `nocheck` template in
// `docs/api/last-good-semantic-attachment.md`. The reactive layer is a PURE
// `@incr.Derived` of the parser's published views; the last-good retention and
// stable-identity commit policy live in the imperative `settle` step, never
// inside the derived closure. See the loom + incr skills for why mutating the
// tracker / last_good inside a `Derived` body is the antipattern this example
// exists to demonstrate the fix for.

///|
/// Outcome of the pure projection attempt for one parser snapshot.
priv enum ProjectionOutcome {
  ParseFailed(Array[String])
  ProjectionFailed(Array[String])
  Projected(Array[RawSetting])
} derive(Eq)

///|
/// The pure derived value: the projected source plus its projection outcome.
/// Mutates nothing — no tracker, no last_good, no cached state.
/// `Eq` is required because `@incr.Scope::derived` change-detects its value.
priv struct ProjectionAttempt {
  source : String
  outcome : ProjectionOutcome
} derive(Eq)

///|
/// Pure projection of one parser snapshot. Reads only the parser's published
/// views (inside-graph `get_or_abort` reads) and returns a value. This is the
/// body of the reactive `Derived` — it never constructs an `ImperativeParser`,
/// never mutates the tracker, last_good, or any cached field.
fn compute_attempt(parser : @loom.Parser[@json.JsonValue]) -> ProjectionAttempt {
  let source = parser.source().get_or_abort()
  let diagnostics = parser.diagnostics().get_or_abort()
  // Parser diagnostics dominate: a syntactically broken document never reaches
  // the semantic projection.
  if !diagnostics.is_empty() {
    return { source, outcome: ParseFailed(diagnostics.format()) }
  }
  let syntax = parser.syntax_tree().get_or_abort()
  match project_settings(syntax) {
    Ok(raws) => { source, outcome: Projected(raws) }
    Err(messages) => { source, outcome: ProjectionFailed(messages) }
  }
}

///|
/// Health of the latest settings projection, kept honest per
/// `incr/docs/design/specs/2026-05-28-honest-read-error-ownership.md`:
/// `GraphBlocked` is a boundary `ReadError`, distinct from a parser or
/// projection diagnostic — folding it into either would lose that split.
pub enum SettingsState {
  Current
  ParserBlocked
  ProjectionBlocked
  GraphBlocked
} derive(Eq)

///|
pub impl Show for SettingsState with fn output(self, logger) {
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
/// A last-good semantic projection attached to a unified JSON `Parser`.
///
/// Owns the parser, the reactive `Scope`/`Watch` GC anchor, the loom-owned
/// `ProjectionIdentityTracker`, and the cached public state (current source,
/// current result, last-good document).
pub struct SettingsAttachment {
  priv parser : @loom.Parser[@json.JsonValue]
  priv scope : @incr.Scope
  priv watch : @incr.Watch[ProjectionAttempt]
  priv tracker : @loom.ProjectionIdentityTracker[String]
  priv mut current_source : String
  priv mut state : SettingsState
  priv mut current : Result[SettingsDoc, String]
  priv mut last_good : SettingsDoc?
}

///|
/// Attach a last-good settings projection over `initial_source`, settling once.
///
/// The parser is built *outside* the reactive closure; the closure only reads
/// its published views. A persistent `Watch` anchors the chain as a GC root.
pub fn SettingsAttachment::SettingsAttachment(
  initial_source : String,
) -> SettingsAttachment {
  let parser = @loom.new_parser(initial_source, @json.json_grammar)
  let scope = @incr.Scope::new(parser.runtime())
  let derived = scope.derived(
    fn() { compute_attempt(parser) },
    label="settings_projection",
  )
  let watch = scope.add_watch(derived.watch())
  let self = {
    parser,
    scope,
    watch,
    tracker: @loom.ProjectionIdentityTracker::new(),
    current_source: initial_source,
    state: ParserBlocked,
    current: Err("not yet settled"),
    last_good: None,
  }
  // Settling reads the watch once, which also primes the GC anchor.
  self.settle(None, None)
  self
}

///|
/// The imperative last-good policy. Reads the pure attempt at the graph boundary
/// (`watch.read()`), then advances cached state. This is the *only* place the
/// tracker and last_good change — never inside the derived closure.
fn SettingsAttachment::settle(
  self : SettingsAttachment,
  source_before_edit : String?,
  edit : @core.Edit?,
) -> Unit {
  let attempt = match self.watch.read() {
    Ok(a) => a
    // Boundary graph-health failure (cycle/disposal): neither a parser nor a
    // projection diagnostic. Retain last_good; do not touch the tracker.
    Err(read_error) => {
      self.state = GraphBlocked
      self.current = Err(
        "settings graph unavailable: " + read_error.format_path(),
      )
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
      self.current = Err(join_messages(messages))
    }
    ProjectionFailed(messages) => {
      self.tracker.record_failed_input_with_optional_edit(
        attempt.source,
        source_before_edit,
        edit,
      )
      self.state = ProjectionBlocked
      self.current = Err(join_messages(messages))
    }
    Projected(raws) => {
      let allocator = match self.tracker.baseline() {
        Some(baseline) =>
          @loom.ProjectionStringIdAllocator::from_baseline(
            baseline, make_setting_id,
          )
        None => @loom.ProjectionStringIdAllocator::new(make_setting_id)
      }
      let leaves = raws.map(raw_setting_to_leaf)
      // Preview alignment against the last-good baseline (no commit yet).
      let stable = self.tracker.realign_success_with_optional_edit(
        attempt.source,
        leaves,
        fn(leaf) { allocator.allocate(leaf) },
        edit,
      )
      let settings : Array[Setting] = []
      for i = 0; i < raws.length(); i = i + 1 {
        settings.push(
          Setting(id=stable[i].id, key=raws[i].key, value=raws[i].value),
        )
      }
      let doc = SettingsDoc(settings)
      // Commit only after the semantic document is built — the sole
      // baseline-advancing call, reachable only on projection success.
      self.tracker.commit_success(attempt.source, stable)
      self.state = Current
      self.current = Ok(doc)
      self.last_good = Some(doc)
    }
  }
}

///|
/// Allocate the public stable id for a freshly-projected setting.
///
/// Ids are **opaque and allocation-order based** (`setting#0`, `setting#1`, …),
/// deliberately *not* derived from the key. That is what makes
/// `ProjectionIdentityTracker` reuse observable: an unchanged setting keeps the
/// low number it was first allocated, while a setting newly appearing inside an
/// edit window gets the next free number — so a downstream UI can keep widget
/// state attached to a setting even when keys are inserted/removed around it. A
/// key-derived id would make preservation indistinguishable from recomputation.
///
/// `make_id` is key-independent here, so the allocator's collision-bumping over
/// its `used` set turns the per-key `occurrence` into a global sequence: the nth
/// distinct id allocated against a fresh/seeded allocator is the nth free
/// `setting#k`.
fn make_setting_id(_key : String, occurrence : Int) -> String {
  "setting#" + occurrence.to_string()
}

///|
fn join_messages(messages : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, m in messages {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_string(m)
  }
  buf.to_string()
}

///|
/// Health of the latest projection.
pub fn SettingsAttachment::state(self : SettingsAttachment) -> SettingsState {
  self.state
}

///|
/// The current settings document. `Ok` only when `state()` is `Current`;
/// stale data after a failure is available via `last_good()`.
pub fn SettingsAttachment::current_result(
  self : SettingsAttachment,
) -> Result[SettingsDoc, String] {
  self.current
}

///|
/// The last successfully projected settings document, retained across malformed
/// or projection-invalid intermediate input. `None` until the first success.
pub fn SettingsAttachment::last_good(self : SettingsAttachment) -> SettingsDoc? {
  self.last_good
}

///|
/// Apply an incremental edit relative to the current source, then re-settle.
/// The exact `edit` is forwarded to the tracker so unchanged keys keep their
/// ids through the edit window.
pub fn SettingsAttachment::apply_edit(
  self : SettingsAttachment,
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  let source_before_edit = self.current_source
  self.parser.apply_edit(edit, new_source)
  self.current_source = new_source
  self.settle(Some(source_before_edit), Some(edit))
}

///|
/// Replace the source wholesale, then re-settle. No edit is supplied, so the
/// tracker falls back to a source diff for identity realignment.
pub fn SettingsAttachment::set_source(
  self : SettingsAttachment,
  new_source : String,
) -> Unit {
  self.parser.set_source(new_source)
  self.current_source = new_source
  self.settle(None, None)
}

///|
/// Dispose the reactive scope (GC anchor + owned cells). Does not touch the
/// parser. Idempotent.
pub fn SettingsAttachment::dispose(self : SettingsAttachment) -> Unit {
  self.scope.dispose()
}
