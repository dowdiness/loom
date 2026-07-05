// Step-based lexer for simplified HTML.
// Tags are coarse tokens: OpenTag(name) spans `<name attrs>`, CloseTag(name) spans `</name>`.

///|
fn is_whitespace_char(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_alpha(c : Char) -> Bool {
  let n = c.to_int()
  n is ('a'..<'z') || n is ('A'..<'Z')
}

///|
fn is_digit_char(c : Char) -> Bool {
  c.to_int() is ('0'..<'9')
}

///|
fn is_tag_name_char(c : Char) -> Bool {
  is_alpha(c) || is_digit_char(c) || c == '-' || c == '_' || c == ':'
}

///|
fn read_tag_name(cursor : @core.LexCursor) -> String {
  let start = cursor.position()
  ignore(cursor.take_while(is_tag_name_char))
  let end = cursor.position()
  cursor.source()[start:end].to_owned()
}

///|
fn read_attr_value(cursor : @core.LexCursor) -> String? {
  match cursor.peek() {
    Some('"') => {
      ignore(cursor.advance_char())
      while !cursor.is_done() {
        match cursor.peek() {
          Some('"') => {
            ignore(cursor.advance_char())
            return None
          }
          Some('\\') => {
            ignore(cursor.advance_char())
            if !cursor.is_done() {
              ignore(cursor.advance_char())
            }
          }
          _ => ignore(cursor.advance_char())
        }
      }
      Some("unterminated double-quoted attribute value")
    }
    Some('\'') => {
      ignore(cursor.advance_char())
      while !cursor.is_done() {
        match cursor.peek() {
          Some('\'') => {
            ignore(cursor.advance_char())
            return None
          }
          _ => ignore(cursor.advance_char())
        }
      }
      Some("unterminated single-quoted attribute value")
    }
    _ => Some("expected quoted attribute value")
  }
}

///|
fn skip_ws(cursor : @core.LexCursor) -> Unit {
  ignore(cursor.take_while(is_whitespace_char))
}

///|
fn read_open_tag_body(cursor : @core.LexCursor) -> (String, Bool) {
  skip_ws(cursor)
  let name = read_tag_name(cursor)
  let mut self_closing = false
  let mut done = false
  while !done {
    skip_ws(cursor)
    match cursor.peek() {
      Some('>') => {
        ignore(cursor.advance_char())
        done = true
      }
      Some('/') => {
        ignore(cursor.advance_char())
        match cursor.peek() {
          Some('>') => {
            ignore(cursor.advance_char())
            self_closing = true
            done = true
          }
          _ => ()
        }
      }
      Some(ch) if is_tag_name_char(ch) || ch == '"' || ch == '\'' =>
        if is_tag_name_char(ch) {
          ignore(read_tag_name(cursor))
          skip_ws(cursor)
          match cursor.peek() {
            Some('=') => {
              ignore(cursor.advance_char())
              skip_ws(cursor)
              let _ = read_attr_value(cursor)
            }
            _ => ()
          }
        } else {
          let _ = read_attr_value(cursor)
        }
      _ => done = true
    }
  }
  (name, self_closing)
}

///|
fn read_close_tag_body(cursor : @core.LexCursor) -> String {
  skip_ws(cursor)
  let name = read_tag_name(cursor)
  skip_ws(cursor)
  match cursor.peek() {
    Some('>') => ignore(cursor.advance_char())
    _ => ()
  }
  name
}

///|
fn html_step_lexer(source : String, start : Int) -> @core.LexStep[@token.Token] {
  let cursor = @core.LexCursor::new(source, start)
  if cursor.is_done() {
    return Done
  }

  match cursor.peek() {
    Some(ch) if is_whitespace_char(ch) => {
      ignore(cursor.take_while(is_whitespace_char))
      cursor.produced(@token.Whitespace)
    }
    Some('<') =>
      if cursor.starts_with("</") {
        ignore(cursor.advance_code_units(2))
        let name = read_close_tag_body(cursor)
        cursor.produced(@token.CloseTag(name))
      } else if cursor.starts_with("<!--") {
        ignore(cursor.advance_code_units(4))
        while !cursor.is_done() {
          if cursor.starts_with("-->") {
            ignore(cursor.advance_code_units(3))
            break
          }
          ignore(cursor.advance_char())
        }
        cursor.produced(@token.Comment)
      } else if cursor.starts_with("<!") {
        ignore(cursor.advance_code_units(2))
        while !cursor.is_done() {
          if cursor.peek() == Some('>') {
            ignore(cursor.advance_char())
            break
          }
          ignore(cursor.advance_char())
        }
        cursor.produced(@token.Doctype)
      } else if cursor.starts_with("<![CDATA[") {
        ignore(cursor.advance_code_units(9))
        while !cursor.is_done() {
          if cursor.starts_with("]]>") {
            ignore(cursor.advance_code_units(3))
            break
          }
          ignore(cursor.advance_char())
        }
        cursor.produced(@token.CData)
      } else {
        ignore(cursor.advance_char())
        let (tag_name, _) = read_open_tag_body(cursor)
        cursor.produced(@token.OpenTag(tag_name))
      }
    Some('=') => {
      ignore(cursor.advance_char())
      cursor.produced(@token.Eq)
    }
    Some('"') | Some('\'') => {
      let _ = read_attr_value(cursor)
      cursor.produced(@token.StringLit)
    }
    Some(_) => {
      while !cursor.is_done() {
        if cursor.peek() == Some('<') {
          break
        }
        ignore(cursor.advance_char())
      }
      cursor.produced(@token.Text)
    }
    None => Done
  }
}

///|
pub fn lex(input : String) -> @core.LexResult[@token.Token] {
  let buffer = @core.TokenBuffer::new_from_steps(
    input,
    @core.PrefixLexer::new(lex_step=html_step_lexer),
    eof_token=@token.EOF,
    error_token=@token.Error(""),
    error_token_from_message=Some(msg => @token.Error(msg)),
  )
  @core.LexResult::with_starts(
    buffer.get_tokens(),
    buffer.get_starts(),
    diagnostics=buffer.get_diagnostics(),
  )
}
