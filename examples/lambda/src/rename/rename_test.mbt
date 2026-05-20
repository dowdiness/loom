// Test fixtures for `plan_rename`. Fixtures are added one-by-one as
// each implementation task lands. See plan file for the fixture list.

///|
fn parse_to_syntax(source : String) -> @seam.SyntaxNode {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  rt.read(parser.syntax_tree())
}

///|
fn def_named(defs : Array[@callers.Def], name : String) -> @callers.Def {
  for d in defs {
    if d.name == name {
      return d
    }
  }
  abort("expected def named " + name)
}

///|
fn def_named_outside_scope(
  defs : Array[@callers.Def],
  name : String,
  excluded : @callers.ScopeId,
) -> @callers.Def {
  for d in defs {
    if d.name == name && !(d.scope == excluded) {
      return d
    }
  }
  abort("expected def named " + name + " outside excluded scope")
}

///|
fn facts_for_test(
  source : String,
) -> (
  @seam.SyntaxNode,
  Array[@callers.Def],
  Array[@callers.Call],
  Array[(@callers.ScopeId, @callers.ScopeId)],
) {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  let syntax = rt.read(parser.syntax_tree())
  let pipeline = @callers.CallersPipeline::CallersPipeline(
    rt,
    parser.syntax_tree(),
  )
  let (defs, calls, enclosing) = pipeline.facts()
  pipeline.dispose()
  (syntax, defs, calls, enclosing)
}

///|
fn setup_pipeline(
  source : String,
) -> (@callers.CallersPipeline, @seam.SyntaxNode, @incr.Runtime) {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  let pipeline = @callers.CallersPipeline::CallersPipeline(
    rt,
    parser.syntax_tree(),
  )
  let syntax = rt.read(parser.syntax_tree())
  (pipeline, syntax, rt)
}

///|
fn diagnostics_have_code(
  diagnostics : Array[@core.Diagnostic],
  code : String,
) -> Bool {
  for d in diagnostics {
    match d.code {
      Some(c) => if c.value() == code { return true }
      None => ()
    }
  }
  false
}

///|
fn edit_starting_at(edits : Array[TextEdit], start : Int) -> TextEdit {
  for e in edits {
    if e.start == start {
      return e
    }
  }
  abort("expected edit starting at " + start.to_string())
}

///|
fn edits_cover_offset(edits : Array[TextEdit], offset : Int) -> Bool {
  for e in edits {
    if offset >= e.start && offset < e.end {
      return true
    }
  }
  false
}

///|
test "name_range_of: top-level LetDef identifier" {
  let src = "let foo = bar\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let foo_def = def_named(defs, "foo")
  let (start, end) = name_range_of(foo_def, syntax)
  inspect(start, content="4")
  inspect(end, content="7")
}

///|
test "name_range_of: lambda parameter identifier" {
  let src = "let id = \\x. x\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let x_def = def_named(defs, "x")
  let (start, end) = name_range_of(x_def, syntax)
  inspect(start, content="10")
  inspect(end, content="11")
}

///|
test "name_range_of: let-paren parameter identifier" {
  let src = "let f (x) = x\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let x_def = def_named(defs, "x")
  let (start, end) = name_range_of(x_def, syntax)
  inspect(start, content="7")
  inspect(end, content="8")
}

///|
test "name_range_of: let-paren parameter can share function name" {
  let src = "let f (f) = f\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let target = locate_target(defs, syntax, 7)
  inspect(target is Some(_), content="true")
  let (start, end) = name_range_of(target.unwrap(), syntax)
  inspect(start, content="7")
  inspect(end, content="8")
}

///|
test "locate_target: hits top-level LetDef name" {
  let src = "let foo = bar\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let target = locate_target(defs, syntax, 5)
  inspect(target is Some(_), content="true")
  inspect(target.unwrap().name, content="foo")
}

///|
test "locate_target: hits lambda parameter, not enclosing LetDef" {
  let src = "let id = \\x. x\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let target = locate_target(defs, syntax, 10)
  inspect(target is Some(_), content="true")
  inspect(target.unwrap().name, content="x")
}

///|
test "locate_target: returns None for whitespace offset" {
  let src = "let foo = bar\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let target = locate_target(defs, syntax, 3)
  inspect(target is None, content="true")
}

///|
test "resolve_innermost: finds binding in same scope" {
  let (_, defs, _, enclosing) = facts_for_test("let x = a\n")
  let x_def = def_named(defs, "x")
  let result = resolve_innermost(x_def.scope, "x", defs, enclosing)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().name, content="x")
}

///|
test "resolve_innermost: walks parent chain" {
  let (_, defs, _, enclosing) = facts_for_test("let x = a\nlet id = \\y. y\n")
  let y_def = def_named(defs, "y")
  let result = resolve_innermost(y_def.scope, "x", defs, enclosing)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().name, content="x")
}

///|
test "resolve_innermost: innermost wins" {
  let (_, defs, _, enclosing) = facts_for_test("let x = a\nlet h = \\x. x\n")
  let outer_x = def_named(defs, "x")
  let inner_x = def_named_outside_scope(defs, "x", outer_x.scope)
  let result = resolve_innermost(inner_x.scope, "x", defs, enclosing)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().start, content=inner_x.start.to_string())
}

///|
test "resolve_innermost: returns None when no binding visible" {
  let (_, defs, _, enclosing) = facts_for_test("let x = a\n")
  let x_def = def_named(defs, "x")
  let result = resolve_innermost(x_def.scope, "y", defs, enclosing)
  inspect(result is None, content="true")
}

///|
test "check_sibling_collision: same-scope name match fires" {
  let src = "let f = a\nlet g = b\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let f_def = def_named(defs, "f")
  let result = check_sibling_collision(f_def, "g", defs, syntax)
  inspect(result is Some(_), content="true")
  let diag = result.unwrap()
  inspect(diag.severity is @core.DiagnosticSeverity::Error, content="true")
}

///|
test "check_sibling_collision: no collision returns None" {
  let src = "let f = a\nlet g = b\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let f_def = def_named(defs, "f")
  let result = check_sibling_collision(f_def, "totally_new", defs, syntax)
  inspect(result is None, content="true")
}

///|
test "is_strict_ancestor: top scope is ancestor of lambda scope" {
  let (_, defs, _, enclosing) = facts_for_test("let h = \\x. x\n")
  let h_def = def_named(defs, "h")
  let x_def = def_named(defs, "x")
  inspect(
    is_strict_ancestor(h_def.scope, x_def.scope, enclosing),
    content="true",
  )
}

///|
test "is_strict_ancestor: equal scopes return false" {
  let (_, defs, _, enclosing) = facts_for_test("let h = \\x. x\n")
  let x_def = def_named(defs, "x")
  inspect(
    is_strict_ancestor(x_def.scope, x_def.scope, enclosing),
    content="false",
  )
}

///|
test "is_strict_ancestor: sibling lambda scopes return false" {
  let (_, defs, _, enclosing) = facts_for_test(
    "let a = \\x. x\nlet b = \\y. y\n",
  )
  let x_def = def_named(defs, "x")
  let y_def = def_named(defs, "y")
  inspect(
    is_strict_ancestor(x_def.scope, y_def.scope, enclosing),
    content="false",
  )
}

///|
test "check_forward_capture: descendant binding fires" {
  let src = "let h = \\f. \\g. f g\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let h_def = def_named(defs, "h")
  let outer_f = def_named_outside_scope(defs, "f", h_def.scope)
  let result = check_forward_capture(outer_f, "g", defs, enclosing, syntax)
  inspect(result is Some(_), content="true")
  inspect(
    result.unwrap().severity is @core.DiagnosticSeverity::Error,
    content="true",
  )
}

///|
test "check_forward_capture: no descendant with new_name returns None" {
  let src = "let f = \\x. x\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let f_def = def_named(defs, "f")
  let result = check_forward_capture(
    f_def, "totally_new", defs, enclosing, syntax,
  )
  inspect(result is None, content="true")
}

///|
test "check_converse_capture: existing call to new_name with target as descendant" {
  let src = "let g = a\nlet h = \\f. f g\n"
  let (syntax, defs, calls, enclosing) = facts_for_test(src)
  let f_param = def_named(defs, "f")
  let result = check_converse_capture(f_param, "g", calls, enclosing, syntax)
  inspect(result is Some(_), content="true")
  inspect(
    result.unwrap().severity is @core.DiagnosticSeverity::Error,
    content="true",
  )
}

///|
test "check_converse_capture: no matching calls returns None" {
  let src = "let f = a\n"
  let (syntax, defs, calls, enclosing) = facts_for_test(src)
  let f_def = def_named(defs, "f")
  let result = check_converse_capture(
    f_def, "totally_new", calls, enclosing, syntax,
  )
  inspect(result is None, content="true")
}

///|
test "check_shadow: param shadows outer let binding" {
  let src = "let g = a\nlet h = \\f. f\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let f_param = def_named(defs, "f")
  let result = check_shadow(f_param, "g", defs, enclosing, syntax)
  inspect(result is Some(_), content="true")
  inspect(
    result.unwrap().severity is @core.DiagnosticSeverity::Warning,
    content="true",
  )
}

///|
test "check_shadow: no outer binding returns None" {
  let src = "let h = \\f. f\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let f_param = def_named(defs, "f")
  let result = check_shadow(f_param, "g", defs, enclosing, syntax)
  inspect(result is None, content="true")
}

///|
test "fixture 1 (smoke): top-level let rename, three edits, no diagnostics" {
  let src = "let f = \\x. x\nlet r = f (f y)\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 4, "fff")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.target.unwrap().name, content="f")
  inspect(plan.edits.length(), content="3")
  for e in plan.edits {
    inspect(e.new_text, content="fff")
  }
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "fixture 2 (sibling collision): rename f -> g when g exists at same scope" {
  let src = "let f = a\nlet g = b\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 4, "g")
  inspect(plan.target.unwrap().name, content="f")
  inspect(plan.edits.length() >= 1, content="true")
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.sibling_collision"),
    content="true",
  )
  pipeline.dispose()
}

///|
test "fixture 10 (name-range correctness): edit byte ranges are identifier-token, not node, ranges" {
  let src1 = "let foo = bar\n"
  let (pipeline1, syntax1, _rt1) = setup_pipeline(src1)
  let plan1 = plan_rename(pipeline1, src1, syntax1, 5, "renamed")
  let def_edit1 = edit_starting_at(plan1.edits, 4)
  inspect(def_edit1.end, content="7")
  pipeline1.dispose()

  let src2 = "let id = \\x. x\n"
  let (pipeline2, syntax2, _rt2) = setup_pipeline(src2)
  let plan2 = plan_rename(pipeline2, src2, syntax2, 10, "y")
  let def_edit2 = edit_starting_at(plan2.edits, 10)
  inspect(def_edit2.end, content="11")
  pipeline2.dispose()

  let src3 = "let f (x) = x\n"
  let (pipeline3, syntax3, _rt3) = setup_pipeline(src3)
  let plan3 = plan_rename(pipeline3, src3, syntax3, 7, "y")
  let def_edit3 = edit_starting_at(plan3.edits, 7)
  inspect(def_edit3.end, content="8")
  pipeline3.dispose()
}

///|
test "fixture 11 (let-paren repeated name): parameter rename does not edit function name" {
  let src = "let f (f) = f\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 7, "g")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.target.unwrap().name, content="f")
  inspect(plan.edits.length(), content="2")
  inspect(edits_cover_offset(plan.edits, 4), content="false")
  inspect(edits_cover_offset(plan.edits, 7), content="true")
  inspect(edits_cover_offset(plan.edits, 12), content="true")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "fixture 12 (top-level source order): forward free reference is not rewritten" {
  let src = "let a = f\nlet f = z\nlet b = f\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 14, "g")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.target.unwrap().name, content="f")
  inspect(plan.edits.length(), content="2")
  inspect(edits_cover_offset(plan.edits, 8), content="false")
  inspect(edits_cover_offset(plan.edits, 14), content="true")
  inspect(edits_cover_offset(plan.edits, 28), content="true")
  pipeline.dispose()
}

///|
test "fixture 13 (sequential top-level): self-reference is not rewritten" {
  let src = "let f = f\nlet g = f\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 4, "fff")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.target.unwrap().name, content="f")
  inspect(plan.edits.length(), content="2")
  inspect(edits_cover_offset(plan.edits, 4), content="true")
  inspect(edits_cover_offset(plan.edits, 8), content="false")
  inspect(edits_cover_offset(plan.edits, 18), content="true")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "fixture 14 (sequential top-level): duplicate name sees previous binding" {
  let src = "let f = a\nlet f = f\nlet g = f\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let first_plan = plan_rename(pipeline, src, syntax, 4, "first")
  inspect(first_plan.target is Some(_), content="true")
  inspect(first_plan.edits.length(), content="2")
  inspect(edits_cover_offset(first_plan.edits, 4), content="true")
  inspect(edits_cover_offset(first_plan.edits, 14), content="false")
  inspect(edits_cover_offset(first_plan.edits, 18), content="true")
  inspect(edits_cover_offset(first_plan.edits, 28), content="false")
  let second_plan = plan_rename(pipeline, src, syntax, 14, "second")
  inspect(second_plan.target is Some(_), content="true")
  inspect(second_plan.edits.length(), content="2")
  inspect(edits_cover_offset(second_plan.edits, 4), content="false")
  inspect(edits_cover_offset(second_plan.edits, 14), content="true")
  inspect(edits_cover_offset(second_plan.edits, 18), content="false")
  inspect(edits_cover_offset(second_plan.edits, 28), content="true")
  pipeline.dispose()
}

///|
test "fixture 15 (block let): local binding does not edit initializer" {
  let src = "let h = \\x. { let x = x; x }\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 18, "y")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.edits.length(), content="2")
  inspect(edits_cover_offset(plan.edits, 9), content="false")
  inspect(edits_cover_offset(plan.edits, 18), content="true")
  inspect(edits_cover_offset(plan.edits, 22), content="false")
  inspect(edits_cover_offset(plan.edits, 25), content="true")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "fixture 16 (block let): unique local binding edits body reference" {
  let src = "let h = \\x. { let y = x; y }\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 18, "z")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.edits.length(), content="2")
  inspect(edits_cover_offset(plan.edits, 18), content="true")
  inspect(edits_cover_offset(plan.edits, 25), content="true")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "fixture 17 (block let): local binding does not leak after block" {
  let src = "let h = { let x = a; x } x\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 14, "y")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.edits.length(), content="2")
  inspect(edits_cover_offset(plan.edits, 14), content="true")
  inspect(edits_cover_offset(plan.edits, 21), content="true")
  inspect(edits_cover_offset(plan.edits, 25), content="false")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "check_sibling_collision: target is not its own sibling" {
  let src = "let f = a\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let target = def_named(defs, "f")
  inspect(
    check_sibling_collision(target, "f", defs, syntax) is None,
    content="true",
  )
}

///|
test "fixture 3 (forward capture): outer f rename to g, inner g intercepts" {
  let src = "let h = \\f. \\g. f g\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 9, "g")
  inspect(plan.target.unwrap().name, content="f")
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.capture"),
    content="true",
  )
  pipeline.dispose()
}

///|
test "fixture 4 (converse capture + shadow): rename param f -> g where outer g exists" {
  let src = "let g = a\nlet h = \\f. f g\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 19, "g")
  inspect(plan.target.unwrap().name, content="f")
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.capture"),
    content="true",
  )
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.shadow"),
    content="true",
  )
  pipeline.dispose()
}

///|
test "fixture 5 (shadow only): rename param f -> g, no body reference to g" {
  let src = "let g = a\nlet h = \\f. f\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 19, "g")
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.shadow"),
    content="true",
  )
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.capture"),
    content="false",
  )
  pipeline.dispose()
}

///|
test "fixture 6 (sequential top-level): rename f -> fff, self-ref untouched" {
  let src = "let f = \\x. f x\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 4, "fff")
  inspect(plan.target.unwrap().name, content="f")
  inspect(plan.edits.length(), content="1")
  inspect(edits_cover_offset(plan.edits, 4), content="true")
  inspect(edits_cover_offset(plan.edits, 12), content="false")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "fixture 7 (let-paren parameter): rename x -> y in let f (x) = x" {
  let src = "let f (x) = x\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 7, "y")
  inspect(plan.target.unwrap().name, content="x")
  inspect(plan.edits.length(), content="2")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}

///|
test "fixture 8 (no-op): rename f -> f produces single Info diagnostic" {
  let src = "let f = a\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 4, "f")
  inspect(plan.edits.length(), content="0")
  inspect(plan.diagnostics.length(), content="1")
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.no_op"),
    content="true",
  )
  inspect(
    plan.diagnostics[0].severity is @core.DiagnosticSeverity::Info,
    content="true",
  )
  pipeline.dispose()
}

///|
test "fixture 9 (offset miss): whitespace offset returns no_target diagnostic" {
  let src = "let f = a\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 3, "fff")
  inspect(plan.target is None, content="true")
  inspect(plan.edits.length(), content="0")
  inspect(
    diagnostics_have_code(plan.diagnostics, "rename.no_target_at_offset"),
    content="true",
  )
  pipeline.dispose()
}
