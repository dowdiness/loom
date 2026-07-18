///|
fn strip_payload_comments(source : String) -> String raise PayloadExprError {
  let out = StringBuilder()
  let mut i = 0
  let mut state = 0
  while i < source.length() {
    let c = source.get_char(i).unwrap()
    if state == 1 {
      out.write_char(c)
      if c == '\\' && i + 1 < source.length() {
        i += 1
        out.write_char(source.get_char(i).unwrap())
      } else if c == '"' {
        state = 0
      }
      i += 1
    } else if state == 2 {
      if c == '\n' {
        out.write_char(c)
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
    } else if state == 4 {
      out.write_char(c)
      i += 1
      if c == '\n' {
        let mut next = i
        while next < source.length() &&
              (
                source.get_char(next).unwrap() == ' ' ||
                source.get_char(next).unwrap() == '\t'
              ) {
          next += 1
        }
        if !(next + 1 < source.length() &&
          (
            source.get_char(next).unwrap() == '$' ||
            source.get_char(next).unwrap() == '#'
          ) &&
          source.get_char(next + 1).unwrap() == '|') {
          state = 0
        }
      }
    } else if (c == '$' || c == '#') &&
      i + 1 < source.length() &&
      source.get_char(i + 1).unwrap() == '|' {
      out.write_char(c)
      i += 1
      out.write_char('|')
      i += 1
      state = 4
    } else if c == '"' {
      out.write_char(c)
      state = 1
      i += 1
    } else if c == '/' &&
      i + 1 < source.length() &&
      source.get_char(i + 1).unwrap() == '/' {
      out.write_char(' ')
      i += 2
      state = 2
    } else if c == '/' &&
      i + 1 < source.length() &&
      source.get_char(i + 1).unwrap() == '*' {
      out.write_char(' ')
      i += 2
      state = 3
    } else {
      out.write_char(c)
      i += 1
    }
  }
  if state == 3 {
    raise PayloadExprError::Invalid("unterminated block comment")
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
  let mut i = 0
  let n = source.length()
  let mut state = 0 // 0 code, 1 string, 2 line comment, 3 block comment, 4 multiline string
  let mut trailing_code_dot = false
  while i < n {
    let c = source.get_char(i).unwrap()
    if state == 1 {
      out.write_char(c)
      if c == '\\' && i + 1 < n {
        i += 1
        out.write_char(source.get_char(i).unwrap())
      } else if c == '"' {
        state = 0
      }
      i += 1
    } else if state == 2 {
      out.write_char(c)
      i += 1
      if c == '\n' {
        state = 0
      }
    } else if state == 3 {
      out.write_char(c)
      if c == '*' && i + 1 < n && source.get_char(i + 1).unwrap() == '/' {
        i += 1
        out.write_char('/')
        state = 0
      }
      i += 1
    } else if state == 4 {
      out.write_char(c)
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
          state = 0
        }
      }
    } else if (c == '$' || c == '#') &&
      i + 1 < n &&
      source.get_char(i + 1).unwrap() == '|' {
      out.write_char(c)
      i += 1
      out.write_char('|')
      i += 1
      state = 4
    } else if c == '"' {
      out.write_char(c)
      state = 1
      i += 1
    } else if c == '/' && i + 1 < n && source.get_char(i + 1).unwrap() == '/' {
      out.write_char(c)
      i += 1
      out.write_char('/')
      i += 1
      state = 2
    } else if c == '/' && i + 1 < n && source.get_char(i + 1).unwrap() == '*' {
      out.write_char(c)
      i += 1
      out.write_char('*')
      i += 1
      state = 3
    } else if c == '$' {
      trailing_code_dot = false
      let start = i
      i += 1
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
        i += 1
      }
      let suffix = if i < n && source.get_char(i).unwrap() == '_' {
        let suffix_start = i
        while i < n && source.get_char(i).unwrap() != '(' {
          i += 1
        }
        guard i < n &&
          i + 1 < n &&
          source.get_char(i).unwrap() == '(' &&
          source.get_char(i + 1).unwrap() == ')' else {
          raise PayloadExprError::Invalid("invalid capture placeholder")
        }
        let s = source[suffix_start:i].to_owned()
        i += 2
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
      if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
        trailing_code_dot = c == '.'
      }
      i += 1
    }
  }
  let rewritten = out.to_string()
  let validation_source = strip_payload_comments(rewritten)
  let (_, diagnostics) = @parser.parse_string(
    "fn __loom_validate_payload() { let _ = (" + validation_source + "\n) }",
  )
  if trailing_code_dot {
    raise PayloadExprError::Invalid("payload expression ends with '.'")
  }
  if diagnostics.length() > 0 {
    raise PayloadExprError::Invalid(diagnostics[0].msg)
  }
  rewritten
}
