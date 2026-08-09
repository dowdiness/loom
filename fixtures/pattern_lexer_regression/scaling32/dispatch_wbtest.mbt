///|
test "dispatched lexer preserves token widths and invalid recovery" {
  match step_lex("a123", 0) {
    Produced(info, next_offset=4) =>
      assert_true(info == @core.TokenInfo::new(CandidateA, 4))
    _ => fail("expected CandidateA")
  }
  match step_lex("F9", 0) {
    Produced(info, next_offset=2) =>
      assert_true(info == @core.TokenInfo::new(CandidateAF, 2))
    _ => fail("expected CandidateAF")
  }
  match step_lex("🤣", 0) {
    Invalid(at=0, width=2, message="Unexpected character") => ()
    _ => fail("non-BMP invalid recovery must consume two UTF-16 units")
  }
  match step_lex("", 0) {
    Done => ()
    _ => fail("empty input must terminate")
  }
}
