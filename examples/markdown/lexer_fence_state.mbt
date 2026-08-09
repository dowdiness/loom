///|
priv struct SourceFenceCandidate {
  marker_start : Int
  run_len : Int
}

///|
priv struct SourceListMarkerFacts {
  marker_indent : Int
  content_indent : Int
}

///|
fn previous_source_line_start(input : String, line_start : Int) -> Int? {
  guard line_start > 0 else { return None }
  let break_start = if line_start >= 2 &&
    char_at(input, line_start - 2) == Some('\r') &&
    char_at(input, line_start - 1) == Some('\n') {
    line_start - 2
  } else {
    line_start - 1
  }
  if break_start == 0 {
    Some(0)
  } else {
    Some(line_start_offset(input, break_start))
  }
}

///|
fn source_line_list_marker_facts(
  input : String,
  line_start : Int,
  line_end : Int,
) -> SourceListMarkerFacts? {
  let (marker_start, marker_indent) = leading_indent_end_offset_and_column(
    input, line_start, 0,
  )
  let marker_end = match char_at(input, marker_start) {
    Some('-') | Some('*') | Some('+') =>
      if marker_start + 1 >= line_end ||
        char_at(input, marker_start + 1) is Some(' ' | '\t') {
        marker_start + 1
      } else {
        return None
      }
    Some(ch) if is_decimal_digit(ch) => {
      let digits = count_ordered_marker_digits(input, marker_start)
      guard digits > 0 else { return None }
      let delimiter_end = marker_start + digits + 1
      match char_at(input, marker_start + digits) {
        Some('.') | Some(')') => {
          guard delimiter_end >= line_end ||
            char_at(input, delimiter_end) is Some(' ' | '\t') else {
            return None
          }
          delimiter_end
        }
        _ => return None
      }
    }
    _ => return None
  }
  let marker_end_column = marker_indent + marker_end - marker_start
  let (_, content_column) = leading_indent_end_offset_and_column(
    input, marker_end, marker_end_column,
  )
  let padding = content_column - marker_end_column
  let content_indent = if padding == 0 || padding > 4 {
    marker_end_column + 1
  } else {
    content_column
  }
  Some(SourceListMarkerFacts::{ marker_indent, content_indent })
}

///|
/// True when an indented line is structurally owned by a preceding list item.
/// Root-level four-space code must not become a detached fence candidate, while
/// fences nested below a list marker still need their opening column recovered.
fn source_line_is_list_owned(
  input : String,
  line_start : Int,
  line_indent : Int,
) -> Bool {
  let mut cursor = line_start
  let mut required_indent = line_indent
  while cursor > 0 {
    let previous_start = previous_source_line_start(input, cursor).unwrap()
    let previous_end = find_line_end(input, previous_start)
    if line_is_blank(input, previous_start, previous_end) {
      cursor = previous_start
      continue
    }
    let (_, previous_indent) = leading_indent_end_offset_and_column(
      input, previous_start, 0,
    )
    match source_line_list_marker_facts(input, previous_start, previous_end) {
      Some(facts) if facts.content_indent <= required_indent &&
        required_indent < facts.content_indent + 4 => {
        if facts.marker_indent <= 3 {
          return true
        }
        required_indent = facts.marker_indent
        cursor = previous_start
        continue
      }
      Some(_) => return false
      None if previous_indent == 0 => return false
      None => cursor = previous_start
    }
  }
  false
}

///|
/// Find a fence marker at the start of a source line, after the line's
/// whitespace and block-container prefixes. This is only a source-derived
/// fallback for detached/public mode stepping; the stateful lexer records the
/// opening column when it enters CodeBlock mode.
fn source_fence_candidate(
  input : String,
  line_start : Int,
  line_end : Int,
  fence_len : Int,
  fence_character : Char,
) -> SourceFenceCandidate? {
  let (start, leading_indent) = leading_indent_end_offset_and_column(
    input, line_start, 0,
  )
  guard leading_indent <= 3 ||
    source_line_is_list_owned(input, line_start, leading_indent) else {
    return None
  }
  let mut cursor = start
  let mut scanning_prefix = true
  while scanning_prefix {
    scanning_prefix = false
    while cursor < line_end {
      match char_at(input, cursor) {
        Some(' ') | Some('\t') => cursor += 1
        _ => break
      }
    }
    match char_at(input, cursor) {
      Some('>') => {
        cursor += 1
        scanning_prefix = true
      }
      Some('-') | Some('*') | Some('+') if cursor + 1 < line_end =>
        match char_at(input, cursor + 1) {
          Some(' ') | Some('\t') => {
            cursor += 2
            scanning_prefix = true
          }
          _ => ()
        }
      Some(ch) if is_decimal_digit(ch) =>
        match ordered_list_marker_at(input, cursor) {
          Some(_) => {
            cursor += count_ordered_marker_digits(input, cursor) + 2
            scanning_prefix = true
          }
          None => ()
        }
      _ => ()
    }
  }
  while cursor < line_end {
    match char_at(input, cursor) {
      Some(' ') | Some('\t') => cursor += 1
      _ => break
    }
  }
  let marker_start = cursor
  let run_len = count_fence_characters(input, marker_start, fence_character)
  guard run_len >= fence_len else { return None }
  let info_start = marker_start + run_len
  if fence_character == '`' && input[info_start:line_end].contains("`") {
    return None
  }
  Some(SourceFenceCandidate::{ marker_start, run_len })
}

///|
/// The closing fence may be preceded by up to three literal spaces, or by
/// the opening indentation when that indentation is deeper.
fn code_block_max_leading_spaces(opening_indent : Int?) -> Int {
  match opening_indent {
    Some(indent) if indent >= 4 => indent
    _ => 3
  }
}

///|
/// Mirror lex_code_block's raw closing-fence rule for detached mode replay:
/// only literal leading spaces are skipped, and the fence tail must be blank.
fn source_code_block_close_candidate(
  input : String,
  line_start : Int,
  fence_len : Int,
  fence_character : Char,
  opening_indent : Int,
) -> Bool {
  let max_leading_spaces = code_block_max_leading_spaces(Some(opening_indent))
  let mut fence_start = line_start
  let mut leading_spaces = 0
  while leading_spaces < max_leading_spaces &&
        char_at(input, fence_start) is Some(' ') {
    fence_start += 1
    leading_spaces += 1
  }
  code_fence_close_end(input, fence_start, fence_len, fence_character)
  is Some(_)
}
