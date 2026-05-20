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
