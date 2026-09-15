///|
/// Language-owned candidate construction either accepts one complete value or
/// rejects the input. Candidate exceptions are a separate observation channel.
pub(all) enum SemanticDecision[M, R] {
  Accept(M)
  Reject(R)
}

///|
/// Terminal settlement outcome. A fault never advances the accepted baseline.
pub enum SemanticStatus[R] {
  Current
  Rejected(R)
  GraphFailed(@incr.ReadError)
  CandidateFailed(Error)
}

///|
/// A parser snapshot captured for semantic settlement, not a second parse.
/// `revision` counts parser-owned semantic transitions, independently of Incr
/// backdating. Diagnostic collections are isolated on capture and access.
pub struct SemanticSnapshot {
  priv source_id : @core.SourceId
  priv source : String
  priv revision : Int
  priv syntax : @seam.SyntaxNode
  priv diagnostics : @core.DiagnosticSet
}

///|
pub fn SemanticSnapshot::source_id(self : SemanticSnapshot) -> @core.SourceId {
  self.source_id
}

///|
pub fn SemanticSnapshot::source(self : SemanticSnapshot) -> String {
  self.source
}

///|
pub fn SemanticSnapshot::revision(self : SemanticSnapshot) -> Int {
  self.revision
}

///|
pub fn SemanticSnapshot::syntax(self : SemanticSnapshot) -> @seam.SyntaxNode {
  self.syntax
}

///|
pub fn SemanticSnapshot::diagnostics(
  self : SemanticSnapshot,
) -> @core.DiagnosticSet {
  self.diagnostics.copy()
}

///|
/// One accepted publication. Put model and identity baseline in `M` together.
/// The author must keep returned domain values observationally stable; core
/// imposes neither `Eq` nor a universal copying convention on `M`.
pub struct SemanticAccepted[M] {
  priv snapshot : SemanticSnapshot
  priv value : M
}

///|
pub fn[M] SemanticAccepted::snapshot(
  self : SemanticAccepted[M],
) -> SemanticSnapshot {
  self.snapshot
}

///|
pub fn[M] SemanticAccepted::value(self : SemanticAccepted[M]) -> M {
  self.value
}

///|
/// A completed observation. Later edits, faults and disposal do not rewrite it.
pub struct SemanticObservation[M, R] {
  priv source : String
  priv revision : Int
  priv accepted : SemanticAccepted[M]?
  priv status : SemanticStatus[R]
}

///|
pub fn[M, R] SemanticObservation::source(
  self : SemanticObservation[M, R],
) -> String {
  self.source
}

///|
pub fn[M, R] SemanticObservation::revision(
  self : SemanticObservation[M, R],
) -> Int {
  self.revision
}

///|
pub fn[M, R] SemanticObservation::accepted(
  self : SemanticObservation[M, R],
) -> SemanticAccepted[M]? {
  self.accepted
}

///|
pub fn[M, R] SemanticObservation::status(
  self : SemanticObservation[M, R],
) -> SemanticStatus[R] {
  self.status
}

///|
priv struct SemanticFrame[M, R] {
  change : SemanticChange
  revision : Int
  accepted : SemanticAccepted[M]?
  observation : SemanticObservation[M, R]?
}

///|
/// A independently settled parser attachment. Owns its graph anchor and
/// accepted frame. Call `read` after an update to choose eager settlement;
/// parser updates themselves never execute candidate code. Dispose explicitly.
pub struct SemanticAnalysis[M, R] {
  priv hub : SemanticHub
  priv registration : Int
  priv scope : @incr.Scope
  priv read_snapshot : (Int) -> Result[SemanticSnapshot, @incr.ReadError]
  priv project : (SemanticAccepted[M]?, SemanticSnapshot, SemanticChange) -> SemanticDecision[
    M,
    R,
  ] raise
  priv frame : Ref[SemanticFrame[M, R]]
}

///|
/// Return the last completed observation without evaluating, including after
/// disposal. `None` means the analysis has never been read.
pub fn[M, R] SemanticAnalysis::observation(
  self : SemanticAnalysis[M, R],
) -> SemanticObservation[M, R]? {
  self.frame.val.observation
}

///|
/// Settle the latest parser transition. Current/rejected results are cached;
/// another explicit read retries a fault. No callback is automatically retried.
/// Candidate errors are quarantined as `CandidateFailed`, not parser failures.
/// Reentrant settlement and reads after disposal raise `Failure` before touching
/// a closed watch. Cached observations remain available through `observation`.
pub fn[M, R] SemanticAnalysis::read(
  self : SemanticAnalysis[M, R],
) -> SemanticObservation[M, R] raise Failure {
  guard !self.scope.is_disposed() else { fail("semantic analysis is disposed") }
  self.hub.require_idle()
  self.hub.busy = true
  defer {
    self.hub.busy = false
  }
  let frame = self.frame.val
  match frame.observation {
    Some(observation) if observation.revision == frame.revision =>
      match observation.status {
        Current | Rejected(_) => return observation
        GraphFailed(_) | CandidateFailed(_) => ()
      }
    _ => ()
  }
  let mut accepted = frame.accepted
  let mut change = frame.change
  let status = match (self.read_snapshot)(frame.revision) {
    Err(error) => SemanticStatus::GraphFailed(error)
    Ok(snapshot) => {
      // This is the author-code fault boundary. No accepted state is changed
      // until the entire candidate has returned normally.
      let outcome = try
        (self.project)(frame.accepted, snapshot, frame.change)
      catch {
        error => Err(error)
      } noraise {
        decision => Ok(decision)
      }
      match outcome {
        Err(error) => CandidateFailed(error)
        Ok(Reject(reason)) => Rejected(reason)
        Ok(Accept(value)) => {
          accepted = Some({ snapshot, value, })
          change = SemanticChange(snapshot.source)
          Current
        }
      }
    }
  }
  // A callback may close its analysis. Cancel publication without touching the
  // closed watch: Watch disposal is not a disposed-cell ReadError.
  guard !self.scope.is_disposed() else {
    fail("semantic analysis was disposed during candidate construction")
  }
  let observation = {
    source: frame.change.source(),
    revision: frame.revision,
    accepted,
    status,
  }
  self.frame.val = {
    change,
    revision: frame.revision,
    accepted,
    observation: Some(observation),
  }
  observation
}

///|
/// Release the registration and graph anchor, retaining completed observations.
/// Idempotent; disposing during candidate construction discards that candidate.
pub fn[M, R] SemanticAnalysis::dispose(self : SemanticAnalysis[M, R]) -> Unit {
  self.hub.registrations.remove(self.registration)
  self.scope.dispose()
}

///|
/// Attach an independently settled semantic analysis to the existing parser.
/// Primes a graph watch but does not call `project`; the caller chooses timing.
/// Candidate code must not mutate or settle this parser reentrantly.
pub fn[Ast, M, R] Parser::attach_semantic(
  self : Parser[Ast],
  project : (SemanticAccepted[M]?, SemanticSnapshot, SemanticChange) -> SemanticDecision[
    M,
    R,
  ] raise,
) -> SemanticAnalysis[M, R] raise Failure {
  let hub = match self.semantic_hub {
    Some(hub) => hub
    None => {
      let hub = SemanticHub()
      self.semantic_hub = Some(hub)
      hub
    }
  }
  hub.require_idle()
  let source_id = self.source_id()
  let scope = @incr.Scope::new(self.rt)
  let watch = scope.watch(self.snapshot_view)
  let frame : Ref[SemanticFrame[M, R]] = Ref({
    change: SemanticChange(self.engine.get_source()),
    revision: hub.revision,
    accepted: None,
    observation: None,
  })
  let registration = hub.next_registration
  hub.next_registration += 1
  hub.registrations[registration] = (source, revision, edit) => {
    let previous = frame.val
    frame.val = {
      change: previous.change.advance(source, edit?),
      revision,
      accepted: previous.accepted,
      observation: previous.observation,
    }
  }
  {
    hub,
    registration,
    scope,
    read_snapshot: revision => {
      match watch.read() {
        Err(error) => Err(error)
        Ok(snapshot) =>
          Ok({
            source_id,
            source: snapshot.source,
            revision,
            syntax: snapshot.syntax,
            diagnostics: snapshot.diagnostics.copy(),
          })
      }
    },
    project,
    frame,
  }
}
