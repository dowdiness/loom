///|
fn issue305_test_source_id() -> @core.SourceId {
  @core.SourceId::SourceId("lambda-issue305-syntax-test")
}

///|
test "issue305: anonymous arrow lambda parses" {
  let term = parse(issue305_test_source_id(), "(x) => x") catch {
    _ => fail("parse failed")
  }
  inspect(@ast.print_term(term), content="(x) => x")
}

///|
test "issue305: arrow lambda allows newline before arrow" {
  let term = parse(issue305_test_source_id(), "(x)\n=> x") catch {
    _ => fail("parse failed")
  }
  inspect(@ast.print_term(term), content="(x) => x")
}

///|
test "issue305: multi-parameter arrow lambda desugars to curried Lam" {
  let term = parse(issue305_test_source_id(), "(x, y) => x y") catch {
    _ => fail("parse failed")
  }
  inspect(@ast.print_term(term), content="(x) => (y) => x y")
}

///|
test "issue305: named fn definition parses and pretty-prints with params" {
  let term = parse(issue305_test_source_id(), "fn add(x, y) { x + y }\nadd 1 2") catch {
    _ => fail("parse failed")
  }
  inspect(
    @ast.print_term(term),
    content=(
      #|{ let add = (x) => (y) => x + y
      #|add 1 2 }
    ),
  )
}

///|
test "issue305: let value declaration parses" {
  let term = parse(issue305_test_source_id(), "let answer = 42\nanswer") catch {
    _ => fail("parse failed")
  }
  inspect(@ast.print_term(term), content="{ let answer = 42\nanswer }")
}

///|
test "issue305: top-level fn requires newline before trailing expression" {
  let (_, diagnostics) = parse_term(
    issue305_test_source_id(),
    "fn id(x) { x } id 1",
  ) catch {
    _ => fail("lex failed")
  }
  inspect(diagnostics.length() > 0, content="true")
  inspect(
    diagnostics.items()[0].message(),
    content="Expected newline after top-level definition",
  )
}

///|
test "issue305: arrow block lambda with local defs roundtrips" {
  let source_id = issue305_test_source_id()
  let term = parse(source_id, "(x) => { let y = x; y }") catch {
    _ => fail("parse failed")
  }
  let source = @ast.print_term(term)
  inspect(source, content="(x) => { let y = x\ny }")
  let reparsed = parse(source_id, source) catch { _ => fail("reparse failed") }
  inspect(reparsed == term, content="true")

  let pretty_source = @pretty.pretty_unparse(term)
  let pretty_reparsed = parse(source_id, pretty_source) catch {
    _ => fail("pretty reparse failed")
  }
  inspect(pretty_reparsed == term, content="true")
}

///|
test "issue305: old lambda abstraction is now rejected" {
  let (_, diagnostics) = parse_term(issue305_test_source_id(), "\\x.x") catch {
    _ => fail("lex failed")
  }
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "issue305: let parameter-list function sugar is rejected" {
  let (_, diagnostics) = parse_term(
    issue305_test_source_id(),
    "let id(x) = x\nid 1",
  ) catch {
    _ => fail("lex failed")
  }
  inspect(diagnostics.length() > 0, content="true")
}
