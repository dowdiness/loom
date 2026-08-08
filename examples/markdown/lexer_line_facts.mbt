///|
fn line_start_offset(input : String, pos : Int) -> Int {
  for i = pos - 1 {
    match char_at(input, i) {
      Some('\r') | Some('\n') => break i + 1
      None => break 0
      _ => continue i - 1
    }
  } nobreak {
    0
  }
}

///|
/// True when `pos` begins a block marker nested after a same-line list
/// marker. The lexer remains in Inline mode after a list marker, so this
/// narrow source-local fact reuses the existing block token kinds without
/// making Inline a second container parser.
fn same_line_list_item_prefix(input : String, pos : Int) -> Bool {
  let start = line_start_offset(input, pos)
  let mut cursor = start
  let mut list_marker_count = 0
  while cursor < pos {
    while cursor < pos {
      match char_at(input, cursor) {
        Some(' ') | Some('\t') => cursor += 1
        _ => break
      }
    }
    if cursor >= pos {
      return list_marker_count > 0
    }
    match char_at(input, cursor) {
      Some('>') => {
        cursor += 1
        if cursor < pos {
          match char_at(input, cursor) {
            Some(' ') | Some('\t') => cursor += 1
            _ => return false
          }
        }
      }
      Some('-') | Some('*') | Some('+') => {
        guard cursor + 1 < pos else { return false }
        match char_at(input, cursor + 1) {
          Some(' ') | Some('\t') => {
            cursor += 2
            list_marker_count += 1
          }
          _ => return false
        }
      }
      Some(ch) if is_decimal_digit(ch) => {
        let digits = count_ordered_marker_digits(input, cursor)
        guard digits > 0 && cursor + digits + 1 < pos else { return false }
        match char_at(input, cursor + digits) {
          Some('.') | Some(')') =>
            match char_at(input, cursor + digits + 1) {
              Some(' ') | Some('\t') => {
                cursor += digits + 2
                list_marker_count += 1
              }
              _ => return false
            }
          _ => return false
        }
      }
      _ => return false
    }
  }
  list_marker_count > 0
}

///|
fn same_line_list_item_content_start(input : String, pos : Int) -> Int? {
  let start = line_start_offset(input, pos)
  match input.get_char(start) {
    Some('-') | Some('*') | Some('+') =>
      match input.get_char(start + 1) {
        Some(' ') | Some('\t') => Some(start + 2)
        _ => None
      }
    Some(ch) if is_decimal_digit(ch) =>
      match ordered_list_marker_at(input, start) {
        Some(_) => Some(start + count_ordered_marker_digits(input, start) + 2)
        None => None
      }
    _ => None
  }
}

///|
fn same_line_list_item_line_is_thematic_break(
  input : String,
  pos : Int,
) -> Bool {
  match same_line_list_item_content_start(input, pos) {
    Some(content_start) =>
      is_valid_thematic_break_markers(
        input[content_start:find_line_end(input, pos)],
      )
    None => false
  }
}

///|
fn same_line_list_item_block_start(input : String, pos : Int) -> Bool {
  match input.get_char(pos) {
    Some('-') | Some('*') | Some('+') =>
      !is_valid_thematic_break_markers(input[pos:find_line_end(input, pos)]) &&
      (match input.get_char(pos + 1) {
        Some(' ') | Some('\t') | Some('\r') | Some('\n') | None => true
        _ => false
      })
    Some(ch) if is_decimal_digit(ch) =>
      ordered_list_marker_at(input, pos) is Some(_)
    Some('#') => {
      let count = count_hashes(input, pos)
      match input.get_char(pos + count) {
        Some(' ') | Some('\t') | Some('\r') | Some('\n') | None =>
          count > 0 && count <= 6
        _ => false
      }
    }
    Some('>') => true
    Some('`') => count_fence_characters(input, pos, '`') >= 3
    Some('~') => count_fence_characters(input, pos, '~') >= 3
    _ => false
  }
}
