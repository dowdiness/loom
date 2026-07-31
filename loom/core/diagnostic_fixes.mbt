///|
/// Confidence attached to one neutral diagnostic fix candidate.
pub(all) enum FixApplicability {
  Always
  MaybeIncorrect
} derive(Eq, Debug)

///|
/// One source-qualified half-open UTF-16 text replacement.
pub struct TextReplacement {
  priv span : SourceSpan
  priv replacement : String
} derive(Eq, Debug)

///|
pub fn TextReplacement::TextReplacement(
  span : SourceSpan,
  replacement : String,
) -> TextReplacement {
  { span, replacement }
}

///|
pub fn TextReplacement::span(self : TextReplacement) -> SourceSpan {
  self.span
}

///|
pub fn TextReplacement::replacement(self : TextReplacement) -> String {
  self.replacement
}

///|
/// Expected failures while constructing or applying a diagnostic fix.
pub suberror DiagnosticFixError {
  EmptyDiagnosticFix
  MultiSourceDiagnosticFix(SourceId, SourceId)
  OverlappingDiagnosticFixEdits(SourceSpan, SourceSpan)
  DuplicateDiagnosticFixInsertion(SourceSpan, SourceSpan)
  DiagnosticFixSourceMismatch(SourceId, SourceId)
  DiagnosticFixRangeOutOfBounds(SourceSpan, Int)
  DiagnosticFixInvalidUtf16Boundary(SourceSpan)
} derive(Eq, Debug)

///|
/// One named, single-source diagnostic fix candidate.
pub struct DiagnosticFix {
  priv title : String
  priv applicability : FixApplicability
  priv edits : Array[TextReplacement]
} derive(Eq, Debug)

///|
pub fn DiagnosticFix::DiagnosticFix(
  title : String,
  applicability : FixApplicability,
  edits : Array[TextReplacement],
) -> DiagnosticFix raise DiagnosticFixError {
  guard !edits.is_empty() else { raise EmptyDiagnosticFix }
  let normalized = edits.copy()
  let expected_source = normalized[0].span.source_id
  match normalized.search_by(edit => edit.span.source_id != expected_source) {
    Some(index) =>
      raise MultiSourceDiagnosticFix(
        expected_source,
        normalized[index].span.source_id,
      )
    None => ()
  }
  normalized.sort_by((left, right) => {
    left.span.range.start.value.compare(right.span.range.start.value)
  })
  normalized
  .windows(2)
  .each(window => {
    let previous = window[0]
    let current = window[1]
    let previous_range = previous.span.range
    let current_range = current.span.range
    if previous_range.start == current_range.start {
      if previous_range.start == previous_range.end &&
        current_range.start == current_range.end {
        raise DuplicateDiagnosticFixInsertion(previous.span, current.span)
      }
      raise OverlappingDiagnosticFixEdits(previous.span, current.span)
    }
    if current_range.start.value < previous_range.end.value {
      raise OverlappingDiagnosticFixEdits(previous.span, current.span)
    }
  })
  { title, applicability, edits: normalized }
}

///|
pub fn DiagnosticFix::title(self : DiagnosticFix) -> String {
  self.title
}

///|
pub fn DiagnosticFix::applicability(self : DiagnosticFix) -> FixApplicability {
  self.applicability
}

///|
pub fn DiagnosticFix::edits(self : DiagnosticFix) -> Array[TextReplacement] {
  self.edits.copy()
}

///|
/// Apply this candidate atomically to the identified in-memory source.
pub fn DiagnosticFix::apply(
  self : DiagnosticFix,
  source_id : SourceId,
  source : String,
) -> String raise DiagnosticFixError {
  let expected_source = self.edits[0].span.source_id
  guard source_id == expected_source else {
    raise DiagnosticFixSourceMismatch(expected_source, source_id)
  }
  let source_length = source.length()
  self.edits.each(edit => {
    let span = edit.span
    let range = span.range
    guard range.end.value <= source_length else {
      raise DiagnosticFixRangeOutOfBounds(span, source_length)
    }
    guard source.get_view(start=range.start.value, end=range.end.value)
      is Some(_) else {
      raise DiagnosticFixInvalidUtf16Boundary(span)
    }
  })
  self.edits.rev_fold(init=source, (current, edit) => {
    let range = edit.span.range
    current.view(start_offset=0, end_offset=range.start.value).to_owned() +
    edit.replacement +
    current
    .view(start_offset=range.end.value, end_offset=current.length())
    .to_owned()
  })
}
