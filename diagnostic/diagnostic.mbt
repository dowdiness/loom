///|
/// Type-safe UTF-16 code-unit offset into a source string.
pub struct TextOffset {
  priv value : Int
} derive(Eq, Debug, Hash, Compare)

///|
pub(all) suberror DiagnosticBuildError {
  NegativeTextOffset(Int)
  InvalidTextRange(Int, Int)
} derive(Debug)

///|
pub fn TextOffset::TextOffset(
  value : Int,
) -> TextOffset raise DiagnosticBuildError {
  guard value >= 0 else { raise NegativeTextOffset(value) }
  { value, }
}

///|
pub fn TextOffset::value(self : TextOffset) -> Int {
  self.value
}

///|
pub fn TextOffset::offset_by(
  self : TextOffset,
  delta : Int,
) -> TextOffset raise DiagnosticBuildError {
  TextOffset(self.value + delta)
}

///|
fn TextOffset::offset_if_at_or_after(
  self : TextOffset,
  delta : Int,
  after : TextOffset,
) -> TextOffset raise DiagnosticBuildError {
  if self.value >= after.value {
    self.offset_by(delta)
  } else {
    self
  }
}

///|
/// Half-open UTF-16 code-unit source range `[start, end)`.
pub struct TextRange {
  priv start : TextOffset
  priv end : TextOffset
} derive(Eq, Debug, Hash, Compare)

///|
pub fn TextRange::TextRange(
  start : TextOffset,
  end : TextOffset,
) -> TextRange raise DiagnosticBuildError {
  guard end.value >= start.value else {
    raise InvalidTextRange(start.value, end.value)
  }
  { start, end }
}

///|
pub fn TextRange::from_offsets(
  start : Int,
  end : Int,
) -> TextRange raise DiagnosticBuildError {
  TextRange(TextOffset(start), TextOffset(end))
}

///|
pub fn TextRange::start(self : TextRange) -> TextOffset {
  self.start
}

///|
pub fn TextRange::end(self : TextRange) -> TextOffset {
  self.end
}

///|
pub fn TextRange::length(self : TextRange) -> Int {
  self.end.value - self.start.value
}

///|
pub fn TextRange::offset_by(
  self : TextRange,
  delta : Int,
  after : TextOffset,
) -> TextRange raise DiagnosticBuildError {
  if delta == 0 {
    return self
  }
  TextRange(
    self.start.offset_if_at_or_after(delta, after),
    self.end.offset_if_at_or_after(delta, after),
  )
}

///|
fn format_line_col(pos : LineCol) -> String {
  pos.line.to_string() + ":" + pos.column.to_string()
}

///|
pub(all) enum DiagnosticSeverity {
  Error
  Warning
  Info
  Hint
} derive(Eq, Debug)

///|
pub fn DiagnosticSeverity::all() -> Array[DiagnosticSeverity] {
  [Error, Warning, Info, Hint]
}

///|
/// Identifies the subsystem or domain that produced a diagnostic.
pub struct DiagnosticOrigin {
  priv name : String
} derive(Eq, Debug, Hash)

///|
pub fn DiagnosticOrigin::DiagnosticOrigin(name : String) -> DiagnosticOrigin {
  { name, }
}

///|
pub fn DiagnosticOrigin::name(self : DiagnosticOrigin) -> String {
  self.name
}

///|
pub struct DiagnosticCode {
  priv value : String
} derive(Eq, Debug, Hash)

///|
pub fn DiagnosticCode::DiagnosticCode(value : String) -> DiagnosticCode {
  { value, }
}

///|
pub fn DiagnosticCode::value(self : DiagnosticCode) -> String {
  self.value
}

///|
/// Stable identity of source text within a resolver snapshot.
pub struct SourceId {
  priv value : String
} derive(Eq, Debug, Hash)

///|
pub fn SourceId::SourceId(value : String) -> SourceId {
  { value, }
}

///|
pub fn SourceId::value(self : SourceId) -> String {
  self.value
}

///|
/// Source-qualified half-open UTF-16 code-unit range.
pub struct SourceSpan {
  priv source_id : SourceId
  priv range : TextRange
} derive(Eq, Debug, Hash)

///|
pub fn SourceSpan::SourceSpan(
  source_id : SourceId,
  range : TextRange,
) -> SourceSpan {
  { source_id, range }
}

///|
pub fn SourceSpan::source_id(self : SourceSpan) -> SourceId {
  self.source_id
}

///|
pub fn SourceSpan::range(self : SourceSpan) -> TextRange {
  self.range
}

///|
fn SourceSpan::offset_by(
  self : SourceSpan,
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> SourceSpan raise DiagnosticBuildError {
  if self.source_id != edited_source || delta == 0 {
    self
  } else {
    SourceSpan(self.source_id, self.range.offset_by(delta, after))
  }
}

///|
pub(all) enum LabelStyle {
  Primary
  Secondary
} derive(Eq, Debug, Hash)

///|
pub struct DiagnosticLabel {
  priv style : LabelStyle
  priv span : SourceSpan
  priv message : String?
} derive(Eq, Debug)

///|
pub fn DiagnosticLabel::DiagnosticLabel(
  style : LabelStyle,
  span : SourceSpan,
  message : String?,
) -> DiagnosticLabel {
  { style, span, message }
}

///|
pub fn DiagnosticLabel::style(self : DiagnosticLabel) -> LabelStyle {
  self.style
}

///|
pub fn DiagnosticLabel::span(self : DiagnosticLabel) -> SourceSpan {
  self.span
}

///|
pub fn DiagnosticLabel::message(self : DiagnosticLabel) -> String? {
  self.message
}

///|
fn DiagnosticLabel::offset_by(
  self : DiagnosticLabel,
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> DiagnosticLabel raise DiagnosticBuildError {
  DiagnosticLabel(
    self.style,
    self.span.offset_by(edited_source, delta, after),
    self.message,
  )
}

///|
/// Canonical structured diagnostic value for tools and applications.
pub struct Diagnostic {
  priv origin : DiagnosticOrigin
  priv severity : DiagnosticSeverity
  priv code : DiagnosticCode?
  priv message : String
  priv labels : Array[DiagnosticLabel]
  priv notes : Array[String]
  priv fixes : Array[DiagnosticFix]
} derive(Eq, Debug)

///|
pub fn Diagnostic::Diagnostic(
  origin~ : DiagnosticOrigin,
  severity~ : DiagnosticSeverity,
  message~ : String,
  code? : DiagnosticCode? = None,
  labels? : Array[DiagnosticLabel] = [],
  notes? : Array[String] = [],
  fixes? : Array[DiagnosticFix] = [],
) -> Diagnostic {
  {
    origin,
    severity,
    code,
    message,
    labels: labels.copy(),
    notes: notes.copy(),
    fixes: fixes.copy(),
  }
}

///|
pub fn Diagnostic::origin(self : Diagnostic) -> DiagnosticOrigin {
  self.origin
}

///|
pub fn Diagnostic::severity(self : Diagnostic) -> DiagnosticSeverity {
  self.severity
}

///|
pub fn Diagnostic::code(self : Diagnostic) -> DiagnosticCode? {
  self.code
}

///|
pub fn Diagnostic::message(self : Diagnostic) -> String {
  self.message
}

///|
pub fn Diagnostic::labels(self : Diagnostic) -> Array[DiagnosticLabel] {
  self.labels.copy()
}

///|
pub fn Diagnostic::notes(self : Diagnostic) -> Array[String] {
  self.notes.copy()
}

///|
pub fn Diagnostic::fixes(self : Diagnostic) -> Array[DiagnosticFix] {
  self.fixes.copy()
}

///|
fn Diagnostic::single_primary_span(self : Diagnostic) -> SourceSpan? {
  let primary = self.labels.filter(label => label.style == LabelStyle::Primary)
  if primary.length() == 1 {
    Some(primary[0].span)
  } else {
    None
  }
}

///|
pub fn Diagnostic::line_range(
  self : Diagnostic,
  index : LineIndex,
) -> LineRange? {
  match self.single_primary_span() {
    Some(span) =>
      Some(index.line_range(span.range.start.value, span.range.end.value))
    None => None
  }
}

///|
pub fn Diagnostic::format(self : Diagnostic) -> String {
  match self.single_primary_span() {
    Some(span) =>
      self.message +
      " [" +
      span.range.start.value.to_string() +
      "," +
      span.range.end.value.to_string() +
      "]"
    None => self.message
  }
}

///|
pub fn Diagnostic::format_with_line_col(
  self : Diagnostic,
  index : LineIndex,
) -> String {
  match self.line_range(index) {
    Some(range) =>
      self.message +
      " [" +
      format_line_col(range.start) +
      "," +
      format_line_col(range.end) +
      "]"
    None => self.message
  }
}

///|
pub fn Diagnostic::offset_by(
  self : Diagnostic,
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> Diagnostic raise DiagnosticBuildError {
  if delta == 0 {
    return self
  }
  Diagnostic(
    origin=self.origin,
    severity=self.severity,
    code=self.code,
    message=self.message,
    labels=self.labels.map(label => label.offset_by(edited_source, delta, after)),
    notes=self.notes,
    fixes=self.fixes,
  )
}

///|
/// Converts an application-defined value into the canonical diagnostic model.
pub(open) trait ToDiagnostic {
  fn to_diagnostic(Self) -> Diagnostic
}
