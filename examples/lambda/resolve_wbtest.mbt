///|
test "resolve: free variable" {
  // x — free
  let term = @ast.Term::Var("x")
  let (_, res) = resolve(term)
  debug_inspect(res.vars.get(0), content="Some(Free)")
}

///|
test "resolve: bound variable in lambda" {
  // (x) => x — x is bound at depth 1
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let (_, res) = resolve(term)
  // node 0 = Lam (no var entry), node 1 = Var("x")
  debug_inspect(res.vars.get(1), content="Some(Bound(depth=1))")
}

///|
test "resolve: free and bound in lambda" {
  // (x) => (x + y) — x bound, y free
  // Pre-order: 0=Lam, 1=Bop, 2=Var(x), 3=Var(y)
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (_, res) = resolve(term)
  debug_inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  debug_inspect(res.vars.get(3), content="Some(Free)")
}

///|
test "resolve: nested lambda shadows outer binding" {
  // (x, x) => x — inner x shadows outer, depth=1
  // Pre-order: 0=Lam(x), 1=Lam(x), 2=Var(x)
  let term = @ast.Term::Lam("x", @ast.Term::Lam("x", @ast.Term::Var("x")))
  let (_, res) = resolve(term)
  debug_inspect(res.vars.get(2), content="Some(Bound(depth=1))")
}

///|
test "resolve: let binding" {
  // let x = 1 \n x — x bound in body, not in initializer
  // Pre-order: 0=Module, 1=LetDef(x), 2=Int(1), 3=Var(x)
  let term = @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Var("x"))
  let (_, res) = resolve(term)
  inspect(res.vars.get(2) is None, content="true") // Int node, no var entry
  debug_inspect(res.vars.get(3), content="Some(Bound(depth=1))")
}

///|
test "resolve: var in let initializer is free" {
  // let x = x \n x — first x (init) is free, second x (body) is bound
  // Pre-order: 0=Module, 1=LetDef(x), 2=Var(x) init, 3=Var(x) body
  let term = @ast.Term::Module(
    [("x", @ast.Term::Var("x"))],
    @ast.Term::Var("x"),
  )
  let (_, res) = resolve(term)
  debug_inspect(res.vars.get(2), content="Some(Free)")
  debug_inspect(res.vars.get(3), content="Some(Bound(depth=1))")
}

///|
test "resolve: standalone LetDef resolves init without binding name" {
  let term = @ast.Term::LetDef("x", @ast.Term::Var("x"))
  let (resolved_term, res) = resolve(term)
  inspect(@ast.print_term(resolved_term), content="let x = <unbound: x>")
  debug_inspect(res.vars.get(1), content="Some(Free)")
}

///|
test "resolve: returns rewritten term with Unbound for free vars" {
  // y is free
  let term = @ast.Term::Var("y")
  let (resolved_term, res) = resolve(term)
  inspect(resolved_term, content="Unbound(\"y\")")
  debug_inspect(res.vars.get(0), content="Some(Free)")
}

///|
test "resolve: bound vars remain as Var in rewritten term" {
  // (x) => x — x is bound, stays Var
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let (resolved_term, _) = resolve(term)
  inspect(@ast.print_term(resolved_term), content="(x) => x")
}

///|
test "resolve: mixed bound and free in rewritten term" {
  // (x) => (x + y) — x bound stays Var, y free becomes Unbound
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (resolved_term, res) = resolve(term)
  inspect(
    @ast.print_term(resolved_term),
    content=(
      #|(x) => x + <unbound: y>
    ),
  )
  debug_inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  debug_inspect(res.vars.get(3), content="Some(Free)")
}

///|
test "resolve: nested let shadowing" {
  // let x = 1 \n let x = x \n x
  // Pre-order: 0=Module, 1=LetDef(x), 2=Int(1), 3=LetDef(x),
  // 4=Var(x) [2nd init], 5=Var(x) [body]
  let term = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("x", @ast.Term::Var("x"))],
    @ast.Term::Var("x"),
  )
  let (resolved_term, res) = resolve(term)
  // outer x in inner init is bound (depth=1), inner x in body is bound (depth=1)
  debug_inspect(res.vars.get(4), content="Some(Bound(depth=1))")
  debug_inspect(res.vars.get(5), content="Some(Bound(depth=1))")
  // no Unbound nodes — all vars are bound
  inspect(
    @ast.print_term(resolved_term),
    content=(
      #|{ let x = 1
      #|let x = x
      #|x }
    ),
  )
}

///|
test "resolve: idempotent on pre-resolved tree" {
  // resolve(resolve(t).0) should produce consistent results
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (resolved_once, _) = resolve(term)
  let (resolved_twice, res2) = resolve(resolved_once)
  // Tree should be identical
  inspect(
    @ast.print_term(resolved_twice),
    content=(
      #|(x) => x + <unbound: y>
    ),
  )
  // Unbound node should still be marked Free in the resolution map
  debug_inspect(res2.vars.get(3), content="Some(Free)")
}

///|
test "term_to_dot_resolved: colors bound green, free red" {
  // (x) => (x + y)
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
