// Tests for the bidirectional type checker.
// Terms are constructed directly (not via convert) to test infer/check in isolation.

///|
test "convert Int" {
  let term = @ast.Term::Int(42)
  let result = convert(term)
  inspect(result, content="Int(42)")
}

///|
test "convert Lam (no annotation)" {
  let term = @ast.Term::Lam("x", @ast.Term::Int(1))
  let result = convert(term)
  inspect(result, content="Lam(\"x\", None, Int(1))")
}

///|
test "convert Module" {
  let defs : Array[(@ast.VarName, @ast.Term)] = [("a", @ast.Term::Int(1))]
  let term = @ast.Term::Module(defs, @ast.Term::Var("a"))
  let result = convert(term)
  inspect(result, content="Module([(\"a\", Int(1))], Var(\"a\"))")
}

///|
test "infer Int literal" {
  let result = infer(TypeEnv::Empty, TypedTerm::Int(42))
  inspect(result.typ, content="Int")
  inspect(result.had_error, content="false")
  inspect(result.diagnostics.length(), content="0")
}

///|
test "infer Unit" {
  let result = infer(TypeEnv::Empty, TypedTerm::Unit)
  inspect(result.typ, content="Unit")
  inspect(result.had_error, content="false")
  inspect(result.diagnostics.length(), content="0")
}

///|
test "infer Var bound" {
  let env = TypeEnv::Empty.extend("x", TInt)
  let result = infer(env, TypedTerm::Var("x"))
  inspect(result.typ, content="Int")
  inspect(result.had_error, content="false")
}

///|
test "infer Var unbound" {
  let result = infer(TypeEnv::Empty, TypedTerm::Var("x"))
  inspect(result.typ, content="<error>")
  inspect(result.had_error, content="true")
  inspect(result.diagnostics.length(), content="1")
  inspect(result.diagnostics[0].message, content="unbound variable: x")
}

///|
test "infer annotated lambda" {
  let body = TypedTerm::Bop(
    @ast.Bop::Plus,
    TypedTerm::Var("x"),
    TypedTerm::Int(1),
  )
  let term = TypedTerm::Lam("x", Some(TInt), body)
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="Int -> Int")
  inspect(result.had_error, content="false")
}

///|
test "infer unannotated lambda fails" {
  let term = TypedTerm::Lam("x", None, TypedTerm::Var("x"))
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="<error>")
  inspect(result.had_error, content="true")
  inspect(result.diagnostics.length(), content="1")
  inspect(result.diagnostics[0].message, content="missing type annotation")
}

///|
test "infer application" {
  // (λx:Int. x + 1) 5
  let body = TypedTerm::Bop(
    @ast.Bop::Plus,
    TypedTerm::Var("x"),
    TypedTerm::Int(1),
  )
  let f = TypedTerm::Lam("x", Some(TInt), body)
  let term = TypedTerm::App(f, TypedTerm::Int(5))
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="Int")
  inspect(result.had_error, content="false")
}

///|
test "infer application of non-function" {
  let term = TypedTerm::App(TypedTerm::Int(5), TypedTerm::Int(3))
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="<error>")
  inspect(result.had_error, content="true")
  inspect(result.diagnostics.length(), content="1")
  inspect(result.diagnostics[0].message, content="not a function: got Int")
}

///|
test "infer binary op" {
  let term = TypedTerm::Bop(
    @ast.Bop::Plus,
    TypedTerm::Int(1),
    TypedTerm::Int(2),
  )
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="Int")
  inspect(result.had_error, content="false")
}

///|
test "infer binary op with wrong type" {
  let term = TypedTerm::Bop(@ast.Bop::Plus, TypedTerm::Unit, TypedTerm::Int(2))
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="Int")
  inspect(result.had_error, content="true")
  inspect(result.diagnostics.length(), content="1")
  inspect(result.diagnostics[0].message, content="expected Int, got Unit")
}

///|
test "infer if expression" {
  // if 1 then 2 else 3
  let term = TypedTerm::If(
    TypedTerm::Int(1),
    TypedTerm::Int(2),
    TypedTerm::Int(3),
  )
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="Int")
  inspect(result.had_error, content="false")
}

///|
test "infer if with wrong condition type" {
  // if Unit then 2 else 3
  let term = TypedTerm::If(
    TypedTerm::Unit,
    TypedTerm::Int(2),
    TypedTerm::Int(3),
  )
  let result = infer(TypeEnv::Empty, term)
  inspect(result.had_error, content="true")
  inspect(result.diagnostics.length(), content="1")
  inspect(result.diagnostics[0].message, content="expected Int, got Unit")
}

///|
test "infer Hole suppresses cascading" {
  // The hole itself emits one diagnostic; nothing else should cascade
  let result = infer(TypeEnv::Empty, TypedTerm::Hole(0))
  inspect(result.typ, content="<error>")
  inspect(result.had_error, content="true")
  inspect(result.diagnostics.length(), content="1")
  inspect(result.diagnostics[0].message, content="incomplete expression")
}

///|
test "error propagation: app of hole" {
  // (hole 5) — function is a hole, should not add a second "not a function" diagnostic
  let term = TypedTerm::App(TypedTerm::Hole(0), TypedTerm::Int(5))
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="<error>")
  inspect(result.had_error, content="true")
  // Exactly one diagnostic from the hole, no secondary "not a function"
  inspect(result.diagnostics.length(), content="1")
}

///|
test "check mode: unannotated lambda gets type from context" {
  // check (λx. x) against Int -> Int
  let term = TypedTerm::Lam("x", None, TypedTerm::Var("x"))
  let result = check(TypeEnv::Empty, term, TArrow(TInt, TInt))
  inspect(result.typ, content="Int -> Int")
  inspect(result.had_error, content="false")
}

///|
test "check mode: annotation mismatch" {
  // (λx:Unit. x) checked against Int -> Int — annotation says Unit, expected Int
  let term = TypedTerm::Lam("x", Some(TUnit), TypedTerm::Var("x"))
  let result = check(TypeEnv::Empty, term, TArrow(TInt, TInt))
  inspect(result.had_error, content="true")
  inspect(result.diagnostics.length(), content="1")
  inspect(
    result.diagnostics[0].message,
    content="annotation mismatch: expected Int, got Unit",
  )
}

///|
test "Show Type: arrow parenthesization" {
  // (Int -> Int) -> Int should display as "(Int -> Int) -> Int"
  let t = Type::TArrow(Type::TArrow(Type::TInt, Type::TInt), Type::TInt)
  inspect(t, content="(Int -> Int) -> Int")
}

///|
test "Show Type: right-associative arrow" {
  // Int -> Int -> Int displays as "Int -> Int -> Int"
  let t = Type::TArrow(Type::TInt, Type::TArrow(Type::TInt, Type::TInt))
  inspect(t, content="Int -> Int -> Int")
}

///|
test "Show TypeDiagnostic: with def_name" {
  let d : TypeDiagnostic = { message: "type error", def_name: Some("foo") }
  inspect(d, content="type error (in foo)")
}

///|
test "Show TypeDiagnostic: without def_name" {
  let d : TypeDiagnostic = { message: "type error", def_name: None }
  inspect(d, content="type error")
}

///|
test "TypeEnv lookup: shadowing" {
  let env = TypeEnv::Empty.extend("x", TInt).extend("x", TUnit)
  inspect(env.lookup("x"), content="Some(Unit)")
}

///|
test "infer module" {
  // let a = 1 in a
  let defs : Array[(String, TypedTerm)] = [("a", TypedTerm::Int(1))]
  let term = TypedTerm::Module(defs, TypedTerm::Var("a"))
  let result = infer(TypeEnv::Empty, term)
  inspect(result.typ, content="Int")
  inspect(result.had_error, content="false")
}
