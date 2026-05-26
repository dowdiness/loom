// Whitebox tests for internal helpers in the callers package.
//
// build_visibility takes Array[Def] + Array[(ScopeId, ScopeId)] as input.
// Synthetic Def construction requires whitebox access because `pub struct
// Def` is not `pub(all)` — field-construction is package-internal by
// MoonBit visibility rules.
//
// extract_facts_full is package-private; tests that need to exercise its
// 3-tuple shape directly live here too.

///|
/// Build a one-shot Parser and extract its current SyntaxNode. Mirrors
/// the helper in callers_test.mbt for whitebox tests that need to invoke
/// package-private extract_facts_full.
fn parse_to_syntax_wb(source : String) -> @seam.SyntaxNode {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  parser.syntax_tree().read_or_abort()
}

///|
test "extract_facts_full: emits TopScope edge for outermost LambdaExpr" {
  let src = "let g = \\x. x\n"
  let (_, _, enclosing) = extract_facts_full(parse_to_syntax_wb(src))
  // Exactly one LambdaScope, with TopScope as its parent.
  inspect(enclosing.length(), content="1")
  let (child, parent) = enclosing[0]
  inspect(parent is TopScope, content="true")
  inspect(child is LambdaScope(_, _), content="true")
}

///|
test "extract_facts_full: nested LambdaExpr emits chain of edges" {
  let src = "let g = \\x. \\y. x y\n"
  let (_, _, enclosing) = extract_facts_full(parse_to_syntax_wb(src))
  // Outer lambda -> TopScope, inner lambda -> outer lambda.
  inspect(enclosing.length(), content="2")
  let outer_edge = enclosing[0]
  inspect(outer_edge.1 is TopScope, content="true")
  let inner_edge = enclosing[1]
  inspect(inner_edge.1 is TopScope, content="false")
  inspect(inner_edge.1 is LambdaScope(_, _), content="true")
}

///|
test "extract_facts_full: let-paren params emit Enclosing edge" {
  let src = "let f(x, y) = x y\n"
  let (_, _, enclosing) = extract_facts_full(parse_to_syntax_wb(src))
  inspect(enclosing.length(), content="1")
  let (_, parent) = enclosing[0]
  inspect(parent is TopScope, content="true")
}

///|
test "visible_from: malformed lambda still sees enclosing bindings" {
  // `\. body` — frame pushed without a Def (ident_after_lead returns
  // None inside collect_in). The Enclosing edge is still emitted, so
  // the (empty) lambda scope inherits the top-level binding `f`.
  // Whitebox because identifying the malformed scope reuses
  // extract_facts_full to read its byte-range id.
  let src = "let f = 1\nlet g = \\. f\n"
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(src, @lambda.lambda_grammar, runtime=rt)
  let p = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  let (_, _, enclosing) = extract_facts_full(parse_to_syntax_wb(src))
  inspect(enclosing.length(), content="1")
  let malformed_scope = enclosing[0].0
  inspect(malformed_scope is LambdaScope(_, _), content="true")
  // The actual claim: f IS visible from the empty lambda scope.
  inspect(p.visible_from(malformed_scope, "f"), content="true")
  inspect(p.visible_from(malformed_scope, "not_a_real_name"), content="false")
  p.dispose()
}

///|
test "pipeline: survives rt.gc() before first read (facts_watch anchor)" {
  // Regression test for the constructor-priming + facts_watch anchor
  // introduced in this PR. Concrete failure mode without the prime:
  // `facts_watch` anchors `facts`, but `facts`'s `gc_dependencies`
  // are empty until its closure runs. An rt.gc() issued before any read
  // therefore sweeps the upstream `syntax_tree` Derived (the parser's
  // interior cell), and the next read aborts inside `facts`'s closure
  // when it calls `syntax.get_or_abort()`. The constructor's
  // `let _ = facts_watch.read_or_abort()` materializes the
  // `facts -> syntax_tree` edge before returning, so gc finds it.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let p = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  // gc immediately, before any reads.
  rt.gc()
  // All three public observers must still resolve.
  inspect(p.callers_of("f").length(), content="1")
  inspect(p.defs_of("f").length(), content="1")
  inspect(p.visible_from(TopScope, "f"), content="true")
  p.dispose()
}

///|
test "build_visibility: TopScope-only defs are visible from TopScope" {
  let defs : Array[Def] = [
    { name: "f", scope: TopScope, start: 0, end: 9, name_start: 4, name_end: 5 },
    {
      name: "g",
      scope: TopScope,
      start: 10,
      end: 19,
      name_start: 14,
      name_end: 15,
    },
  ]
  let enclosing : Array[(ScopeId, ScopeId)] = []
  let v = build_visibility(defs, enclosing)
  inspect(v.get((TopScope, "f")) is Some(_), content="true")
  inspect(v.get((TopScope, "g")) is Some(_), content="true")
  inspect(v.get((TopScope, "absent")) is Some(_), content="false")
}

///|
test "build_visibility: child scope inherits parent's bindings" {
  let inner = LambdaScope(10, 20)
  let defs : Array[Def] = [
    { name: "f", scope: TopScope, start: 0, end: 9, name_start: 4, name_end: 5 },
    {
      name: "x",
      scope: inner,
      start: 10,
      end: 20,
      name_start: 11,
      name_end: 12,
    },
  ]
  let enclosing : Array[(ScopeId, ScopeId)] = [(inner, TopScope)]
  let v = build_visibility(defs, enclosing)
  // Inner scope sees both its own param (x) and the inherited top-level binding (f).
  inspect(v.get((inner, "x")) is Some(_), content="true")
  inspect(v.get((inner, "f")) is Some(_), content="true")
  // TopScope sees only f, not x.
  inspect(v.get((TopScope, "f")) is Some(_), content="true")
  inspect(v.get((TopScope, "x")) is Some(_), content="false")
}

///|
test "build_visibility: deeply nested chain transitively inherits" {
  let outer = LambdaScope(5, 30)
  let inner = LambdaScope(15, 25)
  let defs : Array[Def] = [
    { name: "f", scope: TopScope, start: 0, end: 4, name_start: 0, name_end: 1 },
    { name: "x", scope: outer, start: 5, end: 30, name_start: 6, name_end: 7 },
    {
      name: "y",
      scope: inner,
      start: 15,
      end: 25,
      name_start: 16,
      name_end: 17,
    },
  ]
  let enclosing : Array[(ScopeId, ScopeId)] = [
    (outer, TopScope),
    (inner, outer),
  ]
  let v = build_visibility(defs, enclosing)
  // inner sees y (own), x (outer), f (TopScope).
  inspect(v.get((inner, "y")) is Some(_), content="true")
  inspect(v.get((inner, "x")) is Some(_), content="true")
  inspect(v.get((inner, "f")) is Some(_), content="true")
  // outer sees x and f, not y.
  inspect(v.get((outer, "x")) is Some(_), content="true")
  inspect(v.get((outer, "f")) is Some(_), content="true")
  inspect(v.get((outer, "y")) is Some(_), content="false")
}

///|
test "build_visibility: scope with no own bindings still inherits ancestors" {
  // Models the malformed-lambda case at callers.mbt:204: frame pushed
  // without a Def. The child scope must still appear and inherit.
  let empty_inner = LambdaScope(10, 12)
  let defs : Array[Def] = [
    { name: "f", scope: TopScope, start: 0, end: 9, name_start: 4, name_end: 5 },
  ]
  let enclosing : Array[(ScopeId, ScopeId)] = [(empty_inner, TopScope)]
  let v = build_visibility(defs, enclosing)
  inspect(v.get((empty_inner, "f")) is Some(_), content="true")
  inspect(v.get((empty_inner, "anything_else")) is Some(_), content="false")
}
