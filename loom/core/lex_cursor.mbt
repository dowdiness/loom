///|
/// Small offset cursor for implementing `PrefixLexer` and `ModeLexer` steps.
///
/// `LexCursor` is intentionally scoped to a single lex step: construct it from
/// `(source, start)`, advance to the token end, then call `produced`.
/// Positions and token lengths are UTF-16 code-unit offsets, matching
/// `TokenInfo.len`, `TokenBuffer` starts, and `Edit` ranges.
pub struct LexCursor {
  priv source : String
  priv start : Int
  priv mut position : Int
}

///|
pub fn LexCursor::new(source : String, start : Int) -> LexCursor {
  let pos = lex_cursor_clamp_offset(start, source.length())
  { source, start: pos, position: pos }
}

///|
pub fn LexCursor::source(self : LexCursor) -> String {
  self.source
}

///|
pub fn LexCursor::start(self : LexCursor) -> Int {
  self.start
}

///|
pub fn LexCursor::position(self : LexCursor) -> Int {
  self.position
}

///|
pub fn LexCursor::set_position(self : LexCursor, position : Int) -> Unit {
  self.position = lex_cursor_clamp_offset(position, self.source.length())
}

///|
pub fn LexCursor::len(self : LexCursor) -> Int {
  self.position - self.start
}

///|
pub fn LexCursor::is_done(self : LexCursor) -> Bool {
  self.position >= self.source.length()
}

///|
pub fn LexCursor::view(self : LexCursor) -> StringView {
  self.source.view(start_offset=self.position)
}

///|
pub fn LexCursor::set_view(self : LexCursor, view : StringView) -> Unit {
  self.set_position(view.start_offset())
}

///|
pub fn LexCursor::peek(self : LexCursor) -> Char? {
  self.source.get_char(self.position)
}

///|
pub fn LexCursor::peek_code_unit(self : LexCursor) -> UInt16? {
  if self.position < self.source.length() {
    Some(self.source.code_unit_at(self.position))
  } else {
    None
  }
}

///|
pub fn LexCursor::advance_code_units(self : LexCursor, width : Int) -> Unit {
  if width <= 0 {
    return
  }
  self.position = lex_cursor_clamp_offset(
    self.position + width,
    self.source.length(),
  )
}

///|
/// Advance by one Unicode scalar value. Returns false at EOF or when the
/// current offset splits a surrogate pair.
pub fn LexCursor::advance_char(self : LexCursor) -> Bool {
  if self.position >= self.source.length() {
    return false
  }
  match self.source.get_char(self.position) {
    None => false
    Some(_) => {
      self.position = next_char_offset(self.source, self.position)
      true
    }
  }
}

///|
/// Return the next UTF-16 code-unit offset after the Unicode scalar value at
/// `pos`.
///
/// This is the offset-oriented counterpart to `LexCursor::advance_char` for
/// lexers that scan with local integer offsets. If `pos` is at EOF it returns
/// EOF. If `pos` splits a surrogate pair, it advances one code unit so callers
/// still make progress on malformed boundaries.
pub fn next_char_offset(source : String, pos : Int) -> Int {
  let len = source.length()
  let current = lex_cursor_clamp_offset(pos, len)
  if current >= len {
    return len
  }
  match source.get_char(current) {
    Some(_) => {
      let unit = source.code_unit_at(current)
      if unit.is_surrogate() && current + 1 < len {
        current + 2
      } else {
        current + 1
      }
    }
    None => lex_cursor_clamp_offset(current + 1, len)
  }
}

///|
pub fn LexCursor::take_while(
  self : LexCursor,
  predicate : (Char) -> Bool,
) -> Int {
  let before = self.position
  while self.position < self.source.length() {
    match self.peek() {
      Some(ch) if predicate(ch) => if !self.advance_char() { break }
      _ => break
    }
  }
  self.position - before
}

///|
pub fn LexCursor::consume_char(self : LexCursor, expected : Char) -> Bool {
  match self.peek() {
    Some(ch) if ch == expected => self.advance_char()
    _ => false
  }
}

///|
pub fn LexCursor::starts_with(self : LexCursor, text : String) -> Bool {
  let len = text.length()
  if self.position + len > self.source.length() {
    return false
  }
  for i = 0; i < len; i = i + 1 {
    if self.source.code_unit_at(self.position + i) != text.code_unit_at(i) {
      return false
    }
  }
  true
}

///|
pub fn LexCursor::consume_string(self : LexCursor, text : String) -> Bool {
  if self.starts_with(text) {
    self.advance_code_units(text.length())
    true
  } else {
    false
  }
}

///|
pub fn[T] LexCursor::produced(self : LexCursor, token : T) -> LexStep[T] {
  let len = self.len()
  if len > 0 {
    Produced(TokenInfo::new(token, len), next_offset=self.position)
  } else {
    Invalid(at=self.start, width=1, message="lexer cursor produced no text")
  }
}

///|
pub fn[T] LexCursor::invalid(
  self : LexCursor,
  message : String,
  width? : Int = 1,
) -> LexStep[T] {
  Invalid(at=self.position, width~, message~)
}

///|
pub fn[T] LexCursor::incomplete(
  self : LexCursor,
  expected : String,
) -> LexStep[T] {
  Incomplete(at=self.position, expected~)
}

///|
fn lex_cursor_clamp_offset(pos : Int, length : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > length {
    length
  } else {
    pos
  }
}
