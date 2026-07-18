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
test "generated payload offsets remain absolute after a prefix" {
  match step_lex("prefix abc", 7) {
    @core.LexStep::Produced(info, next_offset=next) =>
      match info.token {
        OffsetWord(start) => {
          inspect(start, content="710")
          inspect(info.len, content="3")
          inspect(next, content="10")
        }
        _ => fail("expected offset payload token")
      }
    _ => fail("expected produced offset token")
  }
  match step_lex("😈prefix abc", 9) {
    @core.LexStep::Produced(info, next_offset=next) =>
      match info.token {
        OffsetWord(start) => {
          inspect(start, content="912")
          inspect(info.len, content="3")
          inspect(next, content="12")
        }
        _ => fail("expected non-BMP offset payload token")
      }
    _ => fail("expected produced non-BMP offset token")
  }
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
