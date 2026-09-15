// settings_attachment.mbt — parser-owned semantic coordination for settings.
//
// The semantic callback below is deliberately a complete candidate builder:
// parser diagnostics, projection validation, identity realignment, and model
// construction all happen before one atomic `Accept`. The parser and semantic
// analysis own transition metadata, pending input, and the accepted baseline;
// this attachment only translates completed observations to the example's
// public API.

///|
/// The immutable semantic model published by a successful candidate.
///
/// Keeping the document and its accepted identity baseline together means a
/// later candidate always realigns against the exact last accepted semantic
/// state. `SettingsDoc` and `ProjectionIdentityBaseline` both defend their
/// backing arrays with copies.
priv struct SettingsModel {
  doc : SettingsDoc
  baseline : @loom.ProjectionIdentityBaseline[String]
}

///|
/// Language-owned rejection data. Candidate exceptions are not represented
/// here; the semantic core reports those separately as `CandidateFailed`.
priv enum SettingsRejection {
  Parser(Array[String])
  Projection(Array[String])
}

///|
/// Build a stable semantic model from a successful raw projection.
///
/// The allocator is intentionally baseline-local: it reserves IDs from the
/// previous accepted baseline for this candidate and is discarded afterwards.
/// No lifetime-monotonic counter is introduced by the attachment.
fn build_settings_model(
  previous : SettingsModel?,
  source : String,
  raws : Array[RawSetting],
  edit : @core.Edit?,
) -> SettingsModel {
  let leaves = raws.map(raw_setting_to_leaf)
  let reserved : Map[String, Bool] = Map([])
  if previous is Some(model) {
    for leaf in model.baseline.leaves() {
      reserved[leaf.id] = true
    }
  }
  // All keys share one ID namespace. Scan it once per candidate, not per key.
  // Generated numbers are never revisited, so only baseline IDs need reserving.
  let mut next = 0
  let allocate = (_leaf : @loom.ProjectionLeaf) => {
    let mut id = make_setting_id(next)
    while reserved.contains(id) {
      next += 1
      id = make_setting_id(next)
    }
    next += 1
    id
  }
  let stable = match previous {
    Some(model) =>
      @loom.realign_projection_identities_with_optional_edit(
        model.baseline,
        source,
        leaves,
        allocate,
        edit,
      )
    None =>
      leaves.map(leaf => {
        let id = allocate(leaf)
        @loom.StableProjectionLeaf::new(leaf.start, leaf.end, leaf.key, id)
      })
  }
  let settings = Array::makei(raws.length(), i => {
    Setting(id=stable[i].id, key=raws[i].key, value=raws[i].value)
  })
  {
    doc: SettingsDoc(settings),
    baseline: @loom.ProjectionIdentityBaseline::new(source, stable),
  }
}

///|
/// Construct one complete settings candidate from a parser semantic snapshot.
///
/// The registered callback uses this builder. It reads the captured snapshot,
/// never reparses the source, and returns a language rejection rather than
/// mutating retained state.
fn project_settings_candidate(
  previous : @loom.SemanticAccepted[SettingsModel]?,
  snapshot : @loom.SemanticSnapshot,
  change : @loom.SemanticChange,
) -> @loom.SemanticDecision[SettingsModel, SettingsRejection] {
  let diagnostics = snapshot.diagnostics()
  if !diagnostics.is_empty() {
    return @loom.SemanticDecision::Reject(Parser(diagnostics.format()))
  }
  match project_settings(snapshot.syntax()) {
    Err(messages) => @loom.SemanticDecision::Reject(Projection(messages))
    Ok(raws) => {
      let previous_model = match previous {
        Some(accepted) => Some(accepted.value())
        None => None
      }
      let model = build_settings_model(
        previous_model,
        snapshot.source(),
        raws,
        change.edit(),
      )
      @loom.SemanticDecision::Accept(model)
    }
  }
}

///|
/// Health of the latest semantic observation.
pub enum SettingsState {
  Current
  ParserBlocked
  ProjectionBlocked
  CandidateBlocked
  GraphBlocked
} derive(Eq)

///|
pub impl Show for SettingsState with fn output(self, logger) {
  logger.write_string(
    match self {
      Current => "Current"
      ParserBlocked => "ParserBlocked"
      ProjectionBlocked => "ProjectionBlocked"
      CandidateBlocked => "CandidateBlocked"
      GraphBlocked => "GraphBlocked"
    },
  )
}

///|
/// A parser-attached last-good settings projection.
///
/// The parser owns the current source/syntax and the semantic analysis owns
/// accepted values, identity baselines, pending metadata, and graph lifetime.
/// This facade stores neither a tracker nor a second cache.
pub struct SettingsAttachment {
  priv parser : @loom.Parser[@json.JsonValue]
  priv analysis : @loom.SemanticAnalysis[SettingsModel, SettingsRejection]
}

///|
/// Attach a semantic settings projection over `initial_source`.
///
/// Construction registers and primes the semantic watch but does not execute
/// the callback until this constructor performs its explicit initial read.
pub fn SettingsAttachment::SettingsAttachment(
  source_id : @core.SourceId,
  initial_source : String,
) -> SettingsAttachment raise Failure {
  let parser = @loom.new_parser(source_id, initial_source, @json.json_grammar)
  let analysis = parser.attach_semantic((previous, snapshot, change) => {
    project_settings_candidate(previous, snapshot, change)
  })
  let self = { parser, analysis, }
  ignore(self.analysis.read())
  self
}

///|
/// Return the completed semantic observation without evaluating the graph.
///
/// The constructor completes its initial read before exposing the facade.
fn SettingsAttachment::observation(
  self : SettingsAttachment,
) -> @loom.SemanticObservation[SettingsModel, SettingsRejection] {
  self.analysis.observation().unwrap()
}

///|
/// Health of the latest semantic projection.
pub fn SettingsAttachment::state(self : SettingsAttachment) -> SettingsState {
  let observation = self.observation()
  match observation.status() {
    @loom.SemanticStatus::Current => Current
    @loom.SemanticStatus::Rejected(reason) =>
      match reason {
        Parser(_) => ParserBlocked
        Projection(_) => ProjectionBlocked
      }
    @loom.SemanticStatus::CandidateFailed(_) => CandidateBlocked
    @loom.SemanticStatus::GraphFailed(_) => GraphBlocked
  }
}

///|
/// The current settings document. `Ok` only when the latest observation is
/// `Current`; retained stale data remains available through `last_good()`.
pub fn SettingsAttachment::current_result(
  self : SettingsAttachment,
) -> Result[SettingsDoc, String] {
  let observation = self.observation()
  match observation.status() {
    @loom.SemanticStatus::Current =>
      Ok(observation.accepted().unwrap().value().doc)
    @loom.SemanticStatus::Rejected(Parser(messages)) => Err(messages.join("; "))
    @loom.SemanticStatus::Rejected(Projection(messages)) =>
      Err(messages.join("; "))
    @loom.SemanticStatus::CandidateFailed(error) =>
      Err("settings candidate failed: " + @debug.to_string(error))
    @loom.SemanticStatus::GraphFailed(error) =>
      Err("settings graph unavailable: " + error.format_path())
  }
}

///|
/// The last successfully accepted settings document, retained across parser,
/// projection, candidate, and graph failures.
pub fn SettingsAttachment::last_good(self : SettingsAttachment) -> SettingsDoc? {
  self.observation().accepted().map(accepted => accepted.value().doc)
}

///|
/// Apply an incremental edit and eagerly settle its semantic observation.
pub fn SettingsAttachment::apply_edit(
  self : SettingsAttachment,
  edit : @core.Edit,
  new_source : String,
) -> Unit raise Failure {
  self.parser.apply_edit(edit, new_source)
  ignore(self.analysis.read())
}

///|
/// Replace the source wholesale and eagerly settle its semantic observation.
pub fn SettingsAttachment::set_source(
  self : SettingsAttachment,
  new_source : String,
) -> Unit raise Failure {
  self.parser.set_source(new_source)
  ignore(self.analysis.read())
}

///|
/// Retry a candidate or graph fault for the current parser revision.
///
/// Current/rejected observations are already settled and therefore remain
/// cached; candidate and graph faults are the only statuses this read retries.
pub fn SettingsAttachment::retry(
  self : SettingsAttachment,
) -> Unit raise Failure {
  ignore(self.analysis.read())
}

///|
/// Release the semantic analysis and its graph scope. Cached observations stay
/// readable after disposal, and repeated disposal is harmless.
pub fn SettingsAttachment::dispose(self : SettingsAttachment) -> Unit {
  self.analysis.dispose()
}

///|
/// Format the public stable id for a freshly projected setting.
///
/// IDs are opaque and baseline-local (`setting#0`, `setting#1`, …), not derived
/// from the key. The allocator reserves IDs from the previous accepted
/// baseline only; a failed candidate never consumes IDs in a later retry.
fn make_setting_id(occurrence : Int) -> String {
  "setting#" + occurrence.to_string()
}
