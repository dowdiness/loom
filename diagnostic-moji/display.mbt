///|
priv struct MojiTextDisplay {}

///|
fn diagnostic_display_units(
  text : String,
  start_column : Int,
) -> Array[@moji.DisplayUnit] {
  try @moji.display_units(text, start_column~, tab_width=4) catch {
    _ => abort("diagnostic display-width context must be valid")
  } noraise {
    units => units
  }
}

///|
fn render_display_line(text : String, start_column : Int) -> String {
  let builder = StringBuilder()
  diagnostic_display_units(text, start_column).each(unit => {
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
fn marker_cells(
  text : String,
  start_column : Int,
  utf16_start : Int,
  utf16_end : Int,
) -> (Int, Int) {
  let units = diagnostic_display_units(text, start_column)
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
impl @diagnostic.TextDisplay for MojiTextDisplay with fn render_line(
  _,
  text,
  start_column,
) {
  render_display_line(text, start_column)
}

///|
impl @diagnostic.TextDisplay for MojiTextDisplay with fn marker_cells(
  _,
  text,
  start_column,
  utf16_start,
  utf16_end,
) {
  marker_cells(text, start_column, utf16_start, utf16_end)
}

///|
/// Render one diagnostic with grapheme-aware Unicode display cells.
pub fn[R : @diagnostic.SourceResolver] render_plain(
  diagnostic : @diagnostic.Diagnostic,
  resolver : R,
) -> String raise @diagnostic.DiagnosticRenderError {
  diagnostic.render_plain_with_display(resolver, MojiTextDisplay::{  })
}

///|
/// Render ordered diagnostics while resolving each source once.
pub fn[R : @diagnostic.SourceResolver] render_diagnostics_plain(
  diagnostics : ArrayView[@diagnostic.Diagnostic],
  resolver : R,
) -> String raise @diagnostic.DiagnosticRenderError {
  @diagnostic.render_diagnostics_plain_with_display(diagnostics, resolver, MojiTextDisplay::{

  })
}
