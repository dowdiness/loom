///|
/// A source position expressed as a 0-based line and UTF-16/code-unit column.
pub(all) struct LineCol {
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// A source range expressed in line/column coordinates.
pub(all) struct LineRange {
  start : LineCol
  end : LineCol
} derive(Eq, Debug)

///|
/// Derived index that maps canonical source offsets to line/column positions.
///
/// Offsets are UTF-16 code-unit offsets, matching `Edit`, `TokenInfo.len`,
/// token starts, and CST text lengths.
pub struct LineIndex {
  priv line_starts : Array[Int]
  priv source_len : Int
}

///|
pub fn LineIndex::new(source : String) -> LineIndex {
  let line_starts : Array[Int] = []
  line_starts.push(0)
  let len = source.length()
  let mut pos = 0
  while pos < len {
    match source.view(start_offset=pos) {
      ['\r', '\n', .. rest] => {
        pos = rest.start_offset()
        line_starts.push(pos)
      }
      ['\n', .. rest] | ['\r', .. rest] => {
        pos = rest.start_offset()
        line_starts.push(pos)
      }
      _ => pos = next_char_offset(source, pos)
    }
  }
  { line_starts, source_len: len }
}

///|
pub fn LineIndex::line_col(self : LineIndex, offset : Int) -> LineCol {
  let clamped = line_index_clamp_offset(offset, self.source_len)
  let line = line_index_for_offset(self.line_starts, clamped)
  let line_start = self.line_starts[line]
  { line, column: clamped - line_start }
}

///|
pub fn LineIndex::line_range(
  self : LineIndex,
  start : Int,
  end : Int,
) -> LineRange {
  { start: self.line_col(start), end: self.line_col(end) }
}

///|
fn line_index_clamp_offset(offset : Int, source_len : Int) -> Int {
  if offset < 0 {
    0
  } else if offset > source_len {
    source_len
  } else {
    offset
  }
}

///|
fn line_index_for_offset(line_starts : Array[Int], offset : Int) -> Int {
  let len = line_starts.length()
  if len == 0 {
    return 0
  }
  let mut lo = 0
  let mut hi = len
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if line_starts[mid] <= offset {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo > 0 {
    lo - 1
  } else {
    0
  }
}
