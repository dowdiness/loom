///|
/// One resolver-owned source snapshot used for diagnostic rendering.
pub struct SourceSnapshot {
  priv name : String
  priv text : String
  priv line_index : LineIndex
}

///|
pub fn SourceSnapshot::SourceSnapshot(
  name : String,
  text : String,
  line_index : LineIndex,
) -> SourceSnapshot {
  { name, text, line_index }
}

///|
/// Capability for resolving one atomic source snapshot by identity.
pub(open) trait SourceResolver {
  fn resolve_source(Self, SourceId) -> SourceSnapshot?
}

///|
/// Capability that renders one raw source line and projects its UTF-16 ranges
/// to relative display ranges. Both methods receive the absolute column where
/// the rendered line starts and must use the same display model. Marker ranges
/// must be non-negative and ordered; offsets beyond the line text represent
/// stripped line terminators.
pub(open) trait TextDisplay {
  fn render_line(Self, String, Int) -> String
  fn marker_cells(Self, String, Int, Int, Int) -> (Int, Int)
}

///|
priv struct CodeUnitTextDisplay {}

///|
impl TextDisplay for CodeUnitTextDisplay with fn render_line(_, text, _) {
  text
}

///|
impl TextDisplay for CodeUnitTextDisplay with fn marker_cells(
  _,
  _,
  _,
  utf16_start,
  utf16_end,
) {
  (utf16_start, utf16_end)
}

///|
/// Expected failures at the source-backed rendering boundary.
pub suberror DiagnosticRenderError {
  MissingSource(SourceId)
  MismatchedLineIndex(SourceId)
  RangeOutOfBounds(SourceSpan, Int)
  InvalidUtf16Boundary(SourceSpan)
} derive(Eq, Debug)

///|
priv struct ValidatedDiagnosticLabel {
  label : DiagnosticLabel
  source : SourceSnapshot
  line_range : LineRange
}

///|
priv struct ValidatedDiagnosticSourceGroup {
  source_id : SourceId
  source : SourceSnapshot
  labels : Array[ValidatedDiagnosticLabel]
}

///|
priv struct ResolvedDiagnosticSource {
  source_id : SourceId
  source : SourceSnapshot
}

///|
priv struct DiagnosticRenderContext[R] {
  resolver : R
  sources : Array[ResolvedDiagnosticSource]
}

///|
fn[R] DiagnosticRenderContext::DiagnosticRenderContext(
  resolver : R,
) -> DiagnosticRenderContext[R] {
  { resolver, sources: [] }
}

///|
fn diagnostic_severity_name(severity : DiagnosticSeverity) -> String {
  match severity {
    Error => "error"
    Warning => "warning"
    Info => "info"
    Hint => "hint"
  }
}

///|
fn diagnostic_label_style_name(style : LabelStyle) -> String {
  match style {
    Primary => "primary"
    Secondary => "secondary"
  }
}

///|
fn diagnostic_label_marker(style : LabelStyle) -> String {
  match style {
    Primary => "^"
    Secondary => "-"
  }
}

///|
fn LineIndex::matches_source(self : LineIndex, source : String) -> Bool {
  let expected = LineIndex::new(source)
  self.source_len == expected.source_len &&
  self.line_starts == expected.line_starts
}

///|
fn[R : SourceResolver] DiagnosticRenderContext::resolve_source(
  self : DiagnosticRenderContext[R],
  source_id : SourceId,
) -> SourceSnapshot raise DiagnosticRenderError {
  match self.sources.search_by(source => source.source_id == source_id) {
    Some(index) => self.sources[index].source
    None => {
      let source = match self.resolver.resolve_source(source_id) {
        Some(source) => source
        None => raise MissingSource(source_id)
      }
      if source.line_index.strict_offset(source.text, { line: 0, column: 0 }) !=
        Some(0) {
        raise MismatchedLineIndex(source_id)
      }
      self.sources.push({ source_id, source })
      source
    }
  }
}

///|
fn validate_diagnostic_label(
  source : SourceSnapshot,
  label : DiagnosticLabel,
) -> ValidatedDiagnosticLabel raise DiagnosticRenderError {
  let span = label.span()
  let range = span.range()
  let start = range.start().value()
  let end = range.end().value()
  let source_len = source.text.length()
  if start > source_len || end > source_len {
    raise RangeOutOfBounds(span, source_len)
  }
  match source.text.get_view(start~, end~) {
    Some(_) => ()
    None => raise InvalidUtf16Boundary(span)
  }
  { label, source, line_range: source.line_index.line_range(start, end) }
}

///|
fn[R : SourceResolver] validate_diagnostic_groups(
  context : DiagnosticRenderContext[R],
  labels : Array[DiagnosticLabel],
) -> Array[ValidatedDiagnosticSourceGroup] raise DiagnosticRenderError {
  let groups : Array[ValidatedDiagnosticSourceGroup] = []
  labels.each(label => {
    let source_id = label.span().source_id()
    match groups.search_by(group => group.source_id == source_id) {
      Some(index) => {
        let source = groups[index].source
        groups[index].labels.push(validate_diagnostic_label(source, label))
      }
      None => {
        let source = context.resolve_source(source_id)
        groups.push({
          source_id,
          source,
          labels: [validate_diagnostic_label(source, label)],
        })
      }
    }
  })
  groups
}

///|
fn source_line_content_end(source : SourceSnapshot, line : Int) -> Int {
  let starts = source.line_index.line_starts
  let line_start = starts[line]
  let raw_end = match starts.get(line + 1) {
    Some(next_start) => next_start
    None => source.text.length()
  }
  if raw_end <= line_start {
    raw_end
  } else if source.text.code_unit_at(raw_end - 1).to_int() == 0x0A {
    if raw_end - 1 > line_start &&
      source.text.code_unit_at(raw_end - 2).to_int() == 0x0D {
      raw_end - 2
    } else {
      raw_end - 1
    }
  } else if source.text.code_unit_at(raw_end - 1).to_int() == 0x0D {
    raw_end - 1
  } else {
    raw_end
  }
}

///|
fn[D : TextDisplay] render_diagnostic_source_line(
  builder : StringBuilder,
  validated : ValidatedDiagnosticLabel,
  line : Int,
  display : D,
) -> Unit raise DiagnosticRenderError {
  let label = validated.label
  let source = validated.source
  let line_range = validated.line_range
  let start = line_range.start
  let end = line_range.end
  let display_line = (line + 1).to_string()
  let gutter_width = 3 + display_line.length()
  let source_column_start = gutter_width + 2
  let line_start = match
    source.line_index.checked_offset(source.text, { line, column: 0 }) {
    Some(offset) => offset
    None => raise MismatchedLineIndex(label.span().source_id())
  }
  let line_end = source_line_content_end(source, line)
  let line_view = match source.text.get_view(start=line_start, end=line_end) {
    Some(view) => view
    None => raise InvalidUtf16Boundary(label.span())
  }
  let marker_start = if line == start.line { start.column } else { 0 }
  let marker_end = if line == end.line {
    end.column
  } else {
    line_end - line_start
  }
  let line_text = line_view.to_owned()
  let rendered_line = display.render_line(line_text, source_column_start)
  let (marker_cell_start, marker_cell_end) = display.marker_cells(
    line_text, source_column_start, marker_start, marker_end,
  )
  builder.write_string("\n  ")
  builder.write_string(display_line)
  builder.write_string(" |")
  if line_end > line_start {
    builder.write_char(' ')
  }
  builder.write_string(rendered_line)
  builder.write_char('\n')
  builder.write_string(" ".repeat(gutter_width))
  builder.write_string("| ")
  builder.write_string(" ".repeat(marker_cell_start))
  let width = if marker_end > marker_start {
    let measured_width = marker_cell_end - marker_cell_start
    if measured_width > 0 {
      measured_width
    } else {
      1
    }
  } else {
    1
  }
  builder.write_string(diagnostic_label_marker(label.style()).repeat(width))
}

///|
fn[D : TextDisplay] render_diagnostic_label(
  builder : StringBuilder,
  validated : ValidatedDiagnosticLabel,
  display : D,
) -> Unit raise DiagnosticRenderError {
  let label = validated.label
  let line_range = validated.line_range
  let start = line_range.start
  let end = line_range.end
  builder.write_string(diagnostic_label_style_name(label.style()))
  builder.write_char(' ')
  builder.write_string((start.line + 1).to_string())
  builder.write_char(':')
  builder.write_string((start.column + 1).to_string())
  builder.write_char('-')
  builder.write_string((end.line + 1).to_string())
  builder.write_char(':')
  builder.write_string((end.column + 1).to_string())
  match label.message() {
    Some(message) => {
      builder.write_string(": ")
      builder.write_string(message)
    }
    None => ()
  }
  let nonempty = label.span().range().length() > 0
  let last_line = if nonempty && end.line > start.line && end.column == 0 {
    end.line - 1
  } else {
    end.line
  }
  Array::makei(last_line - start.line + 1, index => start.line + index).each(line => {
    render_diagnostic_source_line(builder, validated, line, display)
  })
}

///|
fn[D : TextDisplay] render_diagnostic_source_group(
  builder : StringBuilder,
  group : ValidatedDiagnosticSourceGroup,
  display : D,
) -> Unit raise DiagnosticRenderError {
  builder.write_string("\n--> ")
  builder.write_string(group.source.name)
  group.labels.each(label => {
    builder.write_char('\n')
    render_diagnostic_label(builder, label, display)
  })
}

///|
fn[R : SourceResolver, D : TextDisplay] Diagnostic::render_plain_with_context(
  self : Diagnostic,
  context : DiagnosticRenderContext[R],
  display : D,
) -> String raise DiagnosticRenderError {
  let groups = validate_diagnostic_groups(context, self.labels())
  let builder = StringBuilder()
  builder.write_string(diagnostic_severity_name(self.severity()))
  match self.code() {
    Some(code) => {
      builder.write_char('[')
      builder.write_string(code.value())
      builder.write_char(']')
    }
    None => ()
  }
  builder.write_string(": ")
  builder.write_string(self.message())
  groups.each(group => render_diagnostic_source_group(builder, group, display))
  self
  .notes()
  .each(note => {
    builder.write_string("\n= note: ")
    builder.write_string(note)
  })
  builder.to_string()
}

///|
pub fn[R : SourceResolver] Diagnostic::render_plain(
  self : Diagnostic,
  resolver : R,
) -> String raise DiagnosticRenderError {
  self.render_plain_with_context(DiagnosticRenderContext(resolver), CodeUnitTextDisplay::{

  })
}

///|
/// Render with an explicit source display capability.
pub fn[R : SourceResolver, D : TextDisplay] Diagnostic::render_plain_with_display(
  self : Diagnostic,
  resolver : R,
  display : D,
) -> String raise DiagnosticRenderError {
  self.render_plain_with_context(DiagnosticRenderContext(resolver), display)
}

///|
/// Render an ordered diagnostic view while resolving each source once.
pub fn[R : SourceResolver] render_diagnostics_plain(
  diagnostics : ArrayView[Diagnostic],
  resolver : R,
) -> String raise DiagnosticRenderError {
  let context = DiagnosticRenderContext(resolver)
  diagnostics
  .map(diagnostic => {
    diagnostic.render_plain_with_context(context, CodeUnitTextDisplay::{  })
  })
  .join("\n\n")
}

///|
/// Render an ordered diagnostic view with an explicit source display capability.
pub fn[R : SourceResolver, D : TextDisplay] render_diagnostics_plain_with_display(
  diagnostics : ArrayView[Diagnostic],
  resolver : R,
  display : D,
) -> String raise DiagnosticRenderError {
  let context = DiagnosticRenderContext(resolver)
  diagnostics
  .map(diagnostic => diagnostic.render_plain_with_context(context, display))
  .join("\n\n")
}
