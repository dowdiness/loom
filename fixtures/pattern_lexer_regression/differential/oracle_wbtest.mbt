///|
fn assert_same_step(
  legacy : @core.LexStep[Token],
  first : @core.LexStep[Token],
) -> Unit raise {
  match (legacy, first) {
    (
      Produced(legacy_info, next_offset=legacy_next),
      Produced(first_info, next_offset=first_next),
    ) => {
      assert_eq(legacy_info, first_info)
      assert_eq(legacy_next, first_next)
    }
    (
      Invalid(at=legacy_at, width=legacy_width, message=legacy_message),
      Invalid(at=first_at, width=first_width, message=first_message),
    ) => {
      assert_eq(legacy_at, first_at)
      assert_eq(legacy_width, first_width)
      assert_eq(legacy_message, first_message)
    }
    (
      Incomplete(at=legacy_at, expected=legacy_expected),
      Incomplete(at=first_at, expected=first_expected),
    ) => {
      assert_eq(legacy_at, first_at)
      assert_eq(legacy_expected, first_expected)
    }
    (Done, Done) => ()
    _ => fail("legacy and FIRST backends returned different LexStep variants")
  }
}

///|
fn assert_same_stream(source : String) -> Unit raise {
  payload_log.clear()
  custom_log.clear()
  let legacy_lexer = @core.PrefixLexer::new(lex_step=step_lex_legacy)
  let legacy_steps = legacy_lexer.lex_all(source, 0)
  let legacy_payloads = payload_log.copy()
  let legacy_custom = custom_log.copy()
  payload_log.clear()
  custom_log.clear()
  let first_lexer = @core.PrefixLexer::new(lex_step=step_lex_first)
  let first_steps = first_lexer.lex_all(source, 0)
  assert_eq(legacy_steps.length(), first_steps.length())
  for i in 0..<legacy_steps.length() {
    assert_same_step(legacy_steps[i], first_steps[i])
  }
  assert_eq(legacy_payloads, payload_log)
  assert_eq(legacy_custom, custom_log)
}

///|
test "legacy and FIRST agree on token, payload, and hook behavior" {
  assert_same_stream("!!a123 b45 F9")
  assert_same_stream("let letter")
  assert_same_stream("- ->")
  assert_same_stream("~~")
  assert_same_step(step_lex_legacy("~~", 0), step_lex_first("~~", 0))
  match step_lex_legacy("~~", 0) {
    Produced(info, next_offset=2) => assert_eq(info.token, TieFirst)
    _ => fail("equal-length ties must keep the earlier declaration")
  }
  assert_same_stream("# @")
  assert_same_stream("!z999")
}

///|
test "legacy and FIRST agree on recovery, EOF, and UTF-16 offsets" {
  assert_same_stream("😈x")
  assert_same_stream("")
  for source in ["a123", "!!", "let", "->", "😈x", "?"] {
    for pos in 0..<=source.length() {
      assert_same_step(
        step_lex_legacy(source, pos),
        step_lex_first(source, pos),
      )
    }
  }
}
