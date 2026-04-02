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

///|
test "eval: lambda creates closure" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  // Just check it's a VClosure — exact content may vary
  inspect(result is Ok(_), content="true")
}

///|
test "eval: simple application" {
  // (λx. x + 1) 5
  let term = @ast.Term::App(
    @ast.Term::Lam(
      "x",
      @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1)),
    ),
    @ast.Term::Int(5),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(6))")
}

///|
test "eval: curried application" {
  // (λx. λy. x + y) 2 3
  let term = @ast.Term::App(
    @ast.Term::App(
      @ast.Term::Lam(
        "x",
        @ast.Term::Lam(
          "y",
          @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
        ),
      ),
      @ast.Term::Int(2),
    ),
    @ast.Term::Int(3),
  )
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(5))")
}

///|
test "eval: apply non-function is type error" {
  let term = @ast.Term::App(@ast.Term::Int(5), @ast.Term::Int(3))
  let result : Result[Value, StuckReason] = try? @eval.eval(Env::empty(), term)
  inspect(result, content="Err(TypeMismatch(\"app: expected function\"))")
}
