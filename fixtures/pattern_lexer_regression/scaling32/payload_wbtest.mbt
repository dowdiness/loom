///|
test "dispatched lexer preserves provisional payload order" {
  payload_log.clear()
  match step_lex("!!", 0) {
    Produced(info, next_offset=2) =>
      assert_true(info == @core.TokenInfo::new(PayloadLong("!!"), 2))
    _ => fail("expected the longer payload token")
  }
  guard payload_log.length() == 2 else {
    fail("both provisional payloads must be evaluated")
  }
  assert_true(payload_log[0] == "!")
  assert_true(payload_log[1] == "!!")
}
