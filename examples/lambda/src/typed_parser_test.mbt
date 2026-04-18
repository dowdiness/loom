// Integration tests for attach_typecheck — wires the unified `Parser[Term]`
// to the bidirectional type checker and verifies end-to-end flow on edit.

///|
test "attach_typecheck: clean program has zero diagnostics" {
  let parser = @loom.new_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  let result = typed.get()
  inspect(result.body_type.typ, content="Int")
  inspect(result.body_type.had_error, content="false")
  inspect(result.all_diagnostics.length(), content="0")
}

///|
test "attach_typecheck: unbound variable surfaces diagnostic" {
  let parser = @loom.new_parser("x + 1", lambda_grammar)
  let typed = attach_typecheck(parser)
  let result = typed.get()
  inspect(result.body_type.had_error, content="true")
  inspect(result.all_diagnostics.length(), content="1")
  inspect(result.all_diagnostics[0].message, content="unbound variable: x")
}

///|
test "attach_typecheck: unannotated lambda surfaces diagnostic" {
  let parser = @loom.new_parser("λx.x", lambda_grammar)
  let typed = attach_typecheck(parser)
  let result = typed.get()
  inspect(result.body_type.had_error, content="true")
  inspect(result.all_diagnostics.length(), content="1")
  inspect(result.all_diagnostics[0].message, content="missing type annotation")
}

///|
test "attach_typecheck: edit flows through set_source (clean → error)" {
  let parser = @loom.new_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  inspect(typed.get().all_diagnostics.length(), content="0")
  parser.set_source("x + 1")
  let r = typed.get()
  inspect(r.all_diagnostics.length(), content="1")
  inspect(r.all_diagnostics[0].message, content="unbound variable: x")
}

///|
test "attach_typecheck: edit flows through set_source (error → clean)" {
  let parser = @loom.new_parser("x + 1", lambda_grammar)
  let typed = attach_typecheck(parser)
  inspect(typed.get().all_diagnostics.length(), content="1")
  parser.set_source("1 + 2")
  let r = typed.get()
  inspect(r.body_type.typ, content="Int")
  inspect(r.all_diagnostics.length(), content="0")
}

///|
test "attach_typecheck: edit flows through apply_edit (clean → error)" {
  // apply_edit is the CST-reuse path — covers the same publication contract
  // as set_source but exercises the incremental engine underneath.
  let parser = @loom.new_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  inspect(typed.get().all_diagnostics.length(), content="0")
  parser.apply_edit(@core.Edit::new(0, 5, 5), "x + 1")
  let r = typed.get()
  inspect(r.all_diagnostics.length(), content="1")
  inspect(r.all_diagnostics[0].message, content="unbound variable: x")
}

///|
test "attach_typecheck: parse error does not abort the pipeline" {
  // "λx." is a parse error — the grammar cannot complete the lambda body.
  // Pipeline must still produce a ModuleTypeResult; reading it must not
  // abort. Recovery on a subsequent edit is also exercised.
  let parser = @loom.new_parser("λx.", lambda_grammar)
  let typed = attach_typecheck(parser)
  let _ = typed.get()
  parser.set_source("1 + 2")
  let r = typed.get()
  inspect(r.body_type.typ, content="Int")
  inspect(r.all_diagnostics.length(), content="0")
}

///|
test "attach_typecheck: unrecognized source produces a diagnostic, recovers on edit" {
  // Lambda's step-based lexer + `error_token` makes `@invalid` recoverable at
  // the lex layer — Parser publishes `syntax_tree() = Some(tree)` with an
  // ErrorNode child, not None. `convert_from_cst` reaches its unhandled-kind
  // arm and emits a `TypedTerm::Error` the typechecker surfaces as a
  // diagnostic. Covers the CST-error branch of the bridge and recovery on
  // a subsequent clean edit. The bridge's `None → TypedTerm::Error("parse")`
  // arm is unreachable from this grammar; it is exercised at the loom layer
  // in `loom/src/pipeline/parser_test.mbt` via a test-only language.
  let parser = @loom.new_parser("@invalid", lambda_grammar)
  let typed = attach_typecheck(parser)
  let initial = typed.get()
  inspect(initial.body_type.had_error, content="true")
  inspect(initial.all_diagnostics.length(), content="1")
  inspect(initial.all_diagnostics[0].message, content="unhandled CST kind")
  parser.set_source("1 + 2")
  let r = typed.get()
  inspect(r.body_type.typ, content="Int")
  inspect(r.all_diagnostics.length(), content="0")
}

///|
test "attach_typecheck: dispose cleans up without affecting parser" {
  let parser = @loom.new_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  let _ = typed.get()
  typed.dispose()
  // Parser still works after typechecker scope is disposed.
  parser.set_source("42")
  inspect(parser.runtime().read(parser.ast()) |> @ast.print_term, content="42")
}

///|
test "attach_typecheck: chain survives Runtime::gc()" {
  // The persistent observer on the result Memo must keep the entire
  // reactive chain reachable — bridge Memo, parser syntax-tree Memo,
  // internal signals. Without it, `rt.gc()` would dispose all interior
  // cells and the next read would abort.
  let parser = @loom.new_parser("1 + 2", lambda_grammar)
  let typed = attach_typecheck(parser)
  let _ = typed.get()
  parser.runtime().gc()
  parser.set_source("3 + 4")
  let r = typed.get()
  inspect(r.body_type.typ, content="Int")
  inspect(r.all_diagnostics.length(), content="0")
}
