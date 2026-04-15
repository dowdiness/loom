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

// --- Resolution tests ---

///|
test "resolve: bound variable stays Var" {
  // Module with def a=1, body=a → a is bound
  let term = TypedTerm::Module([("a", TypedTerm::Int(1))], TypedTerm::Var("a"))
  let resolved = resolve_typed(term)
  inspect(resolved.body, content="Var(\"a\")")
}

///|
test "resolve: free variable becomes Unbound" {
  // Module with no defs, body=x → x is free
  let term = TypedTerm::Module([], TypedTerm::Var("x"))
  let resolved = resolve_typed(term)
  inspect(resolved.body, content="Unbound(\"x\")")
}

///|
test "resolve: module sequential scoping" {
  // Module: def a = 1, def b = a, body = b
  // In def b, a is in scope. In body, both a and b are in scope.
  let term = TypedTerm::Module(
    [("a", TypedTerm::Int(1)), ("b", TypedTerm::Var("a"))],
    TypedTerm::Var("b"),
  )
  let resolved = resolve_typed(term)
  // def b's body sees a as bound
  inspect(resolved.defs[1].1, content="Var(\"a\")")
  // body sees b as bound
  inspect(resolved.body, content="Var(\"b\")")
}

///|
test "resolve: def body cannot see later defs" {
  // Module: def a = b, def b = 1, body = a
  // In def a, b is NOT yet in scope → becomes Unbound
  let term = TypedTerm::Module(
    [("a", TypedTerm::Var("b")), ("b", TypedTerm::Int(1))],
    TypedTerm::Var("a"),
  )
  let resolved = resolve_typed(term)
  inspect(resolved.defs[0].1, content="Unbound(\"b\")")
}

///|
test "resolve: lambda binds variable" {
  // \x. x  with no outer scope — x is bound by the lambda
  let term = TypedTerm::Lam("x", None, TypedTerm::Var("x"))
  let resolved = resolve_typed(term)
  inspect(resolved.body, content="Lam(\"x\", None, Var(\"x\"))")
}

///|
test "resolve: non-module term" {
  // Bare expression resolves with empty scope
  let term = TypedTerm::App(TypedTerm::Var("f"), TypedTerm::Int(1))
  let resolved = resolve_typed(term)
  // f is unbound since there's no module scope
  inspect(resolved.body, content="App(Unbound(\"f\"), Int(1))")
  inspect(resolved.defs.length(), content="0")
}

// --- Incremental pipeline tests ---

///|
test "incremental: basic typecheck through pipeline" {
  // Module: def f = \x:Int. x+1, body = f 5
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let module_term = TypedTerm::Module(
    [
      (
        "f",
        TypedTerm::Lam(
          "x",
          Some(TInt),
          TypedTerm::Bop(@ast.Bop::Plus, TypedTerm::Var("x"), TypedTerm::Int(1)),
        ),
      ),
    ],
    TypedTerm::App(TypedTerm::Var("f"), TypedTerm::Int(5)),
  )
  let term_signal = scope.signal(module_term, label="source_term")
  let term_memo = scope.memo(fn() { term_signal.get() }, label="source")
  let result_memo = build_typecheck_pipeline(rt, scope, term_memo)
  let result = result_memo.get_result().unwrap()
  // f : Int -> Int
  inspect(result.def_types[0].0, content="f")
  inspect(result.def_types[0].1.typ, content="Int -> Int")
  inspect(result.def_types[0].1.had_error, content="false")
  // body: f 5 : Int
  inspect(result.body_type.typ, content="Int")
  inspect(result.body_type.had_error, content="false")
  inspect(result.all_diagnostics.length(), content="0")
  scope.dispose()
}

///|
test "incremental: source unchanged = cache hit" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let module_term = TypedTerm::Module(
    [("a", TypedTerm::Int(42))],
    TypedTerm::Var("a"),
  )
  let term_signal = scope.signal(module_term, label="source_term")
  let term_memo = scope.memo(fn() { term_signal.get() }, label="source")
  let result_memo = build_typecheck_pipeline(rt, scope, term_memo)
  let r1 = result_memo.get_result().unwrap()
  let r2 = result_memo.get_result().unwrap()
  inspect(r1 == r2, content="true")
  scope.dispose()
}

///|
test "incremental: edit def body triggers recomputation" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  // Initially: def a = 1, body = a
  let module_term1 = TypedTerm::Module(
    [("a", TypedTerm::Int(1))],
    TypedTerm::Var("a"),
  )
  let term_signal = scope.signal(module_term1, label="source_term")
  let term_memo = scope.memo(fn() { term_signal.get() }, label="source")
  let result_memo = build_typecheck_pipeline(rt, scope, term_memo)
  let r1 = result_memo.get_result().unwrap()
  inspect(r1.body_type.typ, content="Int")
  // Now change def a's body to Unit
  let module_term2 = TypedTerm::Module(
    [("a", TypedTerm::Unit)],
    TypedTerm::Var("a"),
  )
  term_signal.set(module_term2)
  let r2 = result_memo.get_result().unwrap()
  inspect(r2.body_type.typ, content="Unit")
  inspect(r2.def_types[0].1.typ, content="Unit")
  scope.dispose()
}

///|
test "incremental: structural change rebuilds scope" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  // Initially: def a = 1, body = a
  let module_term1 = TypedTerm::Module(
    [("a", TypedTerm::Int(1))],
    TypedTerm::Var("a"),
  )
  let term_signal = scope.signal(module_term1, label="source_term")
  let term_memo = scope.memo(fn() { term_signal.get() }, label="source")
  let result_memo = build_typecheck_pipeline(rt, scope, term_memo)
  let r1 = result_memo.get_result().unwrap()
  inspect(r1.def_types.length(), content="1")
  // Now change to two defs: def a = 1, def b = a, body = b
  let module_term2 = TypedTerm::Module(
    [("a", TypedTerm::Int(1)), ("b", TypedTerm::Var("a"))],
    TypedTerm::Var("b"),
  )
  term_signal.set(module_term2)
  let r2 = result_memo.get_result().unwrap()
  inspect(r2.def_types.length(), content="2")
  inspect(r2.def_types[0].0, content="a")
  inspect(r2.def_types[1].0, content="b")
  inspect(r2.body_type.typ, content="Int")
  scope.dispose()
}

///|
test "incremental: empty module" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let module_term = TypedTerm::Module([], TypedTerm::Int(42))
  let term_signal = scope.signal(module_term, label="source_term")
  let term_memo = scope.memo(fn() { term_signal.get() }, label="source")
  let result_memo = build_typecheck_pipeline(rt, scope, term_memo)
  let result = result_memo.get_result().unwrap()
  inspect(result.def_types.length(), content="0")
  inspect(result.body_type.typ, content="Int")
  inspect(result.all_diagnostics.length(), content="0")
  scope.dispose()
}

///|
test "incremental: diagnostics propagate through pipeline" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  // def a = \x. x (unannotated lambda → error), body = a
  let module_term = TypedTerm::Module(
    [("a", TypedTerm::Lam("x", None, TypedTerm::Var("x")))],
    TypedTerm::Var("a"),
  )
  let term_signal = scope.signal(module_term, label="source_term")
  let term_memo = scope.memo(fn() { term_signal.get() }, label="source")
  let result_memo = build_typecheck_pipeline(rt, scope, term_memo)
  let result = result_memo.get_result().unwrap()
  inspect(result.def_types[0].1.had_error, content="true")
  // Diagnostics should be tagged with def name
  inspect(result.all_diagnostics.length() > 0, content="true")
  inspect(result.all_diagnostics[0].def_name, content="Some(\"a\")")
  scope.dispose()
}
