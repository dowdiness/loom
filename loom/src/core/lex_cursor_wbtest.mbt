///|
test "LexCursor clamps start offsets" {
  let before = LexCursor::new("abc", -4)
  inspect(before.start(), content="0")
  inspect(before.position(), content="0")
  let after = LexCursor::new("abc", 99)
  inspect(after.start(), content="3")
  inspect(after.position(), content="3")
  inspect(after.is_done(), content="true")
}

///|
test "LexCursor advance_char uses code-unit offsets for surrogate pairs" {
  let cursor = LexCursor::new("😈x", 0)
  inspect(cursor.position(), content="0")
  inspect(cursor.advance_char(), content="true")
  inspect(cursor.position(), content="2")
  inspect(cursor.peek() == Some('x'), content="true")
  inspect(cursor.advance_char(), content="true")
  inspect(cursor.position(), content="3")
  inspect(cursor.advance_char(), content="false")
}

///|
test "LexCursor take_while advances by characters" {
  let cursor = LexCursor::new("abc123", 0)
  let taken = cursor.take_while(fn(ch) { ch.is_ascii_alphabetic() })
  inspect(taken, content="3")
  inspect(cursor.position(), content="3")
  inspect(cursor.peek() == Some('1'), content="true")
}

///|
test "LexCursor set_position clamps and supports rollback" {
  let cursor = LexCursor::new("abcdef", 2)
  cursor.advance_code_units(3)
  inspect(cursor.position(), content="5")
  cursor.set_position(1)
  inspect(cursor.position(), content="1")
  cursor.set_position(99)
  inspect(cursor.position(), content="6")
}

///|
test "LexCursor consume_string rolls forward only on match" {
  let cursor = LexCursor::new("false", 0)
  inspect(cursor.consume_string("true"), content="false")
  inspect(cursor.position(), content="0")
  inspect(cursor.consume_string("false"), content="true")
  inspect(cursor.position(), content="5")
}

///|
test "LexCursor set_view advances to matched StringView rest" {
  let cursor = LexCursor::new("=> rest", 0)
  match cursor.view() {
    [.. "=>", .. rest] => cursor.set_view(rest)
    _ => abort("expected prefix")
  }
  inspect(cursor.position(), content="2")
  inspect(cursor.peek() == Some(' '), content="true")
}

///|
test "LexCursor produced normalizes TokenInfo length from consumed span" {
  let cursor = LexCursor::new("abc", 0)
  cursor.advance_code_units(2)
  match cursor.produced("id") {
    Produced(info, next_offset~) => {
      inspect(info.token, content="id")
      inspect(info.len, content="2")
      inspect(next_offset, content="2")
    }
    _ => abort("expected Produced")
  }
}

///|
test "LexCursor produced rejects empty tokens" {
  let cursor = LexCursor::new("abc", 1)
  match cursor.produced("empty") {
    Invalid(at~, width~, message~) => {
      inspect(at, content="1")
      inspect(width, content="1")
      inspect(message, content="lexer cursor produced no text")
    }
    _ => abort("expected Invalid")
  }
}

///|
test "LexCursor invalid reports current position" {
  let cursor = LexCursor::new("abc", 0)
  cursor.advance_code_units(2)
  let step : LexStep[String] = cursor.invalid("bad", width=3)
  match step {
    Invalid(at~, width~, message~) => {
      inspect(at, content="2")
      inspect(width, content="3")
      inspect(message, content="bad")
    }
    _ => abort("expected Invalid")
  }
}

///|
test "LexCursor incomplete reports current position" {
  let cursor = LexCursor::new("abc", 0)
  cursor.advance_code_units(3)
  let step : LexStep[String] = cursor.incomplete("more text")
  match step {
    Incomplete(at~, expected~) => {
      inspect(at, content="3")
      inspect(expected, content="more text")
    }
    _ => abort("expected Incomplete")
  }
}
