///|
fn wb_parse_to_syntax(source : String) -> @seam.SyntaxNode {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  rt.read(parser.syntax_tree())
}

///|
fn wb_def_named(defs : Array[@callers.Def], name : String) -> @callers.Def {
  for d in defs {
    if d.name == name {
      return d
    }
  }
  abort("expected def named " + name)
}

///|
test "compute_edits: top-level let rename produces def-site + caller edits" {
  let src = "let f = \\x. x\nlet r = f y\n"
  let syntax = wb_parse_to_syntax(src)
  let (defs, calls) = @callers.extract_facts(syntax)
  let f_def = wb_def_named(defs, "f")
  let edits = compute_edits(f_def, defs, calls, syntax, "fff")
  inspect(edits.length(), content="2")
  for e in edits {
    inspect(e.new_text, content="fff")
  }
}

///|
test "compute_edits: top-level let initializer sees only previous defs" {
  let src = "let f = f\nlet g = f\n"
  let syntax = wb_parse_to_syntax(src)
  let (defs, calls) = @callers.extract_facts(syntax)
  let f_def = wb_def_named(defs, "f")
  let edits = compute_edits(f_def, defs, calls, syntax, "fff")
  inspect(edits.length(), content="2")
  inspect(edits[0].start, content="4")
  inspect(edits[1].start, content="18")
}

///|
test "compute_edits: ignores calls in a different scope" {
  let src = "let g = \\f. f\n"
  let syntax = wb_parse_to_syntax(src)
  let (defs, calls) = @callers.extract_facts(syntax)
  let g_def = wb_def_named(defs, "g")
  let edits = compute_edits(g_def, defs, calls, syntax, "ggg")
  inspect(edits.length(), content="1")
}
