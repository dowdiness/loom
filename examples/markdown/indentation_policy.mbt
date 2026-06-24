///|
/// CommonMark indentation helpers. Tabs advance to the next 4-column stop
/// before block-start and container-relative indentation rules are applied.
const COMMONMARK_TAB_STOP = 4

///|
fn next_tab_stop(col : Int) -> Int {
  (col / COMMONMARK_TAB_STOP + 1) * COMMONMARK_TAB_STOP
}

///|
/// Count visual indentation columns with CommonMark 4-column tab stops.
fn count_indent_columns(input : String, start : Int, end : Int) -> Int {
  input[start:end].fold(init=0, (col, ch) => {
    match ch {
      ' ' => col + 1
      '\t' => next_tab_stop(col)
      _ => col + 1
    }
  })
}

///|
fn leading_indent_end_offset_and_column(
  text : String,
  pos : Int,
  start_col : Int,
) -> (Int, Int) {
  for i = pos, col = start_col; i < text.length(); {
    match char_at(text, i) {
      Some(' ') => continue @core.next_char_offset(text, i), col + 1
      Some('\t') => continue @core.next_char_offset(text, i), next_tab_stop(col)
      _ => break (i, col)
    }
  } nobreak {
    (i, col)
  }
}

///|
fn leading_indent_columns_from(text : StringView, start_col : Int) -> Int {
  for ch in text; col = start_col {
    match ch {
      ' ' => continue col + 1
      '\t' => continue next_tab_stop(col)
      _ => break col - start_col
    }
  } nobreak {
    col - start_col
  }
}

///|
/// Count visual columns of leading whitespace using CommonMark 4-column tab
/// stops. Stops at the first non-space, non-tab character.
fn count_leading_indent(text : StringView) -> Int {
  leading_indent_columns_from(text, 0)
}

///|
fn marker_start_after_optional_indent(text : String, pos : Int) -> Int? {
  let (offset, _) = leading_indent_end_offset_and_column(text, pos, 0)
  Some(offset)
}

///|
fn marker_indent_columns_after_optional_indent(
  text : String,
  pos : Int,
) -> Int? {
  let (_, col) = leading_indent_end_offset_and_column(text, pos, 0)
  Some(col)
}

///|
fn list_marker_body_end_offset(text : String, ordered~ : Bool) -> Int? {
  guard marker_start_after_optional_indent(text, 0) is Some(start) else {
    return None
  }
  if ordered {
    let digits = count_ordered_marker_digits(text, start)
    guard digits > 0 else { return None }
    Some(start + digits + 1)
  } else {
    Some(start + 1)
  }
}

///|
fn line_start_offset_before(source : String, offset : Int) -> Int {
  for i = offset - 1 {
    guard i >= 0 else { break 0 }
    match char_at(source, i) {
      Some('\n') | Some('\r') => break i + 1
      _ => continue i - 1
    }
  }
}

///|
fn visual_column_at_offset(source : String, offset : Int) -> Int {
  count_indent_columns(source, line_start_offset_before(source, offset), offset)
}

///|
fn strip_visual_columns(
  text : String,
  start_col : Int,
  columns : Int,
) -> String {
  let buf = StringBuilder::new()
  let target = start_col + columns
  let mut col = start_col
  // Mutable stripping state is intentional: tabs can overshoot the target
  // column, leaving residual spaces before copying the remainder verbatim.
  let mut stripping = true
  for ch in text {
    let next_col = match ch {
      '\t' => next_tab_stop(col)
      _ => col + 1
    }
    if stripping && col < target {
      match ch {
        ' ' => ()
        '\t' =>
          if next_col > target {
            buf.write_string(" ".repeat(next_col - target))
            stripping = false
          }
        _ => {
          buf.write_char(ch)
          stripping = false
        }
      }
    } else {
      buf.write_char(ch)
      stripping = false
    }
    col = next_col
  }
  buf.to_string()
}
