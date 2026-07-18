///|
fn assert_heading_payload(
  source : String,
  expected : Int,
  width : Int,
) -> Unit raise {
  match step_lex(source, 0) {
    @core.LexStep::Produced(info, next_offset=next) =>
      match info.token {
        HeadingMarker(level) => {
          inspect(level, content=expected.to_string())
          inspect(info.len, content=width.to_string())
          inspect(next, content=width.to_string())
        }
        _ => fail("expected heading marker")
      }
    _ => fail("expected produced heading token")
  }
}

///|
test "generated heading payload levels" {
  assert_heading_payload("# ", 1, 2)
  assert_heading_payload("## ", 2, 3)
}

///|
fn assert_fence_payload(
  source : String,
  expected : String,
  width : Int,
) -> Unit raise {
  match step_lex(source, 0) {
    @core.LexStep::Produced(info, next_offset=next) =>
      match info.token {
        CodeFenceOpen(length, text) => {
          inspect(length, content="3")
          inspect(text, content=expected)
          inspect(info.len, content=width.to_string())
          inspect(next, content=width.to_string())
        }
        _ => fail("expected code fence token")
      }
    _ => fail("expected produced fence token")
  }
}

///|
test "generated fence payload preserves info and length" {
  assert_fence_payload("```\n", "", 3)
  assert_fence_payload("```python\n", "python", 9)
  assert_fence_payload("```😈\n", "😈", 5)
}
