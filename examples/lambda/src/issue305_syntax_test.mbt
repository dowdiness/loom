///|
test "issue305: anonymous arrow lambda parses" {
  let term = parse("(x) => x") catch { _ => fail("parse failed") }
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
