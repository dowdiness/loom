///|
fn is_digit_char(ch : Char) -> Bool {
  let code = ch.to_int()
  code >= 48 && code <= 57
}

///|
fn is_identifier_start(ch : Char) -> Bool {
  let code = ch.to_int()
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || ch == '_'
}

///|
fn is_identifier_char(ch : Char) -> Bool {
  is_identifier_start(ch) || is_digit_char(ch)
}

///|
fn is_horizontal_whitespace(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\r'
}

///|
fn read_number(cursor : @core.LexCursor) -> Unit {
  match cursor.peek() {
    Some('-') => ignore(cursor.advance_char())
    _ => ()
  }
  ignore(cursor.take_while(is_digit_char))
  match cursor.peek() {
    Some('.') => {
      let saved = cursor.position()
      ignore(cursor.advance_char())
      match cursor.peek() {
        Some(ch) if is_digit_char(ch) =>
          ignore(cursor.take_while(is_digit_char))
        _ => cursor.set_position(saved)
      }
    }
    _ => ()
  }
}

///|
fn read_string(cursor : @core.LexCursor) -> (String, Int)? {
  ignore(cursor.consume_char('"'))
  while !cursor.is_done() {
    match cursor.peek() {
      Some('"') => {
        ignore(cursor.advance_char())
        return None
      }
      Some('\\') => {
        ignore(cursor.advance_char())
        if cursor.is_done() {
          return Some(("unterminated string", cursor.position()))
        }
        ignore(cursor.advance_char())
      }
      Some('\n') | Some('\r') =>
        return Some(("unterminated string", cursor.position()))
      Some(_) => ignore(cursor.advance_char())
      None => return Some(("unterminated string", cursor.position()))
    }
  }
  Some(("unterminated string", cursor.position()))
}

///|
fn invalid_width(input : String, start : Int, end : Int) -> Int {
  let bounded_end = if end < start {
    start
  } else if end > input.length() {
    input.length()
  } else {
    end
  }
  let width = bounded_end - start
  if width > 0 {
    width
  } else {
    @core.next_char_offset(input, start) - start
  }
}

///|
fn graph_step_lex(input : String, pos : Int) -> @core.LexStep[Token] {
  let cursor = @core.LexCursor::new(input, pos)
  if cursor.is_done() {
    return Done
  }
  match cursor.view() {
    ['-', '>', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Arrow)
    }
    ['=', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Equal)
    }
    ['(', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(LParen)
    }
    [')', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(RParen)
    }
    [':', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Colon)
    }
    [',', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Comma)
    }
    ['\n', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Newline)
    }
    [ws, ..] if is_horizontal_whitespace(ws) => {
      ignore(cursor.take_while(is_horizontal_whitespace))
      cursor.produced(Whitespace)
    }
    ['"', ..] =>
      match read_string(cursor) {
        Some((message, end)) =>
          @core.LexStep::Invalid(
            at=pos,
            width=invalid_width(input, pos, end),
            message~,
          )
        None => cursor.produced(StringLit)
      }
    ['-', d, ..] if is_digit_char(d) => {
      read_number(cursor)
      cursor.produced(Number)
    }
    [d, ..] if is_digit_char(d) => {
      read_number(cursor)
      cursor.produced(Number)
    }
    [ch, ..] if is_identifier_start(ch) => {
      ignore(cursor.take_while(is_identifier_char))
      cursor.produced(Identifier)
    }
    [ch, .. rest] => {
      cursor.set_view(rest)
      cursor.invalid("unexpected character: " + ch.to_string())
    }
    _ => cursor.invalid("invalid character")
  }
}

///|
fn graph_step_lexer(source : String, start : Int) -> @core.LexStep[Token] {
  graph_step_lex(source, start)
}

///|
fn lex(input : String) -> @core.LexResult[Token] {
  let buffer = @core.TokenBuffer::new_from_steps(
    input,
    @core.PrefixLexer::new(lex_step=graph_step_lexer),
    eof_token=EOF,
    error_token=Error(""),
    error_token_from_message=Some(fn(message) { Error(message) }),
  )
  @core.LexResult::with_starts(
    buffer.get_tokens(),
    buffer.get_starts(),
    diagnostics=buffer.get_diagnostics(),
  )
}
