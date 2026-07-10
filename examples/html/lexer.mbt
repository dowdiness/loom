// Step-based lexer for simplified HTML.
// Tags are coarse tokens: OpenTag(name) spans `<name attrs>`, CloseTag(name) spans `</name>`.

///|
fn is_whitespace_char(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_alpha(c : Char) -> Bool {
  let n = c.to_int()
  n is ('a'..='z') || n is ('A'..='Z')
}

///|
fn is_digit_char(c : Char) -> Bool {
  c.to_int() is ('0'..='9')
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
/// Lexer mode for `<script>`/`<style>` raw-text content (loom #626).
/// `RawText(tag)` holds the lowercased raw-text tag name being scanned for,
/// so scanning resumes correctly even with `<script>`/`<style>` nested at
/// different points in the source.
priv enum HtmlLexMode {
  Normal
  RawText(String)
} derive(Eq)

///|
fn is_close_tag_boundary(c : Char?) -> Bool {
  match c {
    None => true
    Some(c) => !is_tag_name_char(c)
  }
}

///|
/// Case-insensitive, non-consuming probe for `</tag` at `cursor`'s current
/// position, followed by a tag-name boundary — so `</script` does not match
/// inside `</scripts>`. `tag` must already be lowercased.
fn matches_raw_text_close(cursor : @core.LexCursor, tag : String) -> Bool {
  let start = cursor.position()
  if !cursor.consume_char('<') || !cursor.consume_char('/') {
    cursor.set_position(start)
    return false
  }
  for c in tag {
    match cursor.peek() {
      Some(ch) if ch.to_ascii_lowercase() == c => ignore(cursor.advance_char())
      _ => {
        cursor.set_position(start)
        return false
      }
    }
  }
  let matched = is_close_tag_boundary(cursor.peek())
  cursor.set_position(start)
  matched
}

///|
/// Offset where raw-text content for `tag` ends: the start of the matching
/// case-insensitive `</tag` close sequence, or `source.length()` if
/// unterminated. `tag` must already be lowercased. Content is scanned
/// literally — no nested-tag parsing, matching real raw-text-element
/// semantics (a stray `<` that isn't part of the exact close sequence is
/// just raw content).
fn find_raw_text_close(source : String, start : Int, tag : String) -> Int {
  let cursor = @core.LexCursor::new(source, start)
  while !cursor.is_done() {
    if cursor.peek() == Some('<') && matches_raw_text_close(cursor, tag) {
      return cursor.position()
    }
    ignore(cursor.advance_char())
  }
  cursor.position()
}

///|
/// Mode-aware lex step. `Normal` mode is the existing step lexer, except an
/// `OpenTag` for a raw-text tag (script/style, case-insensitively — see
/// `is_raw_text_tag`) switches into `RawText` mode. `RawText` mode scans to
/// the matching close tag and emits a single `@token.RawText` token,
/// without consuming the close tag itself (the next step, back in `Normal`
/// mode, lexes it as an ordinary `CloseTag`).
fn html_mode_lex_step(
  source : String,
  start : Int,
  mode : HtmlLexMode,
) -> (@core.LexStep[@token.Token], HtmlLexMode) {
  match mode {
    Normal => {
      let step = html_step_lexer(source, start)
      let next_mode = match step {
        Produced(info, ..) =>
          match info.token {
            @token.OpenTag(name) if is_raw_text_tag(name) =>
              RawText(name.to_lower())
            _ => Normal
          }
        _ => Normal
      }
      (step, next_mode)
    }
    RawText(tag) => {
      let close_at = find_raw_text_close(source, start, tag)
      if close_at > start {
        let cursor = @core.LexCursor::new(source, start)
        cursor.set_position(close_at)
        (cursor.produced(@token.RawText), Normal)
      } else {
        // Empty content (e.g. `<script></script>`) — do not emit a
        // zero-width token (loom #646 was exactly this class of bug).
        // Re-dispatch at the same position in Normal mode so the close tag
        // is lexed immediately as an ordinary CloseTag.
        html_mode_lex_step(source, start, Normal)
      }
    }
  }
}

///|
let html_mode_lexer : @core.ModeLexer[@token.Token, HtmlLexMode] = {
  lex_step: html_mode_lex_step,
  initial_mode: Normal,
}

///|
let html_mode_relex_state : @core.ModeRelexState[@token.Token] = @loom.erase_mode_lexer(
  html_mode_lexer,
  @token.EOF,
  error_token=@token.Error(""),
  error_token_from_message=Some(msg => @token.Error(msg)),
)

///|
pub fn lex(input : String) -> @core.LexResult[@token.Token] {
  (html_mode_relex_state.tokenize)(input)
}
