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
fn invalid_end_at_cursor(input : String, cursor : @core.LexCursor) -> Int {
  let cursor_pos = cursor.position()
  if cursor_pos < input.length() {
    @core.next_char_offset(input, cursor_pos)
  } else {
    cursor_pos
  }
}

///|
fn read_string(cursor : @core.LexCursor) -> (String, Int)? {
  // cursor points at the opening '"'
  ignore(cursor.consume_char('"'))
  let input = cursor.source()
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
          return Some(("unterminated string", cursor.position()))
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
              return Some(("Invalid \\u escape", invalid_end_at_cursor(input, cursor)))
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
            return Some(("Invalid escape sequence", cursor.position()))
          }
          None => return Some(("unterminated string", cursor.position()))
        }
      }
      Some(ch) => {
        if ch.to_int() >= 0 && ch.to_int() <= 0x1F {
          return Some((
            "Invalid control character in string",
            invalid_end_at_cursor(input, cursor),
          ))
        }
        ignore(cursor.advance_char())
      }
      None =>
        return Some((
          "Invalid character in string",
          invalid_end_at_cursor(input, cursor),
        ))
    }
  }
  // Reached end without closing quote
  Some(("unterminated string", cursor.position()))
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
fn invalid_width_from_end(input : String, pos : Int, end : Int) -> Int {
  let bounded_end = if end < pos {
    pos
  } else if end > input.length() {
    input.length()
  } else {
    end
  }
  let width = bounded_end - pos
  if width > 0 {
    width
  } else {
    @core.next_char_offset(input, pos) - pos
  }
}

///|
/// Step-based lexer: returns one LexStep per call.
fn step_lex(input : String, pos : Int) -> @core.LexStep[Token] {
  let cursor = @core.LexCursor::new(input, pos)
  if cursor.is_done() {
    return Done
  }
  match cursor.view() {
    ['{', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(LBrace)
    }
    ['}', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(RBrace)
    }
    ['[', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(LBracket)
    }
    [']', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(RBracket)
    }
    [':', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Colon)
    }
    [',', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Comma)
    }
    [ws, ..] if is_whitespace_char(ws) => {
      ignore(cursor.take_while(is_whitespace_char))
      cursor.produced(Whitespace)
    }
    ['"', ..] =>
      match read_string(cursor) {
        Some((msg, end)) =>
          @core.LexStep::Invalid(
            at=pos,
            width=invalid_width_from_end(input, pos, end),
            message=msg,
          )
        None => cursor.produced(StringLit)
      }
    ['-', d, ..] if is_digit_char(d) => {
      read_number(cursor)
      cursor.produced(NumberLit)
    }
    ['-', .. rest] => {
      cursor.set_view(rest)
      @core.LexStep::Invalid(
        at=pos,
        width=cursor.len(),
        message="Unexpected character: -",
      )
    }
    [d, ..] if is_digit_char(d) => {
      read_number(cursor)
      cursor.produced(NumberLit)
    }
    [.. "true", .. rest] => {
      cursor.set_view(rest)
      cursor.produced(True)
    }
    [.. "false", .. rest] => {
      cursor.set_view(rest)
      cursor.produced(False)
    }
    [.. "null", .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Null)
    }
    [ch, .. rest] => {
      cursor.set_view(rest)
      @core.LexStep::Invalid(
        at=pos,
        width=cursor.len(),
        message="Unexpected character: \{ch.to_string()}",
      )
    }
    _ => cursor.invalid("Invalid character")
  }
}

///|
/// Public step-based lexer for JSON.
pub fn json_step_lexer(source : String, start : Int) -> @core.LexStep[Token] {
  step_lex(source, start)
}

///|
fn tokenize_recoverable(input : String) -> Array[@core.TokenInfo[Token]] {
  @core.TokenBuffer::new_from_steps(
    input,
    @core.PrefixLexer::new(lex_step=json_step_lexer),
    eof_token=EOF,
    error_token=Error(""),
    error_token_from_message=Some(fn(msg) { Error(msg) }),
  ).get_tokens()
}

///|
/// Batch tokenize: loop step_lex until Done, appending EOF.
#warnings("-unused_error_type")
pub fn tokenize(
  input : String,
) -> Array[@core.TokenInfo[Token]] raise @core.LexError {
  tokenize_recoverable(input)
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
