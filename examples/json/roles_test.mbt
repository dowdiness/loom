///|
test "json roles distinguish property key strings from string values" {
  let source = "{ \"name\": \"Alice\" }"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  let roles = project_json_roles(parser.syntax_tree().read_or_abort())
  let expected : Array[JsonRoleSpan] = [
    JsonRoleSpan(role=Punctuation, start=0, end=1),
    JsonRoleSpan(role=PropertyKey, start=2, end=8),
    JsonRoleSpan(role=Punctuation, start=8, end=9),
    JsonRoleSpan(role=StringValue, start=10, end=17),
    JsonRoleSpan(role=Punctuation, start=18, end=19),
  ]
  guard roles == expected else {
    fail("expected property key and string value role spans")
  }
}

///|
test "json role export names are stable" {
  let roles : Array[JsonRole] = [
    PropertyKey,
    StringValue,
    NumberLiteral,
    BooleanLiteral,
    NullLiteral,
    Punctuation,
    Error,
  ]
  let names = roles.map(fn(role) { role.export_name() })
  let expected = [
    "property-key", "string-value", "number-literal", "boolean-literal", "null-literal",
    "punctuation", "error",
  ]
  guard names == expected else {
    fail("expected stable JSON role export vocabulary")
  }
}

///|
test "json role spans export editor-neutral JSON shape" {
  let source = "{\"a\": [\"x\", 1, true, null]}"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  let exported = export_json_role_spans(
    project_json_roles(parser.syntax_tree().read_or_abort()),
  )
  inspect(exported.length(), content="13")
  inspect(exported[0].start(), content="0")
  inspect(exported[0].end(), content="1")
  inspect(exported[0].role(), content="punctuation")
  inspect(
    exported.to_json().stringify(),
    content=(
      #|[{"start":0,"end":1,"role":"punctuation"},{"start":1,"end":4,"role":"property-key"},{"start":4,"end":5,"role":"punctuation"},{"start":6,"end":7,"role":"punctuation"},{"start":7,"end":10,"role":"string-value"},{"start":10,"end":11,"role":"punctuation"},{"start":12,"end":13,"role":"number-literal"},{"start":13,"end":14,"role":"punctuation"},{"start":15,"end":19,"role":"boolean-literal"},{"start":19,"end":20,"role":"punctuation"},{"start":21,"end":25,"role":"null-literal"},{"start":25,"end":26,"role":"punctuation"},{"start":26,"end":27,"role":"punctuation"}]
    ),
  )
}

///|
test "json roles expose recovered syntax errors and diagnostics" {
  let parser = @loom.new_syntax_parser("]", json_grammar.to_syntax_grammar())
  let roles = project_json_roles(parser.syntax_tree().read_or_abort())
  let diagnostics = parser.diagnostics().read_or_abort()
  guard diagnostics.length() > 0 else {
    fail("expected malformed JSON to keep parser diagnostics")
  }
  guard roles.any(span => span.role() == Error) else {
    fail("expected malformed JSON to expose an error role")
  }
}

///|
test "json roles surface diagnostic-only recoveries as error spans" {
  for source in ["{\"a\" 1}", "{\"a\":1,}", "[1,]", "[1 2]", ""] {
    let parser = @loom.new_syntax_parser(
      source,
      json_grammar.to_syntax_grammar(),
    )
    let roles = project_json_roles(parser.syntax_tree().read_or_abort())
    let diagnostics = parser.diagnostics().read_or_abort()
    guard diagnostics.length() > 0 else {
      fail("expected diagnostics for \{source}")
    }
    guard roles.any(span => span.role() == Error) else {
      fail("expected error role for \{source}")
    }
  }
}

///|
test "json roles after syntax parser edit match fresh parse" {
  let source = "{ \"name\": \"Alice\" }"
  let updated = "{ \"name\": \"Bob\" }"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  parser.apply_edit(@core.Edit::new(11, 5, 3), updated)
  let incremental_roles = project_json_roles(
    parser.syntax_tree().read_or_abort(),
  )
  let fresh_parser = @loom.new_syntax_parser(
    updated,
    json_grammar.to_syntax_grammar(),
  )
  let fresh_roles = project_json_roles(
    fresh_parser.syntax_tree().read_or_abort(),
  )
  let expected : Array[JsonRoleSpan] = [
    JsonRoleSpan(role=Punctuation, start=0, end=1),
    JsonRoleSpan(role=PropertyKey, start=2, end=8),
    JsonRoleSpan(role=Punctuation, start=8, end=9),
    JsonRoleSpan(role=StringValue, start=10, end=15),
    JsonRoleSpan(role=Punctuation, start=16, end=17),
  ]
  guard incremental_roles == fresh_roles else {
    fail("expected edited syntax parser roles to match a fresh parse")
  }
  guard fresh_roles == expected else {
    fail("expected updated source role spans")
  }
}
