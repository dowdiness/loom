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
    @ast.Term::Hole(0),
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

///|
test "children_of/rebuild_from roundtrip: all variants" {
  let terms : Array[@ast.Term] = [
    @ast.Term::Int(0),
    @ast.Term::Var("x"),
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    @ast.Term::App(@ast.Term::Lam("x", @ast.Term::Var("x")), @ast.Term::Int(1)),
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(1), @ast.Term::Int(2)),
    @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3)),
    @ast.Term::Module(
      [("x", @ast.Term::Int(1)), ("y", @ast.Term::Int(2))],
      @ast.Term::Var("x"),
    ),
    @ast.Term::Unit,
    @ast.Term::Unbound("y"),
    @ast.Term::Error("oops"),
    @ast.Term::Hole(0),
  ]
  for term in terms {
    let rebuilt = @ast.rebuild_from(term, @ast.children_of(term))
    inspect(rebuilt == term, content="true")
  }
}

///|
test "children_of: leaf variants have no children" {
  let leaves : Array[@ast.Term] = [
    @ast.Term::Int(42),
    @ast.Term::Var("x"),
    @ast.Term::Unit,
    @ast.Term::Unbound("y"),
    @ast.Term::Error("oops"),
    @ast.Term::Hole(0),
  ]
  for leaf in leaves {
    inspect(@ast.children_of(leaf).length(), content="0")
  }
}

///|
test "children_of: branch arities" {
  inspect(
    @ast.children_of(@ast.Term::Lam("x", @ast.Term::Var("x"))).length(),
    content="1",
  )
  inspect(
    @ast.children_of(
      @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x")),
    ).length(),
    content="2",
  )
  inspect(
    @ast.children_of(
      @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3)),
    ).length(),
    content="3",
  )
}

///|
test "children_of: Module children = defs values + body" {
  let m = @ast.Term::Module(
    [("a", @ast.Term::Int(1)), ("b", @ast.Term::Int(2))],
    @ast.Term::Var("a"),
  )
  let children = @ast.children_of(m)
  inspect(children.length(), content="3")
  inspect(children[0], content="Int(1)")
  inspect(children[1], content="Int(2)")
  inspect(children[2], content="Var(\"a\")")
}

///|
test "rebuild_from: Module preserves def names" {
  let shape = @ast.Term::Module(
    [("x", @ast.Term::Int(0)), ("y", @ast.Term::Int(0))],
    @ast.Term::Unit,
  )
  let new_children = [@ast.Term::Int(10), @ast.Term::Int(20), @ast.Term::Var("z")]
  let rebuilt = @ast.rebuild_from(shape, new_children)
  inspect(
    rebuilt,
    content="Module([(\"x\", Int(10)), (\"y\", Int(20))], Var(\"z\"))",
  )
}

///|
test "rebuild_from: missing children produce Error" {
  let rebuilt = @ast.rebuild_from(@ast.Term::App(@ast.Term::Unit, @ast.Term::Unit), [])
  inspect(
    rebuilt,
    content="App(Error(\"missing\"), Error(\"missing\"))",
  )
}

///|
test "rebuild_from: empty Module children" {
  let shape = @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Unit)
  let rebuilt = @ast.rebuild_from(shape, [])
  inspect(rebuilt, content="Module([], Error(\"missing\"))")
}
