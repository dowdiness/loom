// Test for function application parsing bug

///|
test "parse function application (\\x.x) 5" {
  let input = "(\\x.x) 5"
  let result = parse(input) catch { e => abort("parse failed: \{e}") }
  // The AST should be an App node with Lam and Int children
  match result {
    @ast.Term::App(_, _) => ()
    _ => abort("Expected App term, got \{result}")
  }
  // Should have two sub-terms (func and arg)
  match result {
    @ast.Term::App(@ast.Term::Lam(_, _), @ast.Term::Int(5)) => ()
    _ => abort("Expected App(Lam, Int(5)), got \{result}")
  }
}

///|
test "parse simple application x 5" {
  let input = "x 5"
  let result = parse(input) catch { e => abort("parse failed: \{e}") }
  // The AST should be an App node
  match result {
    @ast.Term::App(_, _) => ()
    _ => abort("Expected App term, got \{result}")
  }
}

///|
test "parse parenthesized lambda (\\x.x)" {
  let input = "(\\x.x)"
  let result = parse(input) catch { e => abort("parse failed: \{e}") }
  // Should be a Lam term
  match result {
    @ast.Term::Lam(_, _) => ()
    _ => abort("Expected Lam term, got \{result}")
  }
}
