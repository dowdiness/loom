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
      if c == '\\' {
        let next = @core.next_char_offset(source, i)
        i = if next < n { @core.next_char_offset(source, next) } else { next }
      } else if c == '"' {
        i = @core.next_char_offset(source, i)
        flush(String, i)
        state = 0
      } else {
        i = @core.next_char_offset(source, i)
      }
    } else if state == 2 {
      i = @core.next_char_offset(source, i)
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
        i = @core.next_char_offset(source, i)
      }
    } else if state == 4 {
      i = @core.next_char_offset(source, i)
      if c == '\n' {
        let mut next = i
        while next < n &&
              (
                source.get_char(next).unwrap() == ' ' ||
                source.get_char(next).unwrap() == '\t'
              ) {
          next = @core.next_char_offset(source, next)
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
      i = @core.next_char_offset(source, i)
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
      i = @core.next_char_offset(source, i)
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
