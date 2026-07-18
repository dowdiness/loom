///|
fn strip_payload_comments(source : String) -> String raise PayloadExprError {
  let out = StringBuilder()
  let segments = lex_payload_segments(source)
  for segment in segments {
    let text = source[segment.start:segment.end]
    match segment.kind {
      Code => out.write_string(text.to_owned())
      String => out.write_string(text.to_owned())
      MultilineString => out.write_string(text.to_owned())
      LineComment => {
        let mut i = segment.start
        while i < segment.end {
          if source.get_char(i).unwrap() == '\n' {
            out.write_char('\n')
          } else {
            out.write_char(' ')
          }
          i = @core.next_char_offset(source, i)
        }
      }
      BlockComment => {
        let mut i = segment.start
        while i < segment.end {
          if source.get_char(i).unwrap() == '\n' {
            out.write_char('\n')
          } else {
            out.write_char(' ')
          }
          i = @core.next_char_offset(source, i)
        }
      }
    }
  }
  out.to_string()
}

///|
/// Errors raised while lowering a `#loom.payload` expression.
suberror PayloadExprError {
  Invalid(String)
}

///|
/// Rewrite capture placeholders while preserving strings and comments.
fn rewrite_payload_expr(
  source : String,
  match_name : String,
) -> String raise PayloadExprError {
  let out = StringBuilder()
  let mut trailing_code_dot = false
  let segments = lex_payload_segments(source)
  for segment in segments {
    let text = source[segment.start:segment.end].to_owned()
    match segment.kind {
      Code => {
        let rewritten_code = rewrite_payload_code(text, match_name)
        let trimmed_code = rewritten_code.trim()
        if trimmed_code.length() > 0 {
          trailing_code_dot = trimmed_code.has_suffix(".")
        }
        out.write_string(rewritten_code)
      }
      String => out.write_string(text)
      LineComment => out.write_string(text)
      BlockComment => out.write_string(text)
      MultilineString => out.write_string(text)
    }
  }
  let rewritten = out.to_string()
  if trailing_code_dot {
    raise PayloadExprError::Invalid("payload expression ends with '.'")
  }
  let validation_source = strip_payload_comments(rewritten)
  let (_, diagnostics) = @parser.parse_string(
    "fn __loom_validate_payload() { let _ = (" + validation_source + "\n) }",
  )
  if diagnostics.length() > 0 {
    raise PayloadExprError::Invalid(diagnostics[0].msg)
  }
  rewritten
}

///|
fn rewrite_payload_code(
  source : String,
  match_name : String,
) -> String raise PayloadExprError {
  let out = StringBuilder()
  let mut i = 0
  let n = source.length()
  while i < n {
    let c = source.get_char(i).unwrap()
    if c == '$' {
      let start = i
      i = @core.next_char_offset(source, i)
      guard i < n else {
        raise PayloadExprError::Invalid("invalid capture placeholder")
      }
      let first = source.get_char(i).unwrap()
      guard first >= '0' && first <= '9' else {
        raise PayloadExprError::Invalid("invalid capture placeholder")
      }
      let mut index = 0
      while i < n {
        let digit = source.get_char(i).unwrap()
        guard digit >= '0' && digit <= '9' else { break }
        index = index * 10 + (digit.to_int() - '0'.to_int())
        i = @core.next_char_offset(source, i)
      }
      let suffix = if i < n && source.get_char(i).unwrap() == '_' {
        let suffix_start = i
        while i < n && source.get_char(i).unwrap() != '(' {
          i = @core.next_char_offset(source, i)
        }
        guard i < n &&
          i + 1 < n &&
          source.get_char(i).unwrap() == '(' &&
          source.get_char(i + 1).unwrap() == ')' else {
          raise PayloadExprError::Invalid("invalid capture placeholder")
        }
        let s = source[suffix_start:i].to_owned()
        i = @core.next_char_offset(source, i)
        i = @core.next_char_offset(source, i)
        s
      } else {
        ""
      }
      if suffix == "" && index == 0 {
        out.write_string(match_name + ".content()")
      } else if suffix == "" {
        out.write_string(
          match_name + ".group(" + index.to_string() + ").unwrap_or(\"\")",
        )
      } else if suffix == "_match_length" && index == 0 {
        out.write_string(match_name + ".content().length()")
      } else if suffix == "_start" {
        out.write_string(
          match_name +
          ".group(" +
          index.to_string() +
          ").map(fn(v) { v.start_offset() }).unwrap_or(0)",
        )
      } else if suffix == "_end" {
        out.write_string(
          match_name +
          ".group(" +
          index.to_string() +
          ").map(fn(v) { v.start_offset() + v.length() }).unwrap_or(0)",
        )
      } else {
        raise PayloadExprError::Invalid(
          "invalid capture placeholder at " + start.to_string(),
        )
      }
    } else {
      out.write_char(c)
      i = @core.next_char_offset(source, i)
    }
  }
  out.to_string()
}
