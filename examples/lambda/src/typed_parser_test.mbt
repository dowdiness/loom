// Integration tests for attach_typecheck — wires the reactive parser
// to the bidirectional type checker and verifies end-to-end flow on edit.

///|
test "attach_typecheck: clean program has zero diagnostics" {
  let parser = @loom.new_reactive_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  let result = typed.get()
  inspect(result.body_type.typ, content="Int")
  inspect(result.body_type.had_error, content="false")
  inspect(result.all_diagnostics.length(), content="0")
}

///|
test "attach_typecheck: unbound variable surfaces diagnostic" {
  let parser = @loom.new_reactive_parser("x + 1", lambda_grammar)
  let typed = attach_typecheck(parser)
  let result = typed.get()
  inspect(result.body_type.had_error, content="true")
  inspect(result.all_diagnostics.length(), content="1")
  inspect(result.all_diagnostics[0].message, content="unbound variable: x")
}

///|
test "attach_typecheck: unannotated lambda surfaces diagnostic" {
  let parser = @loom.new_reactive_parser("λx.x", lambda_grammar)
  let typed = attach_typecheck(parser)
  let result = typed.get()
  inspect(result.body_type.had_error, content="true")
  inspect(result.all_diagnostics.length(), content="1")
  inspect(result.all_diagnostics[0].message, content="missing type annotation")
}

///|
test "attach_typecheck: edit flows through (clean → error)" {
  let parser = @loom.new_reactive_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  inspect(typed.get().all_diagnostics.length(), content="0")
  parser.set_source("x + 1")
  let r = typed.get()
  inspect(r.all_diagnostics.length(), content="1")
  inspect(r.all_diagnostics[0].message, content="unbound variable: x")
}

///|
test "attach_typecheck: edit flows through (error → clean)" {
  let parser = @loom.new_reactive_parser("x + 1", lambda_grammar)
  let typed = attach_typecheck(parser)
  inspect(typed.get().all_diagnostics.length(), content="1")
  parser.set_source("1 + 2")
  let r = typed.get()
  inspect(r.body_type.typ, content="Int")
  inspect(r.all_diagnostics.length(), content="0")
}

///|
test "attach_typecheck: parse error does not abort the pipeline" {
  // "λx." is a parse error — the grammar cannot complete the lambda body.
  // Pipeline must still produce a ModuleTypeResult; reading it must not
  // abort. Recovery on a subsequent edit is also exercised.
  let parser = @loom.new_reactive_parser("λx.", lambda_grammar)
  let typed = attach_typecheck(parser)
  let _ = typed.get()
  parser.set_source("1 + 2")
  let r = typed.get()
  inspect(r.body_type.typ, content="Int")
  inspect(r.all_diagnostics.length(), content="0")
}

///|
test "attach_typecheck: dispose cleans up without affecting parser" {
  let parser = @loom.new_reactive_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  let _ = typed.get()
  typed.dispose()
  // Parser still works after typechecker scope is disposed.
  parser.set_source("42")
  inspect(@ast.print_term(parser.term()), content="42")
}

///|
test "attach_typecheck: chain survives Runtime::gc()" {
  // The persistent observer on the result Memo must keep the entire
  // reactive chain reachable — bridge Memo, parser term Memo, parser CST
  // Memo. Without it, `rt.gc()` would dispose all interior cells and
  // the next read would abort.
  let parser = @loom.new_reactive_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  let _ = typed.get()
  parser.runtime().gc()
  parser.set_source("3 + 4")
  let r = typed.get()
  inspect(r.body_type.typ, content="Int")
  inspect(r.all_diagnostics.length(), content="0")
}
