///|
test "parse null" {
  let v = parse("null") catch { _ => abort("parse error") }
  inspect(v, content="Null")
}

///|
test "parse true" {
  let v = parse("true") catch { _ => abort("parse error") }
  inspect(v, content="Bool(true)")
}

///|
test "parse false" {
  let v = parse("false") catch { _ => abort("parse error") }
  inspect(v, content="Bool(false)")
}

///|
test "parse number integer" {
  let v = parse("42") catch { _ => abort("parse error") }
  inspect(
    v,
    content=(
      #|Number(42)
    ),
  )
}

///|
test "parse number negative" {
  let v = parse("-7") catch { _ => abort("parse error") }
  inspect(
    v,
    content=(
      #|Number(-7)
    ),
  )
}

///|
test "parse number float" {
  let v = parse("3.14") catch { _ => abort("parse error") }
  inspect(v, content="Number(3.14)")
}

///|
test "parse number scientific" {
  let v = parse("1e10") catch { _ => abort("parse error") }
  inspect(
    v,
    content=(
      #|Number(10000000000)
    ),
  )
}

///|
test "parse string" {
  let v = parse("\"hello\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"hello\")")
}

///|
test "parse empty object" {
  let v = parse("{}") catch { _ => abort("parse error") }
  inspect(v, content="Object([])")
}

///|
test "parse empty array" {
  let v = parse("[]") catch { _ => abort("parse error") }
  inspect(v, content="Array([])")
}

///|
test "parse simple object" {
  let v = parse("{\"key\": 42}") catch { _ => abort("parse error") }
  let printed = v.to_string()
  inspect(printed.contains("key"), content="true")
  inspect(printed.contains("42"), content="true")
}

///|
test "parse nested structure" {
  let v = parse("{\"a\": [1, true, null]}") catch { _ => abort("parse error") }
  let printed = v.to_string()
  inspect(printed.contains("a"), content="true")
}

///|
test "parse string with escapes" {
  let v = parse("\"hello\\nworld\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"hello\\nworld\")")
}

///|
test "parse string with tab escape" {
  let v = parse("\"a\\tb\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"a\\tb\")")
}

///|
test "parse string with backslash escape" {
  let v = parse("\"a\\\\b\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"a\\\\b\")")
}

///|
test "parse string with quote escape" {
  let v = parse("\"a\\\"b\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"a\\\"b\")")
}

///|
test "parse string with unicode escape" {
  let v = parse("\"\\u0041\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"A\")")
}

///|
test "parse array of values" {
  let v = parse("[1, \"two\", true, null]") catch { _ => abort("parse error") }
  match v {
    Array(items) => inspect(items.length(), content="4")
    _ => abort("expected array")
  }
}

///|
test "parse object with multiple members" {
  let v = parse("{\"a\": 1, \"b\": 2, \"c\": 3}") catch {
    _ => abort("parse error")
  }
  match v {
    Object(members) => inspect(members.length(), content="3")
    _ => abort("expected object")
  }
}

///|
test "parse deeply nested" {
  let v = parse("{\"x\": {\"y\": {\"z\": 42}}}") catch {
    _ => abort("parse error")
  }
  let printed = v.to_string()
  inspect(printed.contains("42"), content="true")
}

///|
test "parse whitespace around value" {
  let v = parse("  42  ") catch { _ => abort("parse error") }
  inspect(
    v,
    content=(
      #|Number(42)
    ),
  )
}

///|
test "parse number zero" {
  let v = parse("0") catch { _ => abort("parse error") }
  inspect(
    v,
    content=(
      #|Number(0)
    ),
  )
}

///|
test "parse string with emoji" {
  let v = parse("\"hello 😀 world\"") catch { _ => abort("parse error") }
  let s = v.to_string()
  inspect(s.contains("hello"), content="true")
}

///|
test "parse surrogate pair escape" {
  let v = parse("\"\\uD83D\\uDE00\"") catch { _ => abort("parse error") }
  let s = v.to_string()
  inspect(s.length() > 0, content="true")
}
