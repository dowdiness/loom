///|
test "eval: integer literal" {
  let term = @ast.Term::Int(42)
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(42))")
}

///|
test "eval: unit literal" {
  let term = @ast.Term::Unit
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VUnit)")
}

///|
test "eval: variable lookup" {
  let env = Env::empty().extend("x", VInt(5))
  let term = @ast.Term::Var("x")
  let result : Result[Value, StuckReason] = try? @eval.eval(env, term)
  inspect(result, content="Ok(VInt(5))")
}

///|
test "eval: unbound variable" {
  let term = @ast.Term::Var("x")
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Err(Unbound(\"x\"))")
}

///|
test "eval: addition" {
  let term = @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3))
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(5))")
}

///|
test "eval: subtraction" {
  let term = @ast.Term::Bop(Minus, @ast.Term::Int(10), @ast.Term::Int(3))
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(7))")
}

///|
test "eval: nested arithmetic" {
  // (2 + 3) - 1
  let term = @ast.Term::Bop(
    Minus,
    @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3)),
    @ast.Term::Int(1),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(4))")
}

///|
test "eval: add non-integer is type error" {
  let term = @ast.Term::Bop(
    Plus,
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    @ast.Term::Int(1),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Err(TypeMismatch(\"add: expected integer\"))")
}

///|
test "eval: if truthy (non-zero)" {
  let term = @ast.Term::If(
    @ast.Term::Int(1),
    @ast.Term::Int(2),
    @ast.Term::Int(3),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(2))")
}

///|
test "eval: if falsy (zero)" {
  let term = @ast.Term::If(
    @ast.Term::Int(0),
    @ast.Term::Int(2),
    @ast.Term::Int(3),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(3))")
}

///|
test "eval: if with negative is truthy" {
  let term = @ast.Term::If(
    @ast.Term::Int(-1),
    @ast.Term::Int(10),
    @ast.Term::Int(20),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(10))")
}

///|
test "eval: if non-integer condition is type error" {
  let term = @ast.Term::If(
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    @ast.Term::Int(1),
    @ast.Term::Int(2),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(
    result,
    content="Err(TypeMismatch(\"if: expected integer condition\"))",
  )
}
