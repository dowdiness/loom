// End-to-end tests for the "show callers" projection.
//
// Pipeline tests use @loom.new_parser, which constructs a unified
// Parser[Ast] that owns the incremental engine and publishes derived
// state (source, syntax, ast, diagnostics) as @incr.Derived views. After the
// initial parse at Parser::new, source mutations go through
// parser.apply_edit(edit, new_source) so the engine reuses CST nodes
// rather than full-reparsing from scratch.
//
// Semantics (Tier 1, post scope structure):
//   - `callers_of(name)` returns Calls whose `callee == name`, AND whose
//     `resolved_scope == TopScope` (not shadowed by an enclosing lambda
//     or let-param), AND whose `is_call_position` is true (parent is an
//     AppExpr in function position, transparently through ParenExpr).
//   - `defs_of(name)` returns ALL bindings of that name — top-level
//     LetDefs (scope=TopScope) AND lambda params / let-params
//     (scope=LambdaScope). Consumers filter on `.scope` if needed.

///|
/// Build a one-shot Parser and extract its current SyntaxNode. Used by
/// the pure-extraction tests below, which don't care about incremental
/// re-derivation.
fn parse_to_syntax(source : String) -> @seam.SyntaxNode {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  parser.syntax_tree().read_or_abort()
}

///|
test "extract_facts: defs and calls from three-deep call chain" {
  // f calls nothing; g calls f; h calls f. (Calls are AppExpr.func position.)
  let src = "let f = 1\nlet g = f x\nlet h = f x\n"
  let (defs, calls) = extract_facts(parse_to_syntax(src))
  let def_names = defs.map(fn(d) { d.name })
  let call_names = calls.map(fn(c) { c.callee })
  debug_inspect(def_names, content="[\"f\", \"g\", \"h\"]")
  // Calls include every VarRef (both function- and arg-position); the
  // is_call_position flag is what `callers_of` uses to filter.
  debug_inspect(call_names, content="[\"f\", \"x\", \"f\", \"x\"]")
}

///|
test "extract_facts: top-level Defs are tagged TopScope" {
  let src = "let f = 1\nlet g = 2\n"
  let (defs, _) = extract_facts(parse_to_syntax(src))
  inspect(defs.length(), content="2")
  for d in defs {
    inspect(d.scope is TopScope, content="true")
  }
}

///|
test "extract_facts: lambda parameter Defs are tagged LambdaScope" {
  // `let shadow = \f. f` — top-level `shadow` (TopScope) +
  // a lambda param `f` (LambdaScope).
  let src = "let shadow = \\f. f\n"
  let (defs, _) = extract_facts(parse_to_syntax(src))
  inspect(defs.length(), content="2")
  inspect(defs[0].name, content="shadow")
  inspect(defs[0].scope is TopScope, content="true")
  inspect(defs[1].name, content="f")
  inspect(defs[1].scope is TopScope, content="false")
}

///|
test "extract_facts: VarRef in AppExpr.func position has is_call_position=true" {
  // `let g = f x` — `f` is function-position (call), `x` is arg-position (data).
  let src = "let g = f x\n"
  let (_, calls) = extract_facts(parse_to_syntax(src))
  inspect(calls.length(), content="2")
  inspect(calls[0].callee, content="f")
  inspect(calls[0].is_call_position, content="true")
  inspect(calls[1].callee, content="x")
  inspect(calls[1].is_call_position, content="false")
}

///|
test "build_callers_index: groups calls by callee" {
  // build_callers_index is now a thin utility — it groups whatever Calls
  // are passed in. The filtering for `callers_of` happens in the Derived
  // body before this is called.
  let src = "let f = 1\nlet g = f x\nlet h = f x\nlet i = g x\n"
  let (_, calls) = extract_facts(parse_to_syntax(src))
  let idx = build_callers_index(calls)
  // f appears twice (in g, in h); g once (in i); each call body also has
  // an `x` VarRef in arg position.
  debug_inspect(idx.get("f").map(fn(arr) { arr.length() }), content="Some(2)")
  debug_inspect(idx.get("g").map(fn(arr) { arr.length() }), content="Some(1)")
  debug_inspect(idx.get("x").map(fn(arr) { arr.length() }), content="Some(3)")
  debug_inspect(idx.get("undefined"), content="None")
}

///|
test "pipeline: initial query returns correct callers" {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f x\nlet h = f x\n",
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
  // Initial source:  "let f = 1\nlet g = f x\n" (length 22)
  //                   012345678901234567890123
  //                             1111111111222
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())

  // Initial: g calls f.
  inspect(pipe.callers_of("f").length(), content="1")

  // Append "let h = f x\n" at position 22 (insert 12 chars, old_len=0).
  parser.apply_edit(
    @core.Edit::new(22, 0, 12),
    "let f = 1\nlet g = f x\nlet h = f x\n",
  )
  inspect(pipe.callers_of("f").length(), content="2")

  // Delete "let h = f x\n" (12 chars at position 22).
  parser.apply_edit(@core.Edit::new(22, 12, 0), "let f = 1\nlet g = f x\n")
  inspect(pipe.callers_of("f").length(), content="1")

  // Rename `f` to `fff` in "let f = 1": replace 1 char at position 4 with
  // "fff". Source becomes "let fff = 1\nlet g = f x\n" (length 24). The
  // call site at `f x` still says "f", which is now undefined — but the
  // projection still records it as a top-scope caller of "f" (Tier 1
  // doesn't distinguish bound-to-top vs unbound).
  parser.apply_edit(@core.Edit::new(4, 1, 3), "let fff = 1\nlet g = f x\n")
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
  parser.set_source("let f = 1\nlet g = f x\nlet h = f x\n")
  inspect(pipe.callers_of("f").length(), content="2")
}

///|
test "pipeline: lambda body call site counted" {
  // `\x. f x` — body is an AppExpr whose function position holds `f`,
  // which resolves to top-level (`x` is the lambda param, not `f`).
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet apply = \\x. f x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="1")
  inspect(pipe.callers_of("x").length(), content="0")
}

///|
test "pipeline: survives rt.gc() between queries" {
  // Regression test for the persistent-watch GC root. Without the
  // Watch anchoring the index Derived, rt.gc() would sweep the interior
  // facts/index cells (they have no other reachability path) and
  // subsequent reads would abort instead of returning empty arrays.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f x\nlet h = f x\n",
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
  // Regression test for the missing direct IdentToken guard. Source with an
  // incomplete `let = 1` (no identifier) used to emit Def { name: "" }
  // because token_text() returns "" on a missing token.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let = 1\nlet g = f x\n",
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
    "let f = 1\nlet g = f x\nlet h = f x\n",
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

// ─── New: scope-structure tests (pain point #2) ────────────────────────

///|
test "pipeline: lambda parameter shadows top-level def" {
  // Top-level `f`; then a lambda whose param is also named `f` and whose
  // body is `f x`. The inner `f` resolves to the lambda param, not to
  // the top-level. Tier 0 reported this as a caller of the top-level
  // `f`; scope structure excludes it.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet shadow = \\f. f x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  // Pain-point #2 assertion: the inner `f` is the lambda's own param,
  // not a call to the top-level `f`.
  inspect(pipe.callers_of("f").length(), content="0")
  // defs_of returns BOTH bindings (top-level + lambda param). The
  // scope field distinguishes them.
  inspect(pipe.defs_of("f").length(), content="2")
  pipe.dispose()
}

///|
test "pipeline: recursive lambda call resolves to top-level" {
  // `let f = \x. f x` — body's `f` is in the lambda's body, but the
  // lambda's only binding is `x`. So inner `f` resolves to the top-level
  // LetDef and IS counted as a caller. (This is the recursion case
  // Codex flagged as a check.)
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = \\x. f x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="1")
  inspect(pipe.callers_of("x").length(), content="0")
  pipe.dispose()
}

///|
test "pipeline: nested lambdas — innermost shadow wins" {
  // `\x. \x. x x` — outer `x` is shadowed by inner `x`. The two `x`s in
  // the body resolve to the INNER lambda's param. Neither is a
  // top-level caller.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let x = 1\nlet f = \\x. \\x. x x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("x").length(), content="0")
  // defs_of returns the top-level x + both lambda-param xs (= 3).
  inspect(pipe.defs_of("x").length(), content="3")
  pipe.dispose()
}

// ─── New: strict call-position filter tests (pain point #3) ────────────

///|
test "pipeline: strict call filter excludes data-position references" {
  // `let h = g f` — `g` is in AppExpr function position (a real call);
  // `f` is in argument position (passed as data). Tier 0 counted both
  // as callers; the strict filter excludes `f`.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = 2\nlet h = g f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("g").length(), content="1")
  inspect(pipe.callers_of("f").length(), content="0")
  pipe.dispose()
}

///|
test "pipeline: parenthesized callee still counts" {
  // `let h = (f) x` — `f` is wrapped in ParenExpr, which is the function
  // position of an AppExpr. ParenExpr is transparent for call-position
  // detection: `f` should still be recorded as a caller.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet h = (f) x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="1")
  pipe.dispose()
}

///|
test "pipeline: VarRef as bare body — not a call" {
  // `let g = f` (bare value, no application) — `f` is referenced as
  // data, not called. The strict filter excludes it.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet g = f\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="0")
  pipe.dispose()
}

// ─── New: let-paren param scope (multi-param desugaring) ───────────────

///|
test "pipeline: let-paren param shadows top-level def" {
  // `let id(x) = x y` — the let-param `x` binds `x` in the body.
  // The body's `x` resolves to the let-param (LambdaScope keyed by the
  // LetDef's range), NOT to the top-level `let x = ...`.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let x = 1\nlet id(x) = x y\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("x").length(), content="0")
  // defs_of returns top-level + let-param.
  inspect(pipe.defs_of("x").length(), content="2")
  pipe.dispose()
}

// ─── New: defensive edge cases ─────────────────────────────────────────

///|
test "pipeline: typed lambda param still shadows top-level def" {
  // `\x: Int. f x` — TypeAnnot sits between the param IdentToken and the
  // body. The param `x` must still bind the body's `x` (resolved_scope =
  // LambdaScope, excluded from callers_of("x")), and the body's `f x`
  // must still record `f` as a call.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(
    "let f = 1\nlet x = 2\nlet apply = \\x: Int. f x\n",
    @lambda.lambda_grammar,
    runtime=rt,
  )
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="1")
  inspect(pipe.callers_of("x").length(), content="0")
  pipe.dispose()
}

///|
test "pipeline: empty source returns no defs or callers" {
  // Empty source — extraction returns ([], []) and queries return empty
  // arrays without aborting.
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser("", @lambda.lambda_grammar, runtime=rt)
  let pipe = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  inspect(pipe.callers_of("f").length(), content="0")
  inspect(pipe.defs_of("f").length(), content="0")
  pipe.dispose()
}

///|
/// Helper: collect names of all Defs whose scope is NOT TopScope (i.e.
/// names that were bound as lambda params or let-params). Used by the
/// malformed-input regression tests below to assert that error recovery
/// does NOT leak body identifiers into the scope frame.
fn lambda_scope_def_names_of(src : String) -> Array[String] {
  let (defs, _) = extract_facts(parse_to_syntax(src))
  let out : Array[String] = []
  for d in defs {
    if !(d.scope is TopScope) {
      out.push(d.name)
    }
  }
  out
}

///|
test "extract_facts: malformed lambda missing param (\\ . f x)" {
  // ErrorToken placeholder at the param slot. `ident_after_lead` finds
  // LambdaToken, then sees an ErrorToken next (non-trivia, non-Ident) →
  // returns None. No body identifier leaks into the lambda's scope.
  let names = lambda_scope_def_names_of("let f = 1\nlet broken = \\ . f x\n")
  inspect(names.length(), content="0")
}

///|
test "extract_facts: malformed lambda no body (\\f)" {
  // Param `f` is consumed, but no DotToken / body follows. Recovery
  // determines what ends up in LambdaExpr's children; the param `f`
  // should still be the only LambdaScope binding.
  let names = lambda_scope_def_names_of("let broken = \\f\n")
  debug_inspect(names, content="[\"f\"]")
}

///|
test "extract_facts: malformed lambda no param or body (\\)" {
  // Lambda token alone — no param, no body. Param slot has no IdentToken;
  // ident_after_lead returns None; no binding.
  let names = lambda_scope_def_names_of("let broken = \\\n")
  inspect(names.length(), content="0")
}

///|
test "extract_facts: well-formed lambda still binds correctly under new extraction" {
  // Sanity check that the position-aware extractor matches a direct token
  // query on the happy path.
  let src = "let f = 1\nlet shadow = \\f. f\n"
  let names = lambda_scope_def_names_of(src)
  // Lambda's param `f` is the only non-TopScope binding.
  debug_inspect(names, content="[\"f\"]")
}

///|
test "ScopeId derives Hash (compile-time check)" {
  let m : @hashmap.HashMap[ScopeId, Int] = @hashmap.HashMap([])
  m.set(TopScope, 1)
  m.set(LambdaScope(0, 5), 2)
  // is-pattern checks avoid the deprecated Show-on-Option warning while
  // still verifying both presence and bound value.
  inspect(m.get(TopScope) is Some(1), content="true")
  inspect(m.get(LambdaScope(0, 5)) is Some(2), content="true")
  inspect(m.get(LambdaScope(1, 4)) is None, content="true")
}

///|
test "extract_facts wrapper: backward-compat 2-tuple shape preserved" {
  let src = "let g = \\x. x\n"
  let (defs, calls) = extract_facts(parse_to_syntax(src))
  // Same 2-tuple shape as before; per-element checks avoid Show-on-Array warning.
  inspect(defs.length(), content="2")
  inspect(defs[0].name, content="g")
  inspect(defs[1].name, content="x")
  inspect(calls.length(), content="1")
}

///|
/// Helper: build a one-shot CallersPipeline for snapshot tests of the new
/// public API. Modeled on the existing pipeline-construction helpers.
fn build_test_pipeline(source : String) -> CallersPipeline {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
}

///|
test "visible_from: TopScope bindings visible from TopScope" {
  let src = "let f = 1\nlet g = 2\n"
  let p = build_test_pipeline(src)
  inspect(p.visible_from(TopScope, "f"), content="true")
  inspect(p.visible_from(TopScope, "g"), content="true")
  inspect(p.visible_from(TopScope, "unbound"), content="false")
  p.dispose()
}

///|
test "visible_from: LambdaScope param visible inside its body" {
  let src = "let g = \\x. x\n"
  let p = build_test_pipeline(src)
  // Pull the lambda param's scope via defs_of:
  let xdefs = p.defs_of("x")
  inspect(xdefs.length(), content="1")
  let lambda_scope = xdefs[0].scope
  inspect(p.visible_from(lambda_scope, "x"), content="true")
  // x is NOT visible from TopScope.
  inspect(p.visible_from(TopScope, "x"), content="false")
  p.dispose()
}

///|
test "visible_from: TopScope binding visible from nested LambdaScope" {
  let src = "let f = 1\nlet g = \\x. f x\n"
  let p = build_test_pipeline(src)
  let xdefs = p.defs_of("x")
  let lambda_scope = xdefs[0].scope
  // f (TopScope) is visible inside the lambda.
  inspect(p.visible_from(lambda_scope, "f"), content="true")
  p.dispose()
}

///|
test "visible_from: shadowing not modeled — same name visible at both scopes" {
  // Top-level `f` plus a lambda whose param is also `f`. visible_from
  // says BOTH scopes have a binding named `f` — it does NOT distinguish
  // which one wins inside the lambda. That's the documented caveat: the
  // map says "some binding exists in this scope or an ancestor", not
  // "which binding resolves here."
  let src = "let f = 1\nlet g = \\f. f\n"
  let p = build_test_pipeline(src)
  let fdefs = p.defs_of("f")
  // 2 defs: top-level f and lambda-param f.
  inspect(fdefs.length(), content="2")
  // Find the lambda-param def by scope kind.
  let mut lambda_scope_opt : ScopeId? = None
  for d in fdefs {
    if d.scope is LambdaScope(_, _) {
      lambda_scope_opt = Some(d.scope)
    }
  }
  match lambda_scope_opt {
    Some(lambda_scope) => {
      // Both scopes report `f` as visible. The caveat is that no API call
      // distinguishes the inner-binding `f` from the inherited TopScope `f`.
      inspect(p.visible_from(lambda_scope, "f"), content="true")
      inspect(p.visible_from(TopScope, "f"), content="true")
    }
    None => abort("test setup: expected one LambdaScope def of f")
  }
  p.dispose()
}

///|
test "visible_from: fabricated unknown ScopeId returns false" {
  let src = "let f = 1\n"
  let p = build_test_pipeline(src)
  inspect(p.visible_from(LambdaScope(99999, 99999), "f"), content="false")
  p.dispose()
}

///|
test "visible_from: let-paren params visible in their body's scope" {
  let src = "let f(x, y) = x y\n"
  let p = build_test_pipeline(src)
  // Both x and y are defs in the same LambdaScope (let-paren frame).
  let xdefs = p.defs_of("x")
  inspect(xdefs.length(), content="1")
  let scope = xdefs[0].scope
  inspect(p.visible_from(scope, "x"), content="true")
  inspect(p.visible_from(scope, "y"), content="true")
  // f (the let-bound name) is visible at TopScope.
  inspect(p.visible_from(TopScope, "f"), content="true")
  p.dispose()
}

///|
test "pipeline: facts() returns defensive copies" {
  let src = "let f = \\x. x\nlet g = f y\n"
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(src, @lambda.lambda_grammar, runtime=rt)
  let pipeline = CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  let (defs, calls, enclosing) = pipeline.facts()
  // Returned arrays should contain the extracted facts.
  inspect(defs.length() >= 2, content="true")
  inspect(calls.length() >= 1, content="true")
  // Mutating returned arrays must NOT affect subsequent reads.
  defs.clear()
  calls.clear()
  enclosing.clear()
  let (defs2, calls2, _) = pipeline.facts()
  inspect(defs2.length() >= 2, content="true")
  inspect(calls2.length() >= 1, content="true")
  pipeline.dispose()
}
