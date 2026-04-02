// Step-based lexer for JSON tokens

///|
fn is_digit(code : Int) -> Bool {
  code >= 48 && code <= 57 // '0'..'9'
}

///|
fn is_hex_digit(code : Int) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 70) ||
  (code >= 97 && code <= 102)
}

///|
fn is_whitespace_char(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn read_string(input : String, pos : Int) -> (Int, String?) {
  // pos points at the opening '"'
  let mut i = pos + 1
  let len = input.length()
  while i < len {
    let code = input.code_unit_at(i).to_int()
    match code.to_char() {
      Some('"') => {
        let end = i + 1
        return (end, None)
      }
      Some('\\') => {
        // Skip escape sequence
        i = i + 1
        if i >= len {
          return (i, Some("unterminated string"))
        }
        let esc_code = input.code_unit_at(i).to_int()
        match esc_code.to_char() {
          Some('u') => {
            // \uXXXX — need 4 hex digits
            i = i + 1
            let mut hex_count = 0
            while hex_count < 4 && i < len {
              if is_hex_digit(input.code_unit_at(i).to_int()) {
                hex_count = hex_count + 1
                i = i + 1
              } else {
                break
              }
            }
            if hex_count != 4 {
              return (i, Some("Invalid \\u escape"))
            }
          }
          Some('"')
          | Some('\\')
          | Some('/')
          | Some('b')
          | Some('f')
          | Some('n')
          | Some('r')
          | Some('t') => i = i + 1
          _ => return (i + 1, Some("Invalid escape sequence"))
        }
      }
      _ => {
        if code >= 0 && code <= 0x1F {
          return (i, Some("Invalid control character in string"))
        }
        i = i + 1
      }
    }
  }
  // Reached end without closing quote
  (i, Some("unterminated string"))
}

///|
fn read_number(input : String, pos : Int) -> Int {
  let len = input.length()
  let mut i = pos
  // Optional leading '-'
  if i < len {
    match input.code_unit_at(i).to_char() {
      Some('-') => i = i + 1
      _ => ()
    }
  }
  // Integer part
  if i < len {
    let code = input.code_unit_at(i).to_int()
    if code == 48 {
      // '0' — just consume it (no leading zeros allowed after 0)
      i = i + 1
    } else if code >= 49 && code <= 57 {
      // '1'..'9'
      i = i + 1
      while i < len && is_digit(input.code_unit_at(i).to_int()) {
        i = i + 1
      }
    }
  }
  // Optional fraction
  if i < len {
    match input.code_unit_at(i).to_char() {
      Some('.') =>
        // Check next char is a digit before consuming '.'
        if i + 1 < len && is_digit(input.code_unit_at(i + 1).to_int()) {
          i = i + 1 // consume '.'
          while i < len && is_digit(input.code_unit_at(i).to_int()) {
            i = i + 1
          }
        }
      // else: don't consume '.', it's not part of the number
      _ => ()
    }
  }
  // Optional exponent
  if i < len {
    match input.code_unit_at(i).to_char() {
      Some('e') | Some('E') => {
        let saved = i
        i = i + 1 // consume 'e'/'E'
        if i < len {
          match input.code_unit_at(i).to_char() {
            Some('+') | Some('-') => i = i + 1
            _ => ()
          }
        }
        if i < len && is_digit(input.code_unit_at(i).to_int()) {
          // Valid exponent — consume digits
          while i < len && is_digit(input.code_unit_at(i).to_int()) {
            i = i + 1
          }
        } else {
          // No digit after exponent — restore
          i = saved
        }
      }
      _ => ()
    }
  }
  i
}

///|
fn check_keyword(input : String, pos : Int, keyword : String) -> Bool {
  let len = input.length()
  let klen = keyword.length()
  if pos + klen > len {
    return false
  }
  let mut i = 0
  while i < klen {
    if input.code_unit_at(pos + i) != keyword.code_unit_at(i) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Step-based lexer: returns one LexStep per call.
fn step_lex(input : String, pos : Int) -> @core.LexStep[Token] {
  if pos >= input.length() {
    return Done
  }
  let c = input.code_unit_at(pos).to_char()
  match c {
    Some('{') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(LBrace, 1),
        next_offset=pos + 1,
      )
    Some('}') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(RBrace, 1),
        next_offset=pos + 1,
      )
    Some('[') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(LBracket, 1),
        next_offset=pos + 1,
      )
    Some(']') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(RBracket, 1),
        next_offset=pos + 1,
      )
    Some(':') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(Colon, 1),
        next_offset=pos + 1,
      )
    Some(',') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(Comma, 1),
        next_offset=pos + 1,
      )
    Some(ws) if is_whitespace_char(ws) => {
      let mut end = pos + 1
      while end < input.length() {
        match input.code_unit_at(end).to_char() {
          Some(ch) if is_whitespace_char(ch) => end = end + 1
          _ => break
        }
      }
      @core.LexStep::Produced(
        @core.TokenInfo::new(Whitespace, end - pos),
        next_offset=end,
      )
    }
    Some('"') => {
      let (end, err) = read_string(input, pos)
      match err {
        Some(msg) =>
          @core.LexStep::Produced(
            @core.TokenInfo::new(Error(msg), end - pos),
            next_offset=end,
          )
        None =>
          @core.LexStep::Produced(
            @core.TokenInfo::new(StringLit, end - pos),
            next_offset=end,
          )
      }
    }
    Some('-') =>
      // Could be a number if followed by a digit
      if pos + 1 < input.length() &&
        is_digit(input.code_unit_at(pos + 1).to_int()) {
        let end = read_number(input, pos)
        @core.LexStep::Produced(
          @core.TokenInfo::new(NumberLit, end - pos),
          next_offset=end,
        )
      } else {
        @core.LexStep::Produced(
          @core.TokenInfo::new(Error("Unexpected character: -"), 1),
          next_offset=pos + 1,
        )
      }
    Some(d) if is_digit(d.to_int()) => {
      let end = read_number(input, pos)
      @core.LexStep::Produced(
        @core.TokenInfo::new(NumberLit, end - pos),
        next_offset=end,
      )
    }
    Some('t') if check_keyword(input, pos, "true") =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(True, 4),
        next_offset=pos + 4,
      )
    Some('f') if check_keyword(input, pos, "false") =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(False, 5),
        next_offset=pos + 5,
      )
    Some('n') if check_keyword(input, pos, "null") =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(Null, 4),
        next_offset=pos + 4,
      )
    None => @core.LexStep::Invalid(at=pos, width=1, message="Invalid character")
    Some(ch) =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(
          Error("Unexpected character: \{ch.to_string()}"),
          1,
        ),
        next_offset=pos + 1,
      )
  }
}

///|
/// Public step-based lexer for JSON.
pub fn json_step_lexer(source : String, start : Int) -> @core.LexStep[Token] {
  step_lex(source, start)
}

///|
/// Batch tokenize: loop step_lex until Done, appending EOF.
pub fn tokenize(
  input : String,
) -> Array[@core.TokenInfo[Token]] raise @core.LexError {
  @core.tokenize_via_steps(json_step_lexer, input, EOF)
}

///|
/// Format a single TokenInfo for display.
pub fn print_token_info(token_info : @core.TokenInfo[Token]) -> String {
  let tok_str = token_info.token.to_string()
  tok_str + "(" + token_info.len.to_string() + ")"
}

///|
/// Format an array of TokenInfos for display.
pub fn print_token_infos(tokens : Array[@core.TokenInfo[Token]]) -> String {
  let parts : Array[String] = []
  for token_info in tokens {
    parts.push(print_token_info(token_info))
  }
  parts.join(", ")
}
