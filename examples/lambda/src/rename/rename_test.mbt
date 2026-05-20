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
