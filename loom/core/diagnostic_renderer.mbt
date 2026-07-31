///|
/// One provider-owned source snapshot used for diagnostic rendering.
pub struct DiagnosticSourceFile {
  priv name : String
  priv text : String
  priv line_index : LineIndex
}

///|
pub fn DiagnosticSourceFile::DiagnosticSourceFile(
  name : String,
  text : String,
  line_index : LineIndex,
) -> DiagnosticSourceFile {
  { name, text, line_index }
}

///|
/// External capability for resolving one atomic source snapshot by identity.
pub struct SourceProvider {
  priv resolve_source : (SourceId) -> DiagnosticSourceFile?
}

///|
pub fn SourceProvider::SourceProvider(
  resolve_source : (SourceId) -> DiagnosticSourceFile?,
) -> SourceProvider {
  { resolve_source, }
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
  source : DiagnosticSourceFile
  line_range : LineRange
}

///|
priv struct ValidatedDiagnosticSourceGroup {
  source_id : SourceId
  source : DiagnosticSourceFile
  labels : Array[ValidatedDiagnosticLabel]
}

///|
priv struct ResolvedDiagnosticSource {
  source_id : SourceId
  source : DiagnosticSourceFile
}

///|
priv struct DiagnosticRenderContext {
  provider : SourceProvider
  sources : Array[ResolvedDiagnosticSource]
}

///|
fn DiagnosticRenderContext::DiagnosticRenderContext(
  provider : SourceProvider,
) -> DiagnosticRenderContext {
  { provider, sources: [] }
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
fn DiagnosticRenderContext::resolve_source(
  self : DiagnosticRenderContext,
  source_id : SourceId,
) -> DiagnosticSourceFile raise DiagnosticRenderError {
  match self.sources.search_by(source => source.source_id == source_id) {
    Some(index) => self.sources[index].source
    None => {
      let source = match (self.provider.resolve_source)(source_id) {
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
  source : DiagnosticSourceFile,
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
fn validate_diagnostic_groups(
  context : DiagnosticRenderContext,
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
fn source_line_content_end(source : DiagnosticSourceFile, line : Int) -> Int {
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
fn render_diagnostic_source_line(
  builder : StringBuilder,
  validated : ValidatedDiagnosticLabel,
  line : Int,
) -> Unit raise DiagnosticRenderError {
  let label = validated.label
  let source = validated.source
  let line_range = validated.line_range
  let start = line_range.start
  let end = line_range.end
  let display_line = (line + 1).to_string()
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
  builder.write_string("\n  ")
  builder.write_string(display_line)
  builder.write_string(" |")
  if line_end > line_start {
    builder.write_char(' ')
  }
  builder.write_stringview(line_view)
  builder.write_char('\n')
  builder.write_string(" ".repeat(3 + display_line.length()))
  builder.write_string("| ")
  builder.write_string(" ".repeat(marker_start))
  let width = if marker_end > marker_start {
    marker_end - marker_start
  } else {
    1
  }
  builder.write_string(diagnostic_label_marker(label.style()).repeat(width))
}

///|
fn render_diagnostic_label(
  builder : StringBuilder,
  validated : ValidatedDiagnosticLabel,
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
    render_diagnostic_source_line(builder, validated, line)
  })
}

///|
fn render_diagnostic_source_group(
  builder : StringBuilder,
  group : ValidatedDiagnosticSourceGroup,
) -> Unit raise DiagnosticRenderError {
  builder.write_string("\n--> ")
  builder.write_string(group.source.name)
  group.labels.each(label => {
    builder.write_char('\n')
    render_diagnostic_label(builder, label)
  })
}

///|
pub fn Diagnostic::render_plain(
  self : Diagnostic,
  provider : SourceProvider,
) -> String raise DiagnosticRenderError {
  self.render_plain_with_context(DiagnosticRenderContext(provider))
}

///|
fn Diagnostic::render_plain_with_context(
  self : Diagnostic,
  context : DiagnosticRenderContext,
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
  groups.each(group => render_diagnostic_source_group(builder, group))
  self
  .notes()
  .each(note => {
    builder.write_string("\n= note: ")
    builder.write_string(note)
  })
  builder.to_string()
}

///|
pub fn DiagnosticSet::render_plain(
  self : DiagnosticSet,
  provider : SourceProvider,
) -> String raise DiagnosticRenderError {
  let context = DiagnosticRenderContext(provider)
  self
  .items()
  .map(diagnostic => diagnostic.render_plain_with_context(context))
  .join("\n\n")
}
