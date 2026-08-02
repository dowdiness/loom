///|
/// Presentation failures preserve the typed source or display-width cause.
pub(all) suberror DiagnosticPrettyError {
  Diagnostic(@diagnostic.DiagnosticRenderError)
  DisplayWidth(@moji.DisplayWidthError)
} derive(Eq, Debug)

///|
/// Explicit display policy for one diagnostic layout.
pub struct DiagnosticPrettyOptions {
  priv tab_width_ : Int
  priv ambiguous_width_ : @moji.AmbiguousWidth
}

///|
pub fn DiagnosticPrettyOptions::DiagnosticPrettyOptions(
  tab_width? : Int = 4,
  ambiguous_width? : @moji.AmbiguousWidth = @moji.AmbiguousWidth::Narrow,
) -> DiagnosticPrettyOptions raise DiagnosticPrettyError {
  guard tab_width > 0 else {
    raise DisplayWidth(@moji.InvalidTabWidth(tab_width))
  }
  { tab_width_: tab_width, ambiguous_width_: ambiguous_width }
}

///|
/// Semantic presentation roles carried by the returned pretty layout.
pub(all) enum DiagnosticStyle {
  Severity(@diagnostic.DiagnosticSeverity)
  Code
  SourceName
  Gutter
  Primary
  Secondary
  Note
} derive(Eq, Debug)

///|
priv struct ResolvedSource {
  source_id : @diagnostic.SourceId
  snapshot : @diagnostic.SourceSnapshot
}

///|
priv struct ValidatedLabel {
  label : @diagnostic.DiagnosticLabel
  snapshot : @diagnostic.SourceSnapshot
  line_range : @diagnostic.LineRange
}

///|
priv struct SourceGroup {
  source_id : @diagnostic.SourceId
  snapshot : @diagnostic.SourceSnapshot
  labels : Array[ValidatedLabel]
}

///|
priv struct SourceLine {
  start : Int
  end : Int
}

///|
fn[T] diagnostic_error(
  body : () -> T raise @diagnostic.DiagnosticRenderError,
) -> T raise DiagnosticPrettyError {
  body() catch {
    error => raise Diagnostic(error)
  }
}

///|
fn[T] display_error(
  body : () -> T raise @moji.DisplayWidthError,
) -> T raise DiagnosticPrettyError {
  body() catch {
    error => raise DisplayWidth(error)
  }
}

///|
fn measured_text(
  text : String,
  options : DiagnosticPrettyOptions,
  start_column? : Int = 0,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let width = display_error(() => {
    @moji.display_width(
      text,
      start_column~,
      tab_width=options.tab_width_,
      ambiguous_width=options.ambiguous_width_,
    )
  })
  let units = display_units(text, start_column, options)
  let rendered = render_source_text(text, units)
  try @pretty.text_with_width(rendered, width) catch {
    @pretty.NegativeTextWidth(_) =>
      abort("moji display width must be non-negative")
  } noraise {
    layout => layout
  }
}

///|
fn source_lines(text : String) -> Array[SourceLine] {
  let lines : Array[SourceLine] = []
  let len = text.length()
  let mut line_start = 0
  let mut pos = 0
  while pos < len {
    match text.view(start_offset=pos) {
      ['\r', '\n', .. rest] => {
        lines.push({ start: line_start, end: pos })
        pos = rest.start_offset()
        line_start = pos
      }
      ['\n', .. rest] | ['\r', .. rest] => {
        lines.push({ start: line_start, end: pos })
        pos = rest.start_offset()
        line_start = pos
      }
      _ =>
        pos = match text.get_char(pos) {
          Some(_) => {
            let unit = text.code_unit_at(pos)
            if unit.is_surrogate() && pos + 1 < len {
              pos + 2
            } else {
              pos + 1
            }
          }
          None => pos + 1
        }
    }
  }
  lines.push({ start: line_start, end: len })
  lines
}

///|
fn display_units(
  text : String,
  start_column : Int,
  options : DiagnosticPrettyOptions,
) -> Array[@moji.DisplayUnit] raise DiagnosticPrettyError {
  display_error(() => {
    @moji.display_units(
      text,
      start_column~,
      tab_width=options.tab_width_,
      ambiguous_width=options.ambiguous_width_,
    )
  })
}

///|
fn render_source_text(
  text : String,
  units : Array[@moji.DisplayUnit],
) -> String {
  let builder = StringBuilder()
  units.each(unit => {
    let view = text.view(
      start_offset=unit.utf16_start(),
      end_offset=unit.utf16_end(),
    )
    if view.equal_to_string("\t") {
      builder.write_string(" ".repeat(unit.cell_end() - unit.cell_start()))
    } else {
      builder.write_stringview(view)
    }
  })
  builder.to_string()
}

///|
fn report_text(
  text : String,
  options : DiagnosticPrettyOptions,
  first_column? : Int = 0,
  continuation_column? : Int = 0,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let source_line_bounds = source_lines(text)
  let lines = Array::makei(source_line_bounds.length(), index => {
    let bounds = source_line_bounds[index]
    let line = match text.get_view(start=bounds.start, end=bounds.end) {
      Some(view) => view.to_owned()
      None => abort("report line must have UTF-16 boundaries")
    }
    let start_column = if index == 0 {
      first_column
    } else {
      continuation_column
    }
    measured_text(line, options, start_column~)
  })
  @pretty.separate(@pretty.hardline(), lines)
}

///|
fn contains_tab(text : String) -> Bool {
  text.contains("\t")
}

///|
fn projected_marker_cells(
  text : String,
  units : Array[@moji.DisplayUnit],
  start_column : Int,
  utf16_start : Int,
  utf16_end : Int,
) -> (Int, Int) {
  let line_cell_end = match units.last() {
    Some(unit) => unit.cell_end()
    None => start_column
  }
  let cell_start = match
    units.search_by(unit => utf16_start < unit.utf16_end()) {
    Some(index) => units[index].cell_start()
    None => line_cell_end + utf16_start - text.length()
  }
  let cell_end = match units.search_by(unit => utf16_end <= unit.utf16_end()) {
    Some(index) => {
      let unit = units[index]
      if utf16_end <= unit.utf16_start() {
        unit.cell_start()
      } else {
        unit.cell_end()
      }
    }
    None => line_cell_end + utf16_end - text.length()
  }
  (cell_start - start_column, cell_end - start_column)
}

///|
fn severity_name(severity : @diagnostic.DiagnosticSeverity) -> String {
  match severity {
    Error => "error"
    Warning => "warning"
    Info => "info"
    Hint => "hint"
  }
}

///|
fn label_name(style : @diagnostic.LabelStyle) -> String {
  match style {
    Primary => "primary"
    Secondary => "secondary"
  }
}

///|
fn label_marker(style : @diagnostic.LabelStyle) -> String {
  match style {
    Primary => "^"
    Secondary => "-"
  }
}

///|
fn label_style(style : @diagnostic.LabelStyle) -> DiagnosticStyle {
  match style {
    Primary => Primary
    Secondary => Secondary
  }
}

///|
fn validate_label(
  snapshot : @diagnostic.SourceSnapshot,
  label : @diagnostic.DiagnosticLabel,
) -> ValidatedLabel {
  let span = label.span()
  let range = span.range()
  let start = range.start().value()
  let end = range.end().value()
  { label, snapshot, line_range: snapshot.line_index().line_range(start, end) }
}

///|
priv struct CachingResolver[R] {
  resolver : R
  sources : Array[ResolvedSource]
}

///|
impl[R : @diagnostic.SourceResolver] @diagnostic.SourceResolver for CachingResolver[
  R,
] with fn resolve_source(self, source_id) {
  match self.sources.search_by(source => source.source_id == source_id) {
    Some(index) => Some(self.sources[index].snapshot)
    None =>
      match self.resolver.resolve_source(source_id) {
        Some(snapshot) => {
          self.sources.push({ source_id, snapshot })
          Some(snapshot)
        }
        None => None
      }
  }
}

///|
fn validated_groups(
  labels : Array[@diagnostic.DiagnosticLabel],
  sources : Array[ResolvedSource],
) -> Array[SourceGroup] {
  let groups : Array[SourceGroup] = []
  labels.each(label => {
    let source_id = label.span().source_id()
    match groups.search_by(group => group.source_id == source_id) {
      Some(index) => {
        let snapshot = groups[index].snapshot
        groups[index].labels.push(validate_label(snapshot, label))
      }
      None => {
        let snapshot = match
          sources.search_by(source => source.source_id == source_id) {
          Some(index) => sources[index].snapshot
          None => abort("core diagnostic validation must cache every source")
        }
        groups.push({
          source_id,
          snapshot,
          labels: [validate_label(snapshot, label)],
        })
      }
    }
  })
  groups
}

///|
fn header_layout(
  diagnostic : @diagnostic.Diagnostic,
  options : DiagnosticPrettyOptions,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let severity = diagnostic.severity()
  let severity_text = severity_name(severity)
  let severity_doc = @pretty.annotate(
    Severity(severity),
    measured_text(severity_text, options),
  )
  let code_doc = match diagnostic.code() {
    Some(code) =>
      measured_text("[", options) +
      @pretty.annotate(
        Code,
        report_text(
          code.value(),
          options,
          first_column=severity_text.length() + 1,
        ),
      ) +
      measured_text("]:", options)
    None => measured_text(":", options)
  }
  let prefix = severity_doc + code_doc
  let message = diagnostic.message()
  if contains_tab(message) {
    prefix +
    @pretty.nest(
      @pretty.hardline() +
      report_text(message, options, first_column=2, continuation_column=2),
    )
  } else {
    @pretty.group(
      prefix + @pretty.nest(@pretty.line() + report_text(message, options)),
    )
  }
}

///|
fn label_header_layout(
  validated : ValidatedLabel,
  options : DiagnosticPrettyOptions,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let label = validated.label
  let range = validated.line_range
  let base = label_name(label.style()) +
    " " +
    (range.start.line + 1).to_string() +
    ":" +
    (range.start.column + 1).to_string() +
    "-" +
    (range.end.line + 1).to_string() +
    ":" +
    (range.end.column + 1).to_string()
  let content = match label.message() {
    Some(message) => {
      let prefix = measured_text(base + ":", options)
      if contains_tab(message) {
        prefix +
        @pretty.nest(
          @pretty.hardline() +
          report_text(message, options, first_column=2, continuation_column=2),
        )
      } else {
        prefix + @pretty.nest(@pretty.line() + report_text(message, options))
      }
    }
    None => measured_text(base, options)
  }
  @pretty.annotate(label_style(label.style()), @pretty.group(content))
}

///|
fn source_and_marker_layout(
  validated : ValidatedLabel,
  line : Int,
  lines : Array[SourceLine],
  options : DiagnosticPrettyOptions,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let label = validated.label
  let line_range = validated.line_range
  let bounds = lines[line]
  let text = validated.snapshot.text()
  let line_view = match text.get_view(start=bounds.start, end=bounds.end) {
    Some(view) => view
    None => abort("validated source line must have UTF-16 boundaries")
  }
  let line_text = line_view.to_owned()
  let display_line = (line + 1).to_string()
  let gutter_width = 3 + display_line.length()
  let source_column_start = gutter_width + 2
  let units = display_units(line_text, source_column_start, options)
  let rendered_line = render_source_text(line_text, units)
  let source_gutter = "  " +
    display_line +
    " |" +
    (if bounds.end > bounds.start { " " } else { "" })
  let source_doc = @pretty.annotate(
      Gutter,
      measured_text(source_gutter, options),
    ) +
    measured_text(rendered_line, options, start_column=source_column_start)
  let marker_start = if line == line_range.start.line {
    line_range.start.column
  } else {
    0
  }
  let marker_end = if line == line_range.end.line {
    line_range.end.column
  } else {
    bounds.end - bounds.start
  }
  let (cell_start, cell_end) = projected_marker_cells(
    line_text, units, source_column_start, marker_start, marker_end,
  )
  let marker_width = if marker_end > marker_start {
    let width = cell_end - cell_start
    if width > 0 {
      width
    } else {
      1
    }
  } else {
    1
  }
  let marker_gutter = " ".repeat(gutter_width) + "| "
  let marker_doc = @pretty.annotate(
    label_style(label.style()),
    @pretty.annotate(Gutter, measured_text(marker_gutter, options)) +
    measured_text(" ".repeat(cell_start), options) +
    measured_text(label_marker(label.style()).repeat(marker_width), options),
  )
  source_doc + @pretty.hardline() + marker_doc
}

///|
fn label_layout(
  validated : ValidatedLabel,
  options : DiagnosticPrettyOptions,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let range = validated.line_range
  let label = validated.label
  let nonempty = label.span().range().length() > 0
  let last_line = if nonempty &&
    range.end.line > range.start.line &&
    range.end.column == 0 {
    range.end.line - 1
  } else {
    range.end.line
  }
  let lines = source_lines(validated.snapshot.text())
  let rendered_lines = Array::makei(last_line - range.start.line + 1, index => {
    source_and_marker_layout(
      validated,
      range.start.line + index,
      lines,
      options,
    )
  })
  label_header_layout(validated, options) +
  @pretty.hardline() +
  @pretty.separate(@pretty.hardline(), rendered_lines)
}

///|
fn source_group_layout(
  group : SourceGroup,
  options : DiagnosticPrettyOptions,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let source_header = @pretty.annotate(Gutter, measured_text("--> ", options)) +
    @pretty.annotate(
      SourceName,
      report_text(group.snapshot.name(), options, first_column=4),
    )
  let labels = group.labels.map(label => label_layout(label, options))
  source_header +
  @pretty.hardline() +
  @pretty.separate(@pretty.hardline(), labels)
}

///|
fn note_layout(
  note : String,
  options : DiagnosticPrettyOptions,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let prefix = measured_text("= note:", options)
  let content = if contains_tab(note) {
    prefix +
    @pretty.nest(
      @pretty.hardline() +
      report_text(note, options, first_column=2, continuation_column=2),
    )
  } else {
    @pretty.group(
      prefix + @pretty.nest(@pretty.line() + report_text(note, options)),
    )
  }
  @pretty.annotate(Note, content)
}

///|
/// Build a width-aware, semantically annotated diagnostic report layout.
pub fn[R : @diagnostic.SourceResolver] layout(
  diagnostic : @diagnostic.Diagnostic,
  resolver : R,
  options : DiagnosticPrettyOptions,
) -> @pretty.Layout[DiagnosticStyle] raise DiagnosticPrettyError {
  let cached = CachingResolver::{ resolver, sources: [] }
  diagnostic_error(() => ignore(diagnostic.render_plain(cached)))
  let groups = validated_groups(diagnostic.labels(), cached.sources)
  let with_sources = groups
    .iter()
    .fold(init=header_layout(diagnostic, options), (report, group) => {
      report + @pretty.hardline() + source_group_layout(group, options)
    })
  diagnostic
  .notes()
  .iter()
  .fold(init=with_sources, (report, note) => {
    report + @pretty.hardline() + note_layout(note, options)
  })
}
