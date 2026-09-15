///|
using @core {type Edit}

///|
using @semantic_change {
  compose_projection_identity_edits,
  edit_matches_sources,
  edit_has_valid_old_range,
}

///|
priv enum ChangeIntent {
  Unchanged
  Exact(Edit)
  SourceDiff
}

///|
/// Baseline-relative edit evidence retained until semantic acceptance.
///
/// An explicit edit is a conservative envelope, not a lossless edit list.
/// Missing or non-composable evidence falls back to endpoint source comparison.
/// Identity alignment uses the same range and composition policy as
/// `ProjectionIdentityTracker`; accepted semantic values own their baseline.
pub struct SemanticChange {
  priv baseline_source : String
  priv source : String
  priv pending : ChangeIntent
}

///|
pub fn SemanticChange::SemanticChange(source : String) -> SemanticChange {
  { baseline_source: source, source, pending: Unchanged, }
}

///|
pub fn SemanticChange::baseline_source(self : SemanticChange) -> String {
  self.baseline_source
}

///|
pub fn SemanticChange::source(self : SemanticChange) -> String {
  self.source
}

///|
/// Return trustworthy explicit evidence for the current endpoints, or `None`
/// to request source-diff alignment. Equal-text replacements retain intent.
pub fn SemanticChange::edit(self : SemanticChange) -> Edit? {
  match self.pending {
    Exact(edit) if edit_matches_sources(self.baseline_source, self.source, edit) =>
      Some(edit)
    _ => None
  }
}

///|
/// Return a new change without modifying this value. A source-only transition
/// loses exact provenance; later edits cannot manufacture the missing history.
pub fn SemanticChange::advance(
  self : SemanticChange,
  new_source : String,
  edit? : Edit,
) -> SemanticChange {
  let pending = match self.pending {
    Unchanged =>
      match edit {
        Some(edit) if edit_has_valid_old_range(self.source, edit) => Exact(edit)
        _ => SourceDiff
      }
    Exact(previous) =>
      match edit {
        Some(next) =>
          match
            compose_projection_identity_edits(
              self.baseline_source,
              previous,
              self.source,
              next,
              new_source,
            ) {
            Some(composed) => Exact(composed)
            None => SourceDiff
          }
        None => SourceDiff
      }
    SourceDiff => SourceDiff
  }
  { baseline_source: self.baseline_source, source: new_source, pending, }
}
