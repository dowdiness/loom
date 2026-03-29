///|
test "parse null" {
  let v = try! parse("null")
  inspect(v, content="Null")
}

///|
test "parse true" {
  let v = try! parse("true")
  inspect(v, content="Bool(true)")
}

///|
test "parse false" {
  let v = try! parse("false")
  inspect(v, content="Bool(false)")
}

///|
test "parse number integer" {
  let v = try! parse("42")
  inspect(
    v,
    content=(
      #|Number(42)
    ),
  )
}

///|
test "parse number negative" {
  let v = try! parse("-7")
  inspect(
    v,
    content=(
      #|Number(-7)
    ),
  )
}

///|
test "parse number float" {
  let v = try! parse("3.14")
  inspect(v, content="Number(3.14)")
}

///|
test "parse number scientific" {
  let v = try! parse("1e10")
  inspect(
    v,
    content=(
      #|Number(10000000000)
    ),
  )
}

///|
test "parse string" {
  let v = try! parse("\"hello\"")
  inspect(v, content="String(\"hello\")")
}

///|
test "parse empty object" {
  let v = try! parse("{}")
  inspect(v, content="Object([])")
}

///|
test "parse empty array" {
  let v = try! parse("[]")
  inspect(v, content="Array([])")
}

///|
test "parse simple object" {
  let v = try! parse("{\"key\": 42}")
  let printed = v.to_string()
  inspect(printed.contains("key"), content="true")
  inspect(printed.contains("42"), content="true")
}

///|
test "parse nested structure" {
  let v = try! parse("{\"a\": [1, true, null]}")
  let printed = v.to_string()
  inspect(printed.contains("a"), content="true")
}

///|
test "parse string with escapes" {
  let v = try! parse("\"hello\\nworld\"")
  inspect(v, content="String(\"hello\\nworld\")")
}

///|
test "parse string with tab escape" {
  let v = try! parse("\"a\\tb\"")
  inspect(v, content="String(\"a\\tb\")")
}

///|
test "parse string with backslash escape" {
  let v = try! parse("\"a\\\\b\"")
  inspect(v, content="String(\"a\\\\b\")")
}

///|
test "parse string with quote escape" {
  let v = try! parse("\"a\\\"b\"")
  inspect(v, content="String(\"a\\\"b\")")
}

///|
test "parse string with unicode escape" {
  let v = try! parse("\"\\u0041\"")
  inspect(v, content="String(\"A\")")
}

///|
test "parse array of values" {
  let v = try! parse("[1, \"two\", true, null]")
  match v {
    Array(items) => inspect(items.length(), content="4")
    _ => fail("expected array")
  }
}

///|
test "parse object with multiple members" {
  let v = try! parse("{\"a\": 1, \"b\": 2, \"c\": 3}")
  match v {
    Object(members) => inspect(members.length(), content="3")
    _ => fail("expected object")
  }
}

///|
test "parse deeply nested" {
  let v = try! parse("{\"x\": {\"y\": {\"z\": 42}}}")
  let printed = v.to_string()
  inspect(printed.contains("42"), content="true")
}

///|
test "parse whitespace around value" {
  let v = try! parse("  42  ")
  inspect(
    v,
    content=(
      #|Number(42)
    ),
  )
}

///|
test "parse number zero" {
  let v = try! parse("0")
  inspect(
    v,
    content=(
      #|Number(0)
    ),
  )
}

///|
test "parse string with emoji" {
  let v = try! parse("\"hello 😀 world\"")
  let s = v.to_string()
  inspect(s.contains("hello"), content="true")
}

///|
test "parse surrogate pair escape" {
  let v = try! parse("\"\\uD83D\\uDE00\"")
  let s = v.to_string()
  inspect(s.length() > 0, content="true")
}
