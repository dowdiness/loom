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
priv struct SameLineListItemPrefixFacts {
  source : String
  line_start : Int
  line_end : Int
  prefix_end : Int
  list_marker_count : Int
}

///|
let same_line_list_item_prefix_cache : Ref[SameLineListItemPrefixFacts?] = Ref(
  None,
)

///|
fn scan_same_line_list_item_prefix(
  input : String,
  line_start : Int,
  line_end : Int,
) -> SameLineListItemPrefixFacts {
  let mut cursor = line_start
  let mut list_marker_count = 0
  while cursor < line_end {
    while cursor < line_end {
      match char_at(input, cursor) {
        Some(' ') | Some('\t') => cursor += 1
        _ => break
      }
    }
    if cursor >= line_end {
      break
    }
    match char_at(input, cursor) {
      Some('>') => {
        cursor += 1
        if cursor < line_end {
          match char_at(input, cursor) {
            Some(' ') | Some('\t') => cursor += 1
            _ => break
          }
        }
      }
      Some('-') | Some('*') | Some('+') =>
        match char_at(input, cursor + 1) {
          Some(' ') | Some('\t') => {
            cursor += 2
            list_marker_count += 1
          }
          _ => break
        }
      Some(ch) if is_decimal_digit(ch) => {
        let digits = count_ordered_marker_digits(input, cursor)
        match char_at(input, cursor + digits) {
          Some('.') | Some(')') =>
            match char_at(input, cursor + digits + 1) {
              Some(' ') | Some('\t') => {
                cursor += digits + 2
                list_marker_count += 1
              }
              _ => break
            }
          _ => break
        }
      }
      _ => break
    }
  }
  { source: input, line_start, line_end, prefix_end: cursor, list_marker_count }
}

///|
/// True when `pos` begins a block marker nested after a same-line list
/// marker. Prefix facts are cached per source line so ordinary inline text
/// does not rescan the line from its beginning on every lexer step.
fn same_line_list_item_prefix(input : String, pos : Int) -> Bool {
  let facts = match same_line_list_item_prefix_cache.val {
    Some(facts) if facts.line_start <= pos &&
      pos <= facts.line_end &&
      physical_equal(facts.source, input) => facts
    _ => {
      let line_start = line_start_offset(input, pos)
      let line_end = find_line_end(input, pos)
      let facts = scan_same_line_list_item_prefix(input, line_start, line_end)
      same_line_list_item_prefix_cache.val = Some(facts)
      facts
    }
  }
  facts.list_marker_count > 0 && pos <= facts.prefix_end
}

///|
fn same_line_list_item_content_start(input : String, pos : Int) -> Int? {
  let line_start = line_start_offset(input, pos)
  let (start, _) = leading_indent_end_offset_and_column(input, line_start, 0)
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
      match input.get_char(pos + 1) {
        Some(' ') | Some('\t') | Some('\r') | Some('\n') | None =>
          !is_valid_thematic_break_markers(input[pos:find_line_end(input, pos)])
        _ => false
      }
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
