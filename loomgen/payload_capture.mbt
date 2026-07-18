///|
/// Find the largest capture index referenced outside strings/comments.
fn max_payload_capture_index(source : String) -> Int {
  let mut max = -1
  let mut i = 0
  let mut state = 0
  while i < source.length() {
    let c = source.get_char(i).unwrap()
    if state == 1 {
      if c == '\\' {
        i += 2
      } else {
        if c == '"' {
          state = 0
        }
        i += 1
      }
    } else if state == 2 {
      if c == '\n' {
        state = 0
      }
      i += 1
    } else if state == 3 {
      if c == '*' &&
        i + 1 < source.length() &&
        source.get_char(i + 1).unwrap() == '/' {
        i += 2
        state = 0
      } else {
        i += 1
      }
    } else if c == '"' {
      state = 1
      i += 1
    } else if c == '/' &&
      i + 1 < source.length() &&
      source.get_char(i + 1).unwrap() == '/' {
      state = 2
      i += 2
    } else if c == '/' &&
      i + 1 < source.length() &&
      source.get_char(i + 1).unwrap() == '*' {
      state = 3
      i += 2
    } else if c == '$' {
      i += 1
      let mut value = 0
      let mut found = false
      while i < source.length() {
        let digit = source.get_char(i).unwrap()
        if digit < '0' || digit > '9' {
          break
        }
        found = true
        value = value * 10 + digit.to_int() - '0'.to_int()
        i += 1
      }
      if found && value > max {
        max = value
      }
    } else {
      i += 1
    }
  }
  max
}
