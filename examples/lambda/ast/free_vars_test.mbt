// free_vars_test.mbt — tests for the FreeVars TermSym interpretation.

///|
test "free_vars: a variable is free" {
  inspect(
    @ast.free_vars(@ast.Term::Var("x")),
    content=(
      #|[x]
    ),
  )
}

///|
test "free_vars: lambda binds its parameter" {
  inspect(
    @ast.free_vars(@ast.Term::Lam("x", @ast.Term::Var("x"))),
    content="[]",
  )
  inspect(
    @ast.free_vars(@ast.Term::Lam("x", @ast.Term::Var("y"))),
    content=(
      #|[y]
    ),
  )
}

///|
test "free_vars: application unions both sides; sorted and deduped" {
  let unioned = @ast.Term::App(@ast.Term::Var("b"), @ast.Term::Var("a"))
  inspect(
    @ast.free_vars(unioned),
    content=(
      #|[a, b]
    ),
  )
  let duped = @ast.Term::App(@ast.Term::Var("x"), @ast.Term::Var("x"))
  inspect(
    @ast.free_vars(duped),
    content=(
      #|[x]
    ),
  )
}

///|
test "free_vars: bop and if union their children" {
  let b = @ast.Term::Bop(
    @ast.Bop::Plus,
    @ast.Term::Var("a"),
    @ast.Term::Var("b"),
  )
  inspect(
    @ast.free_vars(b),
    content=(
      #|[a, b]
    ),
  )
  let i = @ast.Term::If(
    @ast.Term::Var("c"),
    @ast.Term::Var("t"),
    @ast.Term::Var("e"),
  )
  inspect(
    @ast.free_vars(i),
    content=(
      #|[c, e, t]
    ),
  )
}

///|
test "free_vars: a standalone LetDef init passes through" {
  inspect(
    @ast.free_vars(@ast.Term::LetDef("x", @ast.Term::Var("y"))),
    content=(
      #|[y]
    ),
  )
}

///|
test "free_vars: unbound is free; literals and leaves are empty" {
  inspect(
    @ast.free_vars(@ast.Term::Unbound("z")),
    content=(
      #|[z]
    ),
  )
  inspect(@ast.free_vars(@ast.Term::Int(1)), content="[]")
  inspect(@ast.free_vars(@ast.Term::Unit), content="[]")
  inspect(@ast.free_vars(@ast.Term::Error("oops")), content="[]")
  inspect(@ast.free_vars(@ast.Term::Hole(0)), content="[]")
}

// ── Module scoping (mutually-recursive: defs bind across all defs + body) ──

///|
test "free_vars: a module binds its definition names" {
  // x defined and referenced internally → not free.
  let m1 = @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Var("x"))
  inspect(@ast.free_vars(m1), content="[]")
  // y referenced in a def init but never defined → free.
  let m2 = @ast.Term::Module([("x", @ast.Term::Var("y"))], @ast.Term::Var("x"))
  inspect(
    @ast.free_vars(m2),
    content=(
      #|[y]
    ),
  )
  // z referenced in the body but not defined → free; x defined → not free.
  let m3 = @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Var("z"))
  inspect(
    @ast.free_vars(m3),
    content=(
      #|[z]
    ),
  )
}

///|
test "free_vars: module binds names mutually — no leak across defs" {
  // `b`'s init references the earlier-defined `a`. Under mutually-recursive
  // scoping both names are bound, so nothing is free. The single-fold version
  // leaked `a` here; the two-phase version does not.
  let m = @ast.Term::Module(
    [("a", @ast.Term::Int(1)), ("b", @ast.Term::Var("a"))],
    @ast.Term::Unit,
  )
  inspect(@ast.free_vars(m), content="[]")
}
