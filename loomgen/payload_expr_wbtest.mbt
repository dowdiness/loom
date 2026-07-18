///|
/// Failing contracts for #loom.payload placeholder rewriting.
test "payload expression rewrites captures and preserves MoonBit syntax" {
  let rewritten = rewrite_payload_expr(
    "String::new() + $1.to_owned() + \"$2\" // $3\n", "m",
  )
  inspect(
    rewritten,
    content="String::new() + m.group(1).unwrap_or(\"\").to_owned() + \"$2\" // $3\n",
  )
}

///|
test "payload expression uses full content for capture zero" {
  inspect(
    rewrite_payload_expr("$0 + $1", "m"),
    content="m.content() + m.group(1).unwrap_or(\"\")",
  )
}

///|
test "payload expression rewrites capture offsets from StringView" {
  let rewritten = rewrite_payload_expr(
    "$1_start() + $1_end() + $0_match_length()", "m",
  )
  inspect(
    rewritten,
    content="m.group(1).map(fn(v) { v.start_offset() }).unwrap_or(0) + m.group(1).map(fn(v) { v.start_offset() + v.length() }).unwrap_or(0) + m.content().length()",
  )
}

///|
test "payload expression rejects malformed placeholder" {
  try rewrite_payload_expr("$", "m") catch {
    PayloadExprError::Invalid(_) => ()
  } noraise {
    _ => fail("expected malformed placeholder to raise")
  }
}
