///|
priv struct SourceFenceCandidate {
  marker_start : Int
  run_len : Int
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
  let (start, _) = leading_indent_end_offset_and_column(input, line_start, 0)
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
/// Mirror lex_code_block's raw closing-fence rule for detached mode replay:
/// only literal leading spaces are skipped, and the fence tail must be blank.
fn source_code_block_close_candidate(
  input : String,
  line_start : Int,
  fence_len : Int,
  fence_character : Char,
  opening_indent : Int,
) -> Bool {
  let max_leading_spaces = if opening_indent >= 4 { opening_indent } else { 3 }
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

///|
/// Recover the active fence's opening column by scanning source lines. The
/// scan models only fence open/close ownership, which is sufficient for a
/// detached CodeBlock mode and avoids making the public mode carry context.
fn source_derived_code_block_indent(
  input : String,
  pos : Int,
  fence_len : Int,
  fence_character : Char,
) -> Int? {
  let current_line_start = line_start_offset(input, pos)
  let mut scan = 0
  let mut active : (Int, Char, Int)? = None
  while scan < current_line_start {
    let line_end = find_line_end(input, scan)
    match active {
      None =>
        match
          source_fence_candidate(
            input, scan, line_end, fence_len, fence_character,
          ) {
          Some(candidate) =>
            active = Some(
              (
                candidate.run_len,
                fence_character,
                count_indent_columns(input, scan, candidate.marker_start),
              ),
            )
          None => ()
        }
      Some((open_len, open_character, opening_indent)) if source_code_block_close_candidate(
          input, scan, open_len, open_character, opening_indent,
        ) => active = None
      _ => ()
    }
    let next = line_end_including_break(input, line_end)
    if next <= scan {
      break
    }
    scan = next
  }
  if active is None {
    let line_end = find_line_end(input, current_line_start)
    match
      source_fence_candidate(
        input, current_line_start, line_end, fence_len, fence_character,
      ) {
      Some(candidate) if candidate.marker_start <= pos =>
        active = Some(
          (
            candidate.run_len,
            fence_character,
            count_indent_columns(
              input,
              current_line_start,
              candidate.marker_start,
            ),
          ),
        )
      _ => ()
    }
  }
  match active {
    Some((open_len, open_character, opening_indent)) if open_len == fence_len &&
      open_character == fence_character => Some(opening_indent)
    _ => None
  }
}
