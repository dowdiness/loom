///|
fn line_end_offset(source : String, start : Int, limit : Int) -> Int {
  let mut pos = start
  while pos < limit {
    match char_at(source, pos) {
      Some('\r') | Some('\n') | None => break
      _ => pos = @core.next_char_offset(source, pos)
    }
  }
  pos
}

///|
fn next_line_start(source : String, line_end : Int, limit : Int) -> Int {
  if line_end < limit {
    match source.view(start_offset=line_end) {
      ['\r', '\n', .. rest] => rest.start_offset()
      ['\r', .. rest] | ['\n', .. rest] => rest.start_offset()
      _ => limit
    }
  } else {
    limit
  }
}

///|
fn code_fence_close_line_start(
  origin : MarkdownIROrigin,
  source : String,
) -> Int? {
  let fence_len = count_backticks(source, origin.start())
  guard fence_len >= 3 else { return None }
  let open_line_end = line_end_offset(source, origin.start(), origin.end())
  let mut line_start = next_line_start(source, open_line_end, origin.end())
  while line_start < origin.end() {
    let ticks = count_backticks(source, line_start)
    let marker_end = line_start + ticks
    if ticks >= fence_len {
      let line_end = line_end_offset(source, marker_end, origin.end())
      let mut is_close = true
      let mut pos = marker_end
      while pos < line_end {
        match char_at(source, pos) {
          Some(' ') | Some('\t') => pos = @core.next_char_offset(source, pos)
          _ => {
            is_close = false
            break
          }
        }
      }
      if is_close {
        return Some(line_start)
      }
    }
    let line_end = line_end_offset(source, line_start, origin.end())
    line_start = next_line_start(source, line_end, origin.end())
  }
  None
}
