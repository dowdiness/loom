///|
test "eval: fuel exhaustion on omega combinator" {
  // (λx. x x)(λx. x x) — diverges
  let omega = @ast.Term::Lam(
    "x",
    @ast.Term::App(@ast.Term::Var("x"), @ast.Term::Var("x")),
  )
  let term = @ast.Term::App(omega, omega)
  let result : Result[Value, StuckReason] = try? eval(
    Env::empty(),
    term,
    fuel=50,
  )
  inspect(result, content="Err(Divergence)")
}

///|
test "eval: fuel works for deep but terminating computation" {
  // Nested application: ((λx.x) ((λx.x) ((λx.x) 42)))
  let id = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let term = @ast.Term::App(
    id,
    @ast.Term::App(id, @ast.Term::App(id, @ast.Term::Int(42))),
  )
  let result : Result[Value, StuckReason] = try? eval(
    Env::empty(),
    term,
    fuel=100,
  )
  inspect(result, content="Ok(VInt(42))")
}

///|
test "eval: Hole returns Incomplete" {
  let term = @ast.Term::Hole(0)
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Err(Incomplete)")
}

///|
test "eval: Error node returns ParseError" {
  let term = @ast.Term::Error("missing expression")
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Err(ParseError)")
}

///|
test "eval: Unbound node returns Unbound" {
  let term = @ast.Term::Unbound("foo")
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Err(Unbound(\"foo\"))")
}

///|
test "eval: empty module with Unit body" {
  let term = @ast.Term::Module([], @ast.Term::Unit)
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Ok(VUnit)")
}

///|
test "eval: module definition uses previous binding" {
  // let x = 2 \n let y = x + 1 \n y
  let term = @ast.Term::Module(
    [
      ("x", @ast.Term::Int(2)),
      ("y", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1))),
    ],
    @ast.Term::Var("y"),
  )
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(3))")
}

///|
test "eval: if with computed condition" {
  // if (2 - 2) then 10 else 20  →  20 (condition is 0)
  let term = @ast.Term::If(
    @ast.Term::Bop(Minus, @ast.Term::Int(2), @ast.Term::Int(2)),
    @ast.Term::Int(10),
    @ast.Term::Int(20),
  )
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(20))")
}

///|
test "eval: minus non-integer is type error" {
  let term = @ast.Term::Bop(
    Minus,
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    @ast.Term::Int(1),
  )
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Err(TypeMismatch(\"minus: expected integer\"))")
}

///|
test "eval: module forward reference fails" {
  // let y = x \n let x = 1 \n y — x not yet defined when y is evaluated
  let term = @ast.Term::Module(
    [("y", @ast.Term::Var("x")), ("x", @ast.Term::Int(1))],
    @ast.Term::Var("y"),
  )
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Err(Unbound(\"x\"))")
}

///|
test "eval: unit value flows through application" {
  // (λx. 1) unit → 1
  let term = @ast.Term::App(
    @ast.Term::Lam("x", @ast.Term::Int(1)),
    @ast.Term::Unit,
  )
  let result : Result[Value, StuckReason] = try? eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(1))")
}
