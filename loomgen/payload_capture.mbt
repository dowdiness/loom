///|
/// Find the largest capture index referenced outside strings/comments.
fn max_payload_capture_index(source : String) -> Int {
  let mut max = -1
  let segments = lex_payload_segments(source) catch { _ => return max }
  for segment in segments {
    if segment.kind != Code {
      continue
    }
    let mut i = segment.start
    while i < segment.end {
      if source.get_char(i).unwrap() == '$' {
        i = @core.next_char_offset(source, i)
        let mut value = 0
        let mut found = false
        while i < segment.end {
          let digit = source.get_char(i).unwrap()
          if digit < '0' || digit > '9' {
            break
          }
          found = true
          value = value * 10 + digit.to_int() - '0'.to_int()
          i = @core.next_char_offset(source, i)
        }
        if found && value > max {
          max = value
        }
      } else {
        i = @core.next_char_offset(source, i)
      }
    }
  }
  max
}
