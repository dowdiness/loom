///|
test "generated payload captures heading level" {
  match step_lex("### ", 0) {
    @core.LexStep::Produced(info, next_offset=next) => {
      match info.token {
        HeadingMarker(level) => inspect(level, content="3")
        _ => fail("expected heading marker")
      }
      inspect(info.len, content="4")
      inspect(next, content="4")
    }
    _ => fail("expected a produced heading token")
  }
}
