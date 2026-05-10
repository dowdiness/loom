// Step-based lexer for JSON tokens

///|
fn is_digit(code : Int) -> Bool {
  code >= 48 && code <= 57 // '0'..'9'
}

///|
fn is_digit_char(ch : Char) -> Bool {
  is_digit(ch.to_int())
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
fn read_string(cursor : @core.LexCursor) -> String? {
  // cursor points at the opening '"'
  ignore(cursor.consume_char('"'))
  while !cursor.is_done() {
    match cursor.peek() {
      Some('"') => {
        ignore(cursor.advance_char())
        return None
      }
      Some('\\') => {
        // Skip escape sequence
        ignore(cursor.advance_char())
        if cursor.is_done() {
          return Some("unterminated string")
        }
        match cursor.peek() {
          Some('u') => {
            // \uXXXX — need 4 hex digits
            ignore(cursor.advance_char())
            let mut hex_count = 0
            while hex_count < 4 {
              match cursor.peek() {
                Some(ch) if is_hex_digit(ch.to_int()) => {
                  ignore(cursor.advance_char())
                  hex_count = hex_count + 1
                }
                _ => break
              }
            }
            if hex_count != 4 {
              return Some("Invalid \\u escape")
            }
          }
          Some('"')
          | Some('\\')
          | Some('/')
          | Some('b')
          | Some('f')
          | Some('n')
          | Some('r')
          | Some('t') => ignore(cursor.advance_char())
          Some(_) => {
            ignore(cursor.advance_char())
            return Some("Invalid escape sequence")
          }
          None => return Some("unterminated string")
        }
      }
      Some(ch) => {
        if ch.to_int() >= 0 && ch.to_int() <= 0x1F {
          return Some("Invalid control character in string")
        }
        ignore(cursor.advance_char())
      }
      None => return Some("Invalid character in string")
    }
  }
  // Reached end without closing quote
  Some("unterminated string")
}

///|
fn read_number(cursor : @core.LexCursor) -> Unit {
  // Optional leading '-'
  match cursor.peek() {
    Some('-') => ignore(cursor.advance_char())
    _ => ()
  }
  // Integer part
  match cursor.peek() {
    Some('0') =>
      // '0' — just consume it (no leading zeros allowed after 0)
      ignore(cursor.advance_char())
    Some(ch) if ch.to_int() >= 49 && ch.to_int() <= 57 => {
      // '1'..'9'
      ignore(cursor.advance_char())
      ignore(cursor.take_while(is_digit_char))
    }
    _ => ()
  }
  // Optional fraction
  match cursor.peek() {
    Some('.') =>
      // Check next char is a digit before consuming '.'
      if cursor.position() + 1 < cursor.source().length() &&
        is_digit(cursor.source().code_unit_at(cursor.position() + 1).to_int()) {
        ignore(cursor.advance_char()) // consume '.'
        ignore(cursor.take_while(is_digit_char))
      }
    // else: don't consume '.', it's not part of the number
    _ => ()
  }
  // Optional exponent
  match cursor.peek() {
    Some('e') | Some('E') => {
      let saved = cursor.position()
      ignore(cursor.advance_char()) // consume 'e'/'E'
      match cursor.peek() {
        Some('+') | Some('-') => ignore(cursor.advance_char())
        _ => ()
      }
      match cursor.peek() {
        Some(ch) if is_digit_char(ch) =>
          // Valid exponent — consume digits
          ignore(cursor.take_while(is_digit_char))
        _ =>
          // No digit after exponent — restore
          cursor.set_position(saved)
      }
    }
    _ => ()
  }
}

///|
/// Step-based lexer: returns one LexStep per call.
fn step_lex(input : String, pos : Int) -> @core.LexStep[Token] {
  let cursor = @core.LexCursor::new(input, pos)
  if cursor.is_done() {
    return Done
  }
  match cursor.peek() {
    Some('{') => {
      ignore(cursor.advance_char())
      cursor.produced(LBrace)
    }
    Some('}') => {
      ignore(cursor.advance_char())
      cursor.produced(RBrace)
    }
    Some('[') => {
      ignore(cursor.advance_char())
      cursor.produced(LBracket)
    }
    Some(']') => {
      ignore(cursor.advance_char())
      cursor.produced(RBracket)
    }
    Some(':') => {
      ignore(cursor.advance_char())
      cursor.produced(Colon)
    }
    Some(',') => {
      ignore(cursor.advance_char())
      cursor.produced(Comma)
    }
    Some(ws) if is_whitespace_char(ws) => {
      ignore(cursor.take_while(is_whitespace_char))
      cursor.produced(Whitespace)
    }
    Some('"') =>
      match read_string(cursor) {
        Some(msg) => cursor.produced(Error(msg))
        None => cursor.produced(StringLit)
      }
    Some('-') =>
      // Could be a number if followed by a digit
      if cursor.position() + 1 < input.length() &&
        is_digit(input.code_unit_at(cursor.position() + 1).to_int()) {
        read_number(cursor)
        cursor.produced(NumberLit)
      } else {
        ignore(cursor.advance_char())
        cursor.produced(Error("Unexpected character: -"))
      }
    Some(d) if is_digit_char(d) => {
      read_number(cursor)
      cursor.produced(NumberLit)
    }
    Some('t') if cursor.consume_string("true") => cursor.produced(True)
    Some('f') if cursor.consume_string("false") => cursor.produced(False)
    Some('n') if cursor.consume_string("null") => cursor.produced(Null)
    None => cursor.invalid("Invalid character")
    Some(ch) => {
      ignore(cursor.advance_char())
      cursor.produced(Error("Unexpected character: \{ch.to_string()}"))
    }
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
