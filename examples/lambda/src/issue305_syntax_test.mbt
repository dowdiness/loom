///|
test "issue305: anonymous arrow lambda parses" {
  let term = parse("(x) => x") catch { _ => fail("parse failed") }
  inspect(@ast.print_term(term), content="(x) => x")
}

///|
test "issue305: arrow lambda allows newline before arrow" {
  let term = parse("(x)\n=> x") catch { _ => fail("parse failed") }
  inspect(@ast.print_term(term), content="(x) => x")
}

///|
test "issue305: multi-parameter arrow lambda desugars to curried Lam" {
  let term = parse("(x, y) => x y") catch { _ => fail("parse failed") }
  inspect(@ast.print_term(term), content="(x, y) => (x y)")
}

///|
test "issue305: named fn definition parses and pretty-prints with params" {
  let term = parse("fn add(x, y) { x + y }\nadd 1 2") catch {
    _ => fail("parse failed")
  }
  inspect(
    @ast.print_term(term),
    content="fn add(x, y) { (x + y) }\n((add 1) 2)",
  )
}

///|
test "issue305: let value declaration parses" {
  let term = parse("let answer = 42\nanswer") catch {
    _ => fail("parse failed")
  }
  inspect(@ast.print_term(term), content="let answer = 42\nanswer")
}

///|
test "issue305: top-level fn requires newline before trailing expression" {
  let (_, diagnostics) = parse_term("fn id(x) { x } id 1") catch {
    _ => fail("lex failed")
  }
  inspect(diagnostics.length() > 0, content="true")
  inspect(
    diagnostics.items()[0].message,
    content="Expected newline after top-level definition",
  )
}

///|
test "issue305: arrow block lambda with local defs roundtrips" {
  let term = parse("(x) => { let y = x; y }") catch {
    _ => fail("parse failed")
  }
  let source = @ast.print_term(term)
  inspect(source, content="(x) => { let y = x\ny }")
  let reparsed = parse(source) catch { _ => fail("reparse failed") }
  inspect(reparsed == term, content="true")

  let pretty_source = @pretty.pretty_unparse(term)
  let pretty_reparsed = parse(pretty_source) catch {
    _ => fail("pretty reparse failed")
  }
  inspect(pretty_reparsed == term, content="true")
}

///|
test "issue305: old lambda abstraction is now rejected" {
  let (_, diagnostics) = parse_term("\\x.x") catch { _ => fail("lex failed") }
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "issue305: let parameter-list function sugar is rejected" {
  let (_, diagnostics) = parse_term("let id(x) = x\nid 1") catch {
    _ => fail("lex failed")
  }
  inspect(diagnostics.length() > 0, content="true")
}
