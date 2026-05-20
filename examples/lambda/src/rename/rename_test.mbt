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
