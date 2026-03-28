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

///|
test "replay: Term roundtrip all variants" {
  let terms : Array[@ast.Term] = [
    @ast.Term::Int(0),
    @ast.Term::Var("x"),
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    @ast.Term::App(@ast.Term::Lam("x", @ast.Term::Var("x")), @ast.Term::Int(1)),
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(1), @ast.Term::Int(2)),
    @ast.Term::Bop(@ast.Bop::Minus, @ast.Term::Int(3), @ast.Term::Int(1)),
    @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3)),
    @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Var("x")),
    @ast.Term::Unit,
    @ast.Term::Unbound("y"),
    @ast.Term::Error("oops"),
  ]
  for term in terms {
    inspect((@ast.replay(term) : @ast.Term) == term, content="true")
  }
}

///|
test "replay: Pretty and Term from same source" {
  let term = @ast.Term::Bop(
    @ast.Bop::Plus,
    @ast.Term::Int(1),
    @ast.Term::Int(2),
  )
  inspect((@ast.replay(term) : @ast.Pretty).repr, content="(1 + 2)")
  inspect((@ast.replay(term) : @ast.Term), content="Bop(Plus, Int(1), Int(2))")
}

///|
test "replay: Pretty Lam" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  inspect((@ast.replay(term) : @ast.Pretty).repr, content="(λx. x)")
}

///|
test "replay: Pretty Module" {
  let term = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("y", @ast.Term::Int(2))],
    @ast.Term::Var("x"),
  )
  inspect(
    (@ast.replay(term) : @ast.Pretty).repr,
    content="let x = 1\nlet y = 2\nx",
  )
}
