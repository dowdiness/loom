// loom/examples/lambda/src/ast/sym_test.mbt

///|
test "replay: Term roundtrip for Int" {
  let term = @ast.Term::Int(42)
  inspect((@ast.replay(term) : @ast.Term) == term, content="true")
}

///|
test "replay: Term roundtrip for Lam" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  inspect((@ast.replay(term) : @ast.Term) == term, content="true")
}
