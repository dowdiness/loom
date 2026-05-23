///|
fn wb_facts(
  source : String,
) -> (
  @seam.SyntaxNode,
  Array[@callers.Def],
  Array[@callers.Call],
  Array[(@callers.ScopeId, @callers.ScopeId)],
) {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  let pipeline = @callers.CallersPipeline::CallersPipeline(
    rt,
    parser.syntax_tree(),
  )
  let syntax = parser.syntax_tree().read_or_abort()
  let (defs, calls, enclosing) = pipeline.facts()
  pipeline.dispose()
  (syntax, defs, calls, enclosing)
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
  let (syntax, defs, calls, enclosing) = wb_facts(src)
  let f_def = wb_def_named(defs, "f")
  let edits = compute_edits(f_def, defs, calls, enclosing, syntax, "fff")
  inspect(edits.length(), content="2")
  for e in edits {
    inspect(e.new_text, content="fff")
  }
}

///|
test "compute_edits: top-level let initializer sees only previous defs" {
  let src = "let f = f\nlet g = f\n"
  let (syntax, defs, calls, enclosing) = wb_facts(src)
  let f_def = wb_def_named(defs, "f")
  let edits = compute_edits(f_def, defs, calls, enclosing, syntax, "fff")
  inspect(edits.length(), content="2")
  inspect(edits[0].start, content="4")
  inspect(edits[1].start, content="18")
}

///|
test "compute_edits: block let shadows parameter only after initializer" {
  let src = "let h = \\x. { let x = x; x }\n"
  let (syntax, defs, calls, enclosing) = wb_facts(src)
  let block_x = wb_def_with_name_start(defs, syntax, 18)
  let edits = compute_edits(block_x, defs, calls, enclosing, syntax, "y")
  inspect(edits.length(), content="2")
  inspect(edits[0].start, content="18")
  inspect(edits[1].start, content="25")
}

///|
test "compute_edits: block let is not visible after block" {
  let src = "let h = { let x = a; x } x\n"
  let (syntax, defs, calls, enclosing) = wb_facts(src)
  let block_x = wb_def_with_name_start(defs, syntax, 14)
  let edits = compute_edits(block_x, defs, calls, enclosing, syntax, "y")
  inspect(edits.length(), content="2")
  inspect(edits[0].start, content="14")
  inspect(edits[1].start, content="21")
}

///|
test "compute_edits: ignores calls in a different scope" {
  let src = "let g = \\f. f\n"
  let (syntax, defs, calls, enclosing) = wb_facts(src)
  let g_def = wb_def_named(defs, "g")
  let edits = compute_edits(g_def, defs, calls, enclosing, syntax, "ggg")
  inspect(edits.length(), content="1")
}

///|
fn wb_def_with_name_start(
  defs : Array[@callers.Def],
  syntax : @seam.SyntaxNode,
  start : Int,
) -> @callers.Def {
  for d in defs {
    let (name_start, _) = name_range_of(d, syntax)
    if name_start == start {
      return d
    }
  }
  abort("expected def with name starting at " + start.to_string())
}
