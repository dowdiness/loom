///|
test "resolve: free variable" {
  // x — free
  let term = @ast.Term::Var("x")
  let (_, res) = resolve(term)
  inspect(res.vars.get(0), content="Some(Free)")
}

///|
test "resolve: bound variable in lambda" {
  // λx. x — x is bound at depth 1
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let (_, res) = resolve(term)
  // node 0 = Lam (no var entry), node 1 = Var("x")
  inspect(res.vars.get(1), content="Some(Bound(depth=1))")
}

///|
test "resolve: free and bound in lambda" {
  // λx. (x + y) — x bound, y free
  // Pre-order: 0=Lam, 1=Bop, 2=Var(x), 3=Var(y)
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (_, res) = resolve(term)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Free)")
}

///|
test "resolve: nested lambda shadows outer binding" {
  // λx. λx. x — inner x shadows outer, depth=1
  // Pre-order: 0=Lam(x), 1=Lam(x), 2=Var(x)
  let term = @ast.Term::Lam("x", @ast.Term::Lam("x", @ast.Term::Var("x")))
  let (_, res) = resolve(term)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
}

///|
test "resolve: let binding" {
  // let x = 1 in x — x bound in body, not in initializer
  // Pre-order: 0=Let, 1=Int(1), 2=Var(x)
  let term = @ast.Term::Let("x", @ast.Term::Int(1), @ast.Term::Var("x"))
  let (_, res) = resolve(term)
  inspect(res.vars.get(1), content="None") // Int node, no var entry
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
}

///|
test "resolve: var in let initializer is free" {
  // let x = x in x — first x (in init) is free, second x (in body) is bound
  // Pre-order: 0=Let, 1=Var(x) init, 2=Var(x) body
  let term = @ast.Term::Let("x", @ast.Term::Var("x"), @ast.Term::Var("x"))
  let (_, res) = resolve(term)
  inspect(res.vars.get(1), content="Some(Free)")
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
}

///|
test "resolve: returns rewritten term with Unbound for free vars" {
  // y is free
  let term = @ast.Term::Var("y")
  let (resolved_term, res) = resolve(term)
  inspect(resolved_term, content="Unbound(\"y\")")
  inspect(res.vars.get(0), content="Some(Free)")
}

///|
test "resolve: bound vars remain as Var in rewritten term" {
  // λx. x — x is bound, stays Var
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let (resolved_term, _) = resolve(term)
  inspect(@ast.print_term(resolved_term), content="(λx. x)")
}

///|
test "resolve: mixed bound and free in rewritten term" {
  // λx. (x + y) — x bound stays Var, y free becomes Unbound
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (resolved_term, res) = resolve(term)
  inspect(
    @ast.print_term(resolved_term),
    content="(λx. (x + <unbound: y>))",
  )
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Free)")
}

///|
test "term_to_dot_resolved: colors bound green, free red" {
  // λx. (x + y)
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (resolved_term, res) = resolve(term)
  let dot = term_to_dot_resolved(resolved_term, res)
  // Bound var node should have green color
  inspect(dot.contains("#6a9955"), content="true")
  // Free var node should have red color
  inspect(dot.contains("#f44747"), content="true")
}
