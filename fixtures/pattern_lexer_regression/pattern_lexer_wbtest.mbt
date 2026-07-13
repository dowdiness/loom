///|
fn fixture_lexer() -> @core.PrefixLexer[Token] {
  @core.PrefixLexer::new(lex_step=step_lex)
}

///|
fn assert_produced(
  step : @core.LexStep[Token],
  token : Token,
  len : Int,
  next_offset : Int,
) -> Unit {
  match step {
    Produced(info, next_offset=actual_next) =>
      if !(info == @core.TokenInfo::new(token, len) &&
        actual_next == next_offset) {
        abort("unexpected produced token, length, or next offset")
      }
    _ => abort("expected Produced")
  }
}

///|
test "generated pattern lexer prefers the longest punctuation" {
  assert_produced(step_lex("->", 0), Arrow, 2, 2)
  assert_produced(step_lex("-", 0), Minus, 1, 1)
}

///|
test "generated pattern lexer classifies only exact keywords" {
  assert_produced(step_lex("let", 0), Let, 3, 3)
  assert_produced(step_lex("letter", 0), Ident, 6, 6)
}

///|
test "generated pattern lexer emits trivia and ordinary patterns" {
  let steps = fixture_lexer().lex_all(" \tfoo 42", 0)
  guard steps.length() == 4 else {
    fail("expected trivia, identifier, trivia, and number steps")
  }
  assert_produced(steps[0], Whitespace, 2, 2)
  assert_produced(steps[1], Ident, 3, 5)
  assert_produced(steps[2], Whitespace, 1, 6)
  assert_produced(steps[3], Number, 2, 8)
}

///|
test "generated pattern lexer reports invalid non-BMP input by scalar width" {
  match step_lex("😈x", 0) {
    Invalid(at=0, width=2, message="Unexpected character") => ()
    _ => fail("invalid non-BMP scalar must advance by two code units")
  }
  let recovered = fixture_lexer().lex_all("😈x", 0)
  guard recovered.length() == 2 else {
    fail("non-BMP recovery must continue with the following scalar")
  }
  match recovered[0] {
    Invalid(at=0, width=2, message="Unexpected character") => ()
    _ => fail("first recovered step must retain the scalar-width error")
  }
  assert_produced(recovered[1], Ident, 1, 3)
}

///|
test "generated pattern lexer terminates at EOF" {
  match step_lex("", 0) {
    Done => ()
    _ => fail("empty input must return Done")
  }
  match step_lex("x", 1) {
    Done => ()
    _ => fail("end offset must return Done")
  }
}
