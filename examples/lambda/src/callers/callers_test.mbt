// End-to-end tests for the Tier 0 "show callers" projection.
//
// Pipeline tests use @loom.new_parser, which constructs a unified
// Parser[Ast] that owns the incremental engine and publishes derived
// state (source, syntax, ast, diagnostics) as @incr.Memo views. After the
// initial parse at Parser::new, source mutations go through
// parser.apply_edit(edit, new_source) so the engine reuses CST nodes
// rather than full-reparsing from scratch.

///|
/// Build a one-shot Parser and extract its current SyntaxNode. Used by
/// the pure-extraction tests below, which don't care about incremental
/// re-derivation.
fn parse_to_syntax(source : String) -> @seam.SyntaxNode {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  rt.read(parser.syntax_tree())
}

///|
test "extract_facts: defs and calls from three-deep call chain" {
  // f calls nothing; g calls f; h calls f.
  let src = "let f = 1\nlet g = f\nlet h = f\n"
  let (defs, calls) = extract_facts(parse_to_syntax(src))
  let def_names = defs.map(fn(d) { d.name })
  let call_names = calls.map(fn(c) { c.callee })
  inspect(def_names, content="[f, g, h]")
  inspect(call_names, content="[f, f]")
}

///|
test "build_callers_index: groups calls by callee" {
  let src = "let f = 1\nlet g = f\nlet h = f\nlet i = g\n"
  let (_, calls) = extract_facts(parse_to_syntax(src))
  let idx = build_callers_index(calls)
  inspect(idx.get("f").map(fn(arr) { arr.length() }), content="Some(2)")
  inspect(idx.get("g").map(fn(arr) { arr.length() }), content="Some(1)")
  inspect(idx.get("undefined"), content="None")
}

///|
test "pipeline: initial query returns correct callers" {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f\nlet h = f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="2")
  inspect(pipe.callers_of("g").length(), content="0")
  inspect(pipe.callers_of("nobody").length(), content="0")
  inspect(pipe.defs_of("f").length(), content="1")
}

///|
test "pipeline: apply_edit re-derives index incrementally" {
  // Initial source: "let f = 1\nlet g = f\n" (length 20)
  //                  0123456789012345678901
  //                            1111111111
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())

  // Initial: g calls f.
  inspect(pipe.callers_of("f").length(), content="1")

  // Append "let h = f\n" at position 20 (insert 10 chars, old_len=0).
  parser.apply_edit(
    @core.Edit::new(20, 0, 10),
    "let f = 1\nlet g = f\nlet h = f\n",
  )
  inspect(pipe.callers_of("f").length(), content="2")

  // Delete "let h = f\n" (10 chars at position 20).
  parser.apply_edit(@core.Edit::new(20, 10, 0), "let f = 1\nlet g = f\n")
  inspect(pipe.callers_of("f").length(), content="1")

  // Rename `f` to `fff` in "let f = 1": replace 1 char at position 4 with
  // "fff". Source becomes "let fff = 1\nlet g = f\n" (length 22). The
  // reference at the end still says "f", which is now undefined — but
  // the projection still records it as a caller of "f" (Tier 0 doesn't
  // do scope resolution).
  parser.apply_edit(@core.Edit::new(4, 1, 3), "let fff = 1\nlet g = f\n")
  inspect(pipe.callers_of("f").length(), content="1")
  inspect(pipe.callers_of("fff").length(), content="0")
  inspect(pipe.defs_of("fff").length(), content="1")
  inspect(pipe.defs_of("f").length(), content="0")
}

///|
test "pipeline: set_source forces full reparse" {
  // set_source discards incremental state — exercised once here to
  // confirm the pipeline still re-derives correctly through that path
  // (e.g., file-open or a non-edit-shaped source change).
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="0")
  parser.set_source("let f = 1\nlet g = f\nlet h = f\n")
  inspect(pipe.callers_of("f").length(), content="2")
}

///|
test "pipeline: nested call through Lambda body" {
  // The lambda body `\x. f` contains a VarRef to `f`, which counts as a use.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet apply = \\x. f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="1")
}

///|
test "pipeline: survives rt.gc() between queries" {
  // Regression test for the persistent-observer GC root. Without the
  // Observer anchoring the index Memo, rt.gc() would sweep the interior
  // facts/index cells (they have no other reachability path) and
  // subsequent reads would abort instead of returning empty arrays.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f\nlet h = f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="2")
  rt.gc()
  inspect(pipe.callers_of("f").length(), content="2")
  inspect(pipe.defs_of("f").length(), content="1")
  pipe.dispose()
}

///|
test "pipeline: malformed LetDef without IdentToken emits no ghost def" {
  // Regression test for the find_token None guard. Source with an
  // incomplete `let = 1` (no identifier) used to emit Def { name: "" }
  // because token_text() returns "" on a missing token. Now skipped.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let = 1\nlet g = f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.defs_of("").length(), content="0")
  inspect(pipe.defs_of("g").length(), content="1")
  pipe.dispose()
}

///|
test "pipeline: callers_of result is defensively copied" {
  // Regression test for the defensive copy. Mutating the returned array
  // must not affect subsequent reads of the cached index.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f\nlet h = f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  let first = pipe.callers_of("f")
  inspect(first.length(), content="2")
  first.clear()
  let second = pipe.callers_of("f")
  inspect(second.length(), content="2")
  pipe.dispose()
}
