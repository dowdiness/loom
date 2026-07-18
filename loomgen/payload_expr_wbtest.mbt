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
test "payload expression preserves non-BMP strings while rewriting captures" {
  inspect(
    rewrite_payload_expr("\"😈\" + $1", "m"),
    content="\"😈\" + m.group(1).unwrap_or(\"\")",
  )
}

///|
test "payload expression preserves non-BMP comments while validating" {
  inspect(
    rewrite_payload_expr("$1 /* 😈 */", "m"),
    content="m.group(1).unwrap_or(\"\") /* 😈 */",
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

///|
test "payload expression rejects trailing dot" {
  try rewrite_payload_expr("$1.", "m") catch {
    PayloadExprError::Invalid(_) => ()
  } noraise {
    _ => fail("expected trailing dot to raise")
  }
}

///|
test "payload expression allows punctuation in trailing comments" {
  inspect(
    rewrite_payload_expr("$1 // explanation.", "m"),
    content="m.group(1).unwrap_or(\"\") // explanation.",
  )
}

///|
test "payload expression allows punctuation in strings and block comments" {
  let actual = rewrite_payload_expr("\".\" + $1 /* explanation. */", "m") catch {
    PayloadExprError::Invalid(msg) => fail(msg)
  }
  inspect(
    actual,
    content="\".\" + m.group(1).unwrap_or(\"\") /* explanation. */",
  )
}

///|
test "payload expression rejects unterminated block comments" {
  try rewrite_payload_expr("$1 /* explanation.", "m") catch {
    PayloadExprError::Invalid(_) => ()
  } noraise {
    _ => fail("expected unterminated block comment to raise")
  }
}

///|
test "payload expression preserves multiline string contents" {
  let expr = "$| heading\n$| $1\n$| // comment"
  let rewritten = rewrite_payload_expr(expr, "m")
  inspect(rewritten, content=expr)
}

///|
test "payload expression rewrites after nested multiline string" {
  let expr = "(\n  $| heading\n  $| /* explanation. */\n) + $1"
  inspect(
    rewrite_payload_expr(expr, "m"),
    content="(\n  $| heading\n  $| /* explanation. */\n) + m.group(1).unwrap_or(\"\")",
  )
}

///|
test "payload expression accepts mixed multiline prefixes" {
  let expr = "(\n  #| heading\n  $| details\n) + $1"
  inspect(
    rewrite_payload_expr(expr, "m"),
    content="(\n  #| heading\n  $| details\n) + m.group(1).unwrap_or(\"\")",
  )
}

///|
test "payload capture index ignores multiline string placeholders" {
  inspect(max_payload_capture_index("(\n  $| text $2\n) + $1"), content="1")
}

///|
test "payload capture indexing advances across non-BMP code" {
  inspect(max_payload_capture_index("😈 + $1"), content="1")
}
