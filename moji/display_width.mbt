///|
/// Treatment of Unicode East Asian Ambiguous characters.
pub(all) enum AmbiguousWidth {
  Narrow
  Wide
} derive(Eq, Debug)

///|
pub(all) suberror DisplayWidthError {
  InvalidStartColumn(Int)
  InvalidTabWidth(Int)
} derive(Eq, Debug)

///|
/// Unicode data version used by the display-width implementation.
pub let display_width_unicode_version : (Int, Int, Int) = @unicodewidth.unicode_version

///|
fn AmbiguousWidth::is_cjk(self : AmbiguousWidth) -> Bool {
  self == Wide
}

///|
fn validate_display_width_args(
  start_column : Int,
  tab_width : Int,
) -> Unit raise DisplayWidthError {
  guard start_column >= 0 else { raise InvalidStartColumn(start_column) }
  guard tab_width > 0 else { raise InvalidTabWidth(tab_width) }
}

///|
/// One terminal display unit with half-open UTF-16 and cell-column ranges.
pub struct DisplayUnit {
  priv utf16_start_ : Int
  priv utf16_end_ : Int
  priv cell_start_ : Int
  priv cell_end_ : Int
} derive(Eq, Debug)

///|
fn DisplayUnit::DisplayUnit(
  utf16_start : Int,
  utf16_end : Int,
  cell_start : Int,
  cell_end : Int,
) -> DisplayUnit {
  {
    utf16_start_: utf16_start,
    utf16_end_: utf16_end,
    cell_start_: cell_start,
    cell_end_: cell_end,
  }
}

///|
pub fn DisplayUnit::utf16_start(self : DisplayUnit) -> Int {
  self.utf16_start_
}

///|
pub fn DisplayUnit::utf16_end(self : DisplayUnit) -> Int {
  self.utf16_end_
}

///|
pub fn DisplayUnit::cell_start(self : DisplayUnit) -> Int {
  self.cell_start_
}

///|
pub fn DisplayUnit::cell_end(self : DisplayUnit) -> Int {
  self.cell_end_
}

///|
/// Append one completed unit and return the next absolute display column.
fn append_display_unit(
  units : Array[DisplayUnit],
  utf16_start : Int,
  utf16_end : Int,
  width : Int,
  column : Int,
) -> Int {
  units.push(DisplayUnit(utf16_start, utf16_end, column, column + width))
  column + width
}

///|
/// Reconcile a tab-delimited segment against the width library's complete
/// state machine. Some Unicode sequences become non-additive only after three
/// or more graphemes, so pairwise grouping alone cannot prove additivity.
fn reconcile_display_segment(
  units : Array[DisplayUnit],
  text : String,
  utf16_start : Int,
  utf16_end : Int,
  unit_start : Int,
  cell_start : Int,
  column : Int,
  ambiguous_width : AmbiguousWidth,
) -> Int {
  if utf16_start == utf16_end {
    column
  } else {
    let width = @unicodewidth.str_width(
      text.view(start_offset=utf16_start, end_offset=utf16_end),
      cjk=ambiguous_width.is_cjk(),
    )
    if width == column - cell_start {
      column
    } else {
      units.truncate(unit_start)
      append_display_unit(units, utf16_start, utf16_end, width, cell_start)
    }
  }
}

///|
/// Map one display run from UTF-16 grapheme ranges to terminal-cell ranges.
/// A tab-delimited segment is returned as one unit when longer Unicode context
/// makes its complete width differ from the sum of smaller candidate units.
pub fn display_units(
  text : String,
  start_column? : Int = 0,
  tab_width? : Int = 4,
  ambiguous_width? : AmbiguousWidth = Narrow,
) -> Array[DisplayUnit] raise DisplayWidthError {
  validate_display_width_args(start_column, tab_width)
  let units : Array[DisplayUnit] = []
  // `column` is the accumulated display state; local mutation only builds the
  // returned immutable value sequence.
  let mut column = start_column
  // Adjacent graphemes can form a non-additive terminal unit (for example an
  // Arabic lam-alef ligature). This local state machine keeps the smallest
  // pending run whose combined width has not yet proved additive.
  let mut pending_start = 0
  let mut pending_end = 0
  let mut pending_width = 0
  let mut has_pending = false
  let mut segment_utf16_start = 0
  let mut segment_unit_start = 0
  let mut segment_cell_start = start_column
  for cluster in grapheme_clusters(text) {
    let (start, end) = cluster
    let view = text.view(start_offset=start, end_offset=end)
    if view.equal_to_string("\t") {
      if has_pending {
        column = append_display_unit(
          units, pending_start, pending_end, pending_width, column,
        )
        has_pending = false
      }
      column = reconcile_display_segment(
        units, text, segment_utf16_start, start, segment_unit_start, segment_cell_start,
        column, ambiguous_width,
      )
      let tab_cell_width = tab_width - column % tab_width
      column = append_display_unit(units, start, end, tab_cell_width, column)
      segment_utf16_start = end
      segment_unit_start = units.length()
      segment_cell_start = column
    } else if !has_pending {
      pending_start = start
      pending_end = end
      pending_width = @unicodewidth.str_width(
        view,
        cjk=ambiguous_width.is_cjk(),
      )
      has_pending = true
    } else {
      let grapheme_width = @unicodewidth.str_width(
        view,
        cjk=ambiguous_width.is_cjk(),
      )
      let combined_width = @unicodewidth.str_width(
        text.view(start_offset=pending_start, end_offset=end),
        cjk=ambiguous_width.is_cjk(),
      )
      if combined_width == pending_width + grapheme_width {
        column = append_display_unit(
          units, pending_start, pending_end, pending_width, column,
        )
        pending_start = start
        pending_end = end
        pending_width = grapheme_width
      } else {
        pending_end = end
        pending_width = combined_width
      }
    }
  }
  if has_pending {
    column = append_display_unit(
      units, pending_start, pending_end, pending_width, column,
    )
  }
  ignore(
    reconcile_display_segment(
      units,
      text,
      segment_utf16_start,
      text.length(),
      segment_unit_start,
      segment_cell_start,
      column,
      ambiguous_width,
    ),
  )
  units
}

///|
/// Return the terminal cells consumed by one display run.
pub fn display_width(
  text : String,
  start_column? : Int = 0,
  tab_width? : Int = 4,
  ambiguous_width? : AmbiguousWidth = Narrow,
) -> Int raise DisplayWidthError {
  let units = display_units(text, start_column~, tab_width~, ambiguous_width~)
  match units.last() {
    Some(unit) => unit.cell_end() - start_column
    None => 0
  }
}
