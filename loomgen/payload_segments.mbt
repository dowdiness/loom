///|
enum PayloadSegmentKind {
  Code
  String
  LineComment
  BlockComment
  MultilineString
} derive(Eq)

///|
struct PayloadSegment {
  kind : PayloadSegmentKind
  start : Int
  end : Int
}

///|
fn lex_payload_segments(
  source : String,
) -> Array[PayloadSegment] raise PayloadExprError {
  let segments : Array[PayloadSegment] = []
  let mut state = 0
  let mut segment_start = 0
  let mut i = 0
  let n = source.length()
  let flush = (kind : PayloadSegmentKind, end : Int) => {
    if end > segment_start {
      segments.push({ kind, start: segment_start, end })
    }
    segment_start = end
  }
  while i < n {
    let c = source.get_char(i).unwrap()
    if state == 1 {
      if c == '\\' && i + 1 < n {
        i += 2
      } else if c == '"' {
        i += 1
        flush(String, i)
        state = 0
      } else {
        i += 1
      }
    } else if state == 2 {
      i += 1
      if c == '\n' {
        flush(LineComment, i)
        state = 0
      }
    } else if state == 3 {
      if c == '*' && i + 1 < n && source.get_char(i + 1).unwrap() == '/' {
        i += 2
        flush(BlockComment, i)
        state = 0
      } else {
        i += 1
      }
    } else if state == 4 {
      i += 1
      if c == '\n' {
        let mut next = i
        while next < n &&
              (
                source.get_char(next).unwrap() == ' ' ||
                source.get_char(next).unwrap() == '\t'
              ) {
          next += 1
        }
        if !(next + 1 < n &&
          (
            source.get_char(next).unwrap() == '$' ||
            source.get_char(next).unwrap() == '#'
          ) &&
          source.get_char(next + 1).unwrap() == '|') {
          flush(MultilineString, i)
          state = 0
        }
      }
    } else if c == '"' {
      flush(Code, i)
      state = 1
      segment_start = i
      i += 1
    } else if (c == '$' || c == '#') &&
      i + 1 < n &&
      source.get_char(i + 1).unwrap() == '|' {
      flush(Code, i)
      state = 4
      segment_start = i
      i += 2
    } else if c == '/' && i + 1 < n && source.get_char(i + 1).unwrap() == '/' {
      flush(Code, i)
      state = 2
      segment_start = i
      i += 2
    } else if c == '/' && i + 1 < n && source.get_char(i + 1).unwrap() == '*' {
      flush(Code, i)
      state = 3
      segment_start = i
      i += 2
    } else {
      i += 1
    }
  }
  if state == 3 {
    raise PayloadExprError::Invalid("unterminated block comment")
  }
  let final_kind = match state {
    0 => Code
    1 => String
    2 => LineComment
    3 => BlockComment
    4 => MultilineString
    _ => Code
  }
  flush(final_kind, n)
  segments
}
