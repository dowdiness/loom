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
