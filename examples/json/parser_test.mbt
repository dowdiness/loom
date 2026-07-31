///|
test "parse null" {
  let source_id = @core.SourceId("json-parser-null")
  let v = try! parse(source_id, "null")
  inspect(v, content="Null")
}

///|
test "parse true" {
  let source_id = @core.SourceId("json-parser-true")
  let v = try! parse(source_id, "true")
  inspect(v, content="Bool(true)")
}

///|
test "parse false" {
  let source_id = @core.SourceId("json-parser-false")
  let v = try! parse(source_id, "false")
  inspect(v, content="Bool(false)")
}

///|
test "parse number integer" {
  let source_id = @core.SourceId("json-parser-integer")
  let v = try! parse(source_id, "42")
  inspect(
    v,
    content=(
      #|Number(42)
    ),
  )
}

///|
test "parse number negative" {
  let source_id = @core.SourceId("json-parser-negative")
  let v = try! parse(source_id, "-7")
  inspect(
    v,
    content=(
      #|Number(-7)
    ),
  )
}

///|
test "parse number float" {
  let source_id = @core.SourceId("json-parser-float")
  let v = try! parse(source_id, "3.14")
  inspect(v, content="Number(3.14)")
}

///|
test "parse number scientific" {
  let source_id = @core.SourceId("json-parser-scientific")
  let v = try! parse(source_id, "1e10")
  inspect(
    v,
    content=(
      #|Number(10000000000)
    ),
  )
}

///|
test "parse string" {
  let source_id = @core.SourceId("json-parser-string")
  let v = try! parse(source_id, "\"hello\"")
  inspect(v, content="String(\"hello\")")
}

///|
test "parse empty object" {
  let source_id = @core.SourceId("json-parser-empty-object")
  let v = try! parse(source_id, "{}")
  inspect(v, content="Object([])")
}

///|
test "parse empty array" {
  let source_id = @core.SourceId("json-parser-empty-array")
  let v = try! parse(source_id, "[]")
  inspect(v, content="Array([])")
}

///|
test "parse simple object" {
  let source_id = @core.SourceId("json-parser-simple-object")
  let v = try! parse(source_id, "{\"key\": 42}")
  let printed = v.to_string()
  inspect(printed.contains("key"), content="true")
  inspect(printed.contains("42"), content="true")
}

///|
test "parse nested structure" {
  let source_id = @core.SourceId("json-parser-nested-structure")
  let v = try! parse(source_id, "{\"a\": [1, true, null]}")
  let printed = v.to_string()
  inspect(printed.contains("a"), content="true")
}

///|
test "parse string with escapes" {
  let source_id = @core.SourceId("json-parser-string-escapes")
  let v = try! parse(source_id, "\"hello\\nworld\"")
  inspect(v, content="String(\"hello\\nworld\")")
}

///|
test "parse string with tab escape" {
  let source_id = @core.SourceId("json-parser-tab-escape")
  let v = try! parse(source_id, "\"a\\tb\"")
  inspect(v, content="String(\"a\\tb\")")
}

///|
test "parse string with backslash escape" {
  let source_id = @core.SourceId("json-parser-backslash-escape")
  let v = try! parse(source_id, "\"a\\\\b\"")
  inspect(v, content="String(\"a\\\\b\")")
}

///|
test "parse string with quote escape" {
  let source_id = @core.SourceId("json-parser-quote-escape")
  let v = try! parse(source_id, "\"a\\\"b\"")
  inspect(v, content="String(\"a\\\"b\")")
}

///|
test "parse string with unicode escape" {
  let source_id = @core.SourceId("json-parser-unicode-escape")
  let v = try! parse(source_id, "\"\\u0041\"")
  inspect(v, content="String(\"A\")")
}

///|
test "parse array of values" {
  let source_id = @core.SourceId("json-parser-array-values")
  let v = try! parse(source_id, "[1, \"two\", true, null]")
  match v {
    Array(items) => inspect(items.length(), content="4")
    _ => fail("expected array")
  }
}

///|
test "parse object with multiple members" {
  let source_id = @core.SourceId("json-parser-object-members")
  let v = try! parse(source_id, "{\"a\": 1, \"b\": 2, \"c\": 3}")
  match v {
    Object(members) => inspect(members.length(), content="3")
    _ => fail("expected object")
  }
}

///|
test "parse deeply nested" {
  let source_id = @core.SourceId("json-parser-deeply-nested")
  let v = try! parse(source_id, "{\"x\": {\"y\": {\"z\": 42}}}")
  let printed = v.to_string()
  inspect(printed.contains("42"), content="true")
}

///|
test "parse whitespace around value" {
  let source_id = @core.SourceId("json-parser-whitespace")
  let v = try! parse(source_id, "  42  ")
  inspect(
    v,
    content=(
      #|Number(42)
    ),
  )
}

///|
test "parse number zero" {
  let source_id = @core.SourceId("json-parser-zero")
  let v = try! parse(source_id, "0")
  inspect(
    v,
    content=(
      #|Number(0)
    ),
  )
}

///|
test "parse string with emoji" {
  let source_id = @core.SourceId("json-parser-emoji")
  let v = try! parse(source_id, "\"hello 😀 world\"")
  let s = v.to_string()
  inspect(s.contains("hello"), content="true")
}

///|
test "parse surrogate pair escape" {
  let source_id = @core.SourceId("json-parser-surrogate-pair")
  let v = try! parse(source_id, "\"\\uD83D\\uDE00\"")
  let s = v.to_string()
  inspect(s.length() > 0, content="true")
}

///|
test "parse error reports formatted parser diagnostic" {
  let source_id = @core.SourceId("json-parser-error-diagnostic")
  try parse(source_id, "]") catch {
    ParseError::ParseError(message) =>
      inspect(message, content="Expected JSON value [0,1]")
    _ => fail("expected ParseError")
  } noraise {
    _ => fail("expected parse failure")
  }
}

///|
test "parse error reports formatted lexer diagnostic" {
  let source_id = @core.SourceId("json-lexer-error-diagnostic")
  try parse(source_id, "\"\\x\"") catch {
    ParseError::ParseError(message) =>
      inspect(message, content="Invalid escape sequence [0,3]")
    _ => fail("expected ParseError")
  } noraise {
    _ => fail("expected parse failure")
  }
}
