///|
test "inline delimiter cursor: waits for a future event" {
  assert_false(delimiter_event_is_ready(current_start=3, event_start=5))
}

///|
test "inline delimiter cursor: emits an event at the current position" {
  assert_true(delimiter_event_is_ready(current_start=5, event_start=5))
}

///|
test "panic inline delimiter cursor: rejects a skipped event" {
  ignore(delimiter_event_is_ready(current_start=6, event_start=5))
}

///|
test "inline delimiter cursor: accepts complete balanced emission" {
  validate_delimiter_cursor_completion(
    event_index=3,
    event_count=3,
    emphasis_depth=0,
  )
}

///|
test "panic inline delimiter cursor: rejects unconsumed events" {
  validate_delimiter_cursor_completion(
    event_index=2,
    event_count=3,
    emphasis_depth=0,
  )
}

///|
test "panic inline delimiter cursor: rejects unclosed emphasis" {
  validate_delimiter_cursor_completion(
    event_index=3,
    event_count=3,
    emphasis_depth=1,
  )
}
