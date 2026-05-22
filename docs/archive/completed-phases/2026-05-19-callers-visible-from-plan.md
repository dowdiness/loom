# Tier 1+ callers `visible_from` Implementation Plan

**Status:** Complete. Shipped in PR #129 (`3682e59`).

Completion note:

- PR #129 implemented the plan, including the follow-up Codex review fixes:
  `extract_facts_full` stayed package-private, `facts_observer` is primed at
  construction time to preserve the syntax-tree dependency before GC, and
  `build_visibility` documents the acyclic enclosing-graph precondition.

Decision record:

- [ADR 2026-05-22: Callers `visible_from` Memo Projection](../../decisions/2026-05-22-callers-visible-from-memo.md)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [2026-05-19-callers-visible-from.md](2026-05-19-callers-visible-from.md)

**Goal:** Ship `CallersPipeline::visible_from(scope, name) -> Bool` as a pure Memo on the existing Tier 1 foundation, plus a `facts_observer` GC anchor that fixes a latent pre-existing GC gap.

**Architecture:** Single `@incr.Scope` rooted at `parser.runtime()` with three Memos (`facts`, `callers_index`, `visibility`) and three Observers. No new Datalog cells. Extends `collect_in` to emit `Enclosing` edges; adds `build_visibility` as a pure function over `(defs, enclosing)`.

**Tech Stack:** MoonBit 0.9.2, `@incr.Scope`/`Memo`/`Observer`, `@hashmap.HashMap`, `@hashset.HashSet`, loom test runner (`moon test`).

**Worktree:** `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/loom-callers-escalation`. All file paths in this plan are relative to that worktree root.

**Baseline:** 591/599 lambda tests passing (8 pre-existing v0.9.2 snapshot-render failures unrelated to callers); `examples/lambda/src/callers/` 25/25 ✓ pre-change.

**Command convention:** Bash snippets show plain `moon ...` invocations. When executed through Claude Code, the RTK hook transparently rewrites them to `rtk moon ...` for token savings (see `~/.claude/RTK.md`). Manual executors should prefix `rtk` themselves: e.g., `rtk moon test`. Either form works; choose based on your environment.

---

## File Structure

Changed files:

| File | Responsibility | Net change |
|---|---|---|
| `examples/lambda/src/callers/callers.mbt` | Public API + extraction + pipeline | ~+90 LOC, ~-15 deleted (`rt` field + redundancies) |
| `examples/lambda/src/callers/callers_test.mbt` | Tests | ~+50 LOC, no deletions |
| `examples/lambda/src/callers/pkg.generated.mbti` | `moon info`-generated interface | auto |

Single-package change; one PR; Medium band.

---

### Task 0: Commit the spec + plan + index update

**Files:**
- Add: `docs/plans/2026-05-19-callers-visible-from.md` (spec, untracked)
- Add: `docs/plans/2026-05-19-callers-visible-from-plan.md` (this plan, untracked)
- Modify: `docs/README.md` (Active Plans entry)

- [ ] **Step 0.1: Verify the three docs files exist and `docs/README.md` is modified**

  ```
  git status -s
  ```

  Expected:
  ```
   M docs/README.md
  ?? docs/plans/
  ```

- [ ] **Step 0.2: Commit the docs**

  ```bash
  git add docs/plans/2026-05-19-callers-visible-from.md \
          docs/plans/2026-05-19-callers-visible-from-plan.md \
          docs/README.md
  git commit -m "docs(plans): spec + implementation plan for visible_from

  Adds the design spec and a TDD-structured implementation plan for the
  Tier 1+ callers projection (visible_from). Decision: ship as Memo, not
  Datalog — the engine's monotonic-relation constraint makes Datalog give
  negative value for this consumer (rename + conflict detection). Full
  reasoning in the spec §7 and the brainstorming history. No new ADR.

  Indexed in docs/README.md under Active Plans."
  ```

  This commit is independent of any source-code change — if implementation
  iterates, the design stays auditable in git.

- [ ] **Step 0.3: Verify the commit landed**

  ```
  git log -1 --stat
  ```

  Expected: three files changed (docs/README.md, docs/plans/2026-05-19-callers-visible-from.md, docs/plans/2026-05-19-callers-visible-from-plan.md).

---

### Task 1: Add `Hash` derive to `ScopeId`

**Files:**
- Modify: `examples/lambda/src/callers/callers.mbt:40-43`

- [ ] **Step 1.1: Add a failing test that constructs `HashMap[ScopeId, _]`**

  Append to `examples/lambda/src/callers/callers_test.mbt`:

  ```moonbit
  ///|
  test "ScopeId derives Hash (compile-time check)" {
    let m : @hashmap.HashMap[ScopeId, Int] = @hashmap.HashMap([])
    m.set(TopScope, 1)
    m.set(LambdaScope(0, 5), 2)
    inspect(m.get(TopScope), content="Some(1)")
    inspect(m.get(LambdaScope(0, 5)), content="Some(2)")
    inspect(m.get(LambdaScope(1, 4)), content="None")
  }
  ```

- [ ] **Step 1.2: Run the test to verify it fails to compile**

  Run from the worktree's lambda dir:

  ```
  cd examples/lambda && moon check -p dowdiness/lambda/callers 2>&1 | tail -20
  ```

  Expected: a compile error noting that `ScopeId` does not implement `Hash` (or similar trait-bound error referencing the `HashMap[ScopeId, …]` annotation).

- [ ] **Step 1.3: Add `Hash` to the derive list**

  In `callers.mbt`, change:

  ```moonbit
  pub(all) enum ScopeId {
    TopScope
    LambdaScope(Int, Int)
  } derive(Eq, Debug)
  ```

  to:

  ```moonbit
  pub(all) enum ScopeId {
    TopScope
    LambdaScope(Int, Int)
  } derive(Eq, Hash, Debug)
  ```

- [ ] **Step 1.4: Verify the test passes and existing 25 callers tests still pass**

  ```
  cd examples/lambda && moon test -p dowdiness/lambda/callers 2>&1 | tail -5
  ```

  Expected: `Total tests: 26, passed: 26, failed: 0.`

- [ ] **Step 1.5: Commit**

  ```bash
  git add examples/lambda/src/callers/callers.mbt examples/lambda/src/callers/callers_test.mbt
  git commit -m "feat(lambda/callers): derive Hash on ScopeId for visibility map keying"
  ```

---

### Task 2: Implement `extract_facts_full` with Enclosing edge emission

**Files:**
- Modify: `examples/lambda/src/callers/callers.mbt:182-287` (`collect_in` and `extract_facts`)

- [ ] **Step 2.1: Add failing tests for Enclosing-edge extraction**

  Append to `callers_test.mbt`:

  ```moonbit
  ///|
  test "extract_facts_full: emits TopScope edge for outermost LambdaExpr" {
    let src = "let g = \\x. x\n"
    let (_, _, enclosing) = extract_facts_full(parse_to_syntax(src))
    // Exactly one LambdaScope, with TopScope as its parent.
    inspect(enclosing.length(), content="1")
    let (child, parent) = enclosing[0]
    inspect(parent is TopScope, content="true")
    inspect(child is LambdaScope(_, _), content="true")
  }

  ///|
  test "extract_facts_full: nested LambdaExpr emits chain of edges" {
    let src = "let g = \\x. \\y. x y\n"
    let (_, _, enclosing) = extract_facts_full(parse_to_syntax(src))
    // Outer lambda -> TopScope, inner lambda -> outer lambda.
    inspect(enclosing.length(), content="2")
    // Outer (LambdaExpr starting before inner) edge to TopScope:
    let outer_edge = enclosing[0]
    inspect(outer_edge.1 is TopScope, content="true")
    // Inner edge's parent is the outer LambdaScope (not TopScope).
    let inner_edge = enclosing[1]
    inspect(inner_edge.1 is TopScope, content="false")
    inspect(inner_edge.1 is LambdaScope(_, _), content="true")
  }

  ///|
  test "extract_facts_full: let-paren params emit Enclosing edge" {
    let src = "let f(x, y) = x y\n"
    let (_, _, enclosing) = extract_facts_full(parse_to_syntax(src))
    inspect(enclosing.length(), content="1")
    let (_, parent) = enclosing[0]
    inspect(parent is TopScope, content="true")
  }

  ///|
  test "extract_facts wrapper: backward-compat 2-tuple shape preserved" {
    let src = "let g = \\x. x\n"
    let (defs, calls) = extract_facts(parse_to_syntax(src))
    // Same 2-tuple shape as before; values match the existing test at line ~30
    let def_names = defs.map(fn(d) { d.name })
    inspect(def_names, content="[g, x]")
    inspect(calls.length(), content="1")
  }
  ```

- [ ] **Step 2.2: Run tests to verify they fail (`extract_facts_full` undefined)**

  ```
  cd examples/lambda && moon test -p dowdiness/lambda/callers 2>&1 | tail -10
  ```

  Expected: compile error — `extract_facts_full` not defined.

- [ ] **Step 2.3: Extend `collect_in` signature to take an `enclosing` accumulator**

  In `callers.mbt`, change the signature of `collect_in` from:

  ```moonbit
  fn collect_in(
    node : @seam.SyntaxNode,
    defs : Array[Def],
    calls : Array[Call],
    stack : Array[Frame],
  ) -> Unit {
  ```

  to:

  ```moonbit
  fn collect_in(
    node : @seam.SyntaxNode,
    defs : Array[Def],
    calls : Array[Call],
    enclosing : Array[(ScopeId, ScopeId)],
    stack : Array[Frame],
  ) -> Unit {
  ```

- [ ] **Step 2.4: Emit Enclosing edge before LambdaExpr frame push**

  In `collect_in`, inside the `@syntax.LambdaExpr` arm, change:

  ```moonbit
        stack.push({ id: frame_id, names })
        for child in node.children() {
          collect_in(child, defs, calls, stack)
        }
  ```

  to:

  ```moonbit
        if stack.length() > 0 {
          enclosing.push((frame_id, stack[stack.length() - 1].id))
        }
        stack.push({ id: frame_id, names })
        for child in node.children() {
          collect_in(child, defs, calls, enclosing, stack)
        }
  ```

  (Note: the recursive `collect_in` call now passes `enclosing` as well.)

- [ ] **Step 2.5: Emit Enclosing edge before LetDef-with-ParamList frame push**

  In `collect_in`, inside the `@syntax.LetDef` arm, change:

  ```moonbit
            stack.push({ id: frame_id, names })
            pushed = true
          } else {
            collect_in(child, defs, calls, stack)
          }
  ```

  to:

  ```moonbit
            if stack.length() > 0 {
              enclosing.push((frame_id, stack[stack.length() - 1].id))
            }
            stack.push({ id: frame_id, names })
            pushed = true
          } else {
            collect_in(child, defs, calls, enclosing, stack)
          }
  ```

- [ ] **Step 2.6: Update the catch-all recursive arm**

  In `collect_in`, change the `_ =>` arm at the bottom from:

  ```moonbit
      _ =>
        for child in node.children() {
          collect_in(child, defs, calls, stack)
        }
  ```

  to:

  ```moonbit
      _ =>
        for child in node.children() {
          collect_in(child, defs, calls, enclosing, stack)
        }
  ```

- [ ] **Step 2.7: Add `extract_facts_full` and reshape `extract_facts` to wrapper**

  Replace the existing `extract_facts` (around `callers.mbt:281-287`) with:

  ```moonbit
  ///|
  /// Pure extraction including Enclosing edges. Used by the pipeline's
  /// `facts` Memo. The returned `enclosing` array carries `(child, parent)`
  /// tuples for every LambdaScope frame pushed during the walk. TopScope is
  /// never a child of an edge (it's the implicit root of every chain).
  pub fn extract_facts_full(
    root : @seam.SyntaxNode,
  ) -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]) {
    let defs : Array[Def] = []
    let calls : Array[Call] = []
    let enclosing : Array[(ScopeId, ScopeId)] = []
    let stack : Array[Frame] = [{ id: TopScope, names: [] }]
    collect_in(root, defs, calls, enclosing, stack)
    (defs, calls, enclosing)
  }

  ///|
  /// Backward-compatible 2-tuple shape: defs and calls only. The 23
  /// pre-existing tests at this signature continue to compile unchanged.
  pub fn extract_facts(root : @seam.SyntaxNode) -> (Array[Def], Array[Call]) {
    let (defs, calls, _enclosing) = extract_facts_full(root)
    (defs, calls)
  }
  ```

- [ ] **Step 2.8: Run all callers tests and verify they pass**

  ```
  cd examples/lambda && moon test -p dowdiness/lambda/callers 2>&1 | tail -5
  ```

  Expected: `Total tests: 30, passed: 30, failed: 0.` (26 from Task 1 + 4 new in Task 2).

- [ ] **Step 2.9: Commit**

  ```bash
  git add examples/lambda/src/callers/callers.mbt examples/lambda/src/callers/callers_test.mbt
  git commit -m "feat(lambda/callers): emit Enclosing edges during extraction

  Adds extract_facts_full returning (defs, calls, enclosing) for the
  visibility build to consume. extract_facts kept as a 2-tuple wrapper
  so the 23 pre-existing test call sites compile unchanged. The edge
  set has (child_scope, parent_scope) tuples emitted at each LambdaExpr
  and LetDef-with-ParamList frame push. TopScope is implicitly the root
  of every chain."
  ```

---

### Task 3: Implement `build_visibility`

**Files:**
- Modify: `examples/lambda/src/callers/moon.pkg` (add `hashset` import)
- Modify: `examples/lambda/src/callers/callers.mbt` (insert new function before the `CallersPipeline` struct, around line 305)

- [ ] **Step 3.0: Add the `hashset` import to `moon.pkg`**

  `build_visibility` uses `@hashset.HashSet[String]` for its memoization
  table and per-scope name accumulator. The package currently imports only
  `hashmap` and `debug`, so this must land before the implementation
  compiles. Modify `examples/lambda/src/callers/moon.pkg` from:

  ```
  import {
    "dowdiness/seam" @seam,
    "dowdiness/lambda/syntax" @syntax,
    "dowdiness/incr" @incr,
    "moonbitlang/core/hashmap",
    "moonbitlang/core/debug",
  }
  ```

  to:

  ```
  import {
    "dowdiness/seam" @seam,
    "dowdiness/lambda/syntax" @syntax,
    "dowdiness/incr" @incr,
    "moonbitlang/core/hashmap",
    "moonbitlang/core/hashset",
    "moonbitlang/core/debug",
  }
  ```

- [ ] **Step 3.1: Add failing tests for `build_visibility`**

  Append to `callers_test.mbt`:

  ```moonbit
  ///|
  test "build_visibility: TopScope-only defs are visible from TopScope" {
    let defs : Array[Def] = [
      { name: "f", scope: TopScope, start: 0, end: 9 },
      { name: "g", scope: TopScope, start: 10, end: 19 },
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
      { name: "f", scope: TopScope, start: 0, end: 9 },
      { name: "x", scope: inner, start: 10, end: 20 },
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
      { name: "f", scope: TopScope, start: 0, end: 4 },
      { name: "x", scope: outer, start: 5, end: 30 },
      { name: "y", scope: inner, start: 15, end: 25 },
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
    let defs : Array[Def] = [{ name: "f", scope: TopScope, start: 0, end: 9 }]
    let enclosing : Array[(ScopeId, ScopeId)] = [(empty_inner, TopScope)]
    let v = build_visibility(defs, enclosing)
    inspect(v.get((empty_inner, "f")) is Some(_), content="true")
    inspect(v.get((empty_inner, "anything_else")) is Some(_), content="false")
  }
  ```

- [ ] **Step 3.2: Run tests to verify they fail (`build_visibility` undefined)**

  ```
  cd examples/lambda && moon test -p dowdiness/lambda/callers 2>&1 | tail -10
  ```

  Expected: compile error — `build_visibility` not defined.

- [ ] **Step 3.3: Implement `visible_names_at` helper**

  Insert into `callers.mbt`, immediately before the `CallersPipeline` struct (around line 305):

  ```moonbit
  ///|
  /// Compute the full set of names visible at scope `s`. Walks the parent
  /// chain upward, unioning each ancestor's own bindings. Memoized via
  /// `memo` to avoid quadratic re-walks along shared chains.
  fn visible_names_at(
    s : ScopeId,
    parent : @hashmap.HashMap[ScopeId, ScopeId],
    own : @hashmap.HashMap[ScopeId, Array[String]],
    memo : @hashmap.HashMap[ScopeId, @hashset.HashSet[String]],
  ) -> @hashset.HashSet[String] {
    match memo.get(s) {
      Some(set) => set
      None => {
        let result : @hashset.HashSet[String] = @hashset.HashSet([])
        match own.get(s) {
          Some(arr) =>
            for n in arr {
              result.add(n)
            }
          None => ()
        }
        match parent.get(s) {
          Some(p) => {
            let inherited = visible_names_at(p, parent, own, memo)
            for n in inherited {
              result.add(n)
            }
          }
          None => () // root or unparented
        }
        memo.set(s, result)
        result
      }
    }
  }
  ```

- [ ] **Step 3.4: Implement `build_visibility`**

  Immediately after `visible_names_at`, add:

  ```moonbit
  ///|
  /// Build the (scope, name) → Unit visibility map from extracted defs +
  /// enclosing edges. Membership in the map means "binding `name` exists
  /// in `scope` or any enclosing scope." Does NOT model shadowing.
  pub fn build_visibility(
    defs : Array[Def],
    enclosing : Array[(ScopeId, ScopeId)],
  ) -> @hashmap.HashMap[(ScopeId, String), Unit] {
    // 1. Collect every scope mentioned in defs OR enclosing, plus TopScope.
    let scopes : @hashset.HashSet[ScopeId] = @hashset.HashSet([])
    scopes.add(TopScope)
    for d in defs {
      scopes.add(d.scope)
    }
    for edge in enclosing {
      scopes.add(edge.0)
      scopes.add(edge.1)
    }
    // 2. parent[child] = parent_scope. First edge wins (defensive against
    //    malformed input that emits duplicate parents).
    let parent : @hashmap.HashMap[ScopeId, ScopeId] = @hashmap.HashMap([])
    for edge in enclosing {
      match parent.get(edge.0) {
        None => parent.set(edge.0, edge.1)
        Some(_) => ()
      }
    }
    // 3. own[scope] = [name, ...] for bindings introduced by that scope.
    let own : @hashmap.HashMap[ScopeId, Array[String]] = @hashmap.HashMap([])
    for d in defs {
      match own.get(d.scope) {
        Some(arr) => arr.push(d.name)
        None => own.set(d.scope, [d.name])
      }
    }
    // 4. For each scope, materialize its visibility name set (memoized).
    let memo : @hashmap.HashMap[ScopeId, @hashset.HashSet[String]] = @hashmap.HashMap(
      [],
    )
    // 5. Flatten into (scope, name) → Unit.
    let result : @hashmap.HashMap[(ScopeId, String), Unit] = @hashmap.HashMap([])
    for s in scopes {
      let names = visible_names_at(s, parent, own, memo)
      for n in names {
        result.set((s, n), ())
      }
    }
    result
  }
  ```

- [ ] **Step 3.5: Run all callers tests and verify they pass**

  ```
  cd examples/lambda && moon test -p dowdiness/lambda/callers 2>&1 | tail -5
  ```

  Expected: `Total tests: 34, passed: 34, failed: 0.` (30 from Tasks 1-2 + 4 new).

- [ ] **Step 3.6: Commit**

  ```bash
  git add examples/lambda/src/callers/callers.mbt examples/lambda/src/callers/callers_test.mbt
  git commit -m "feat(lambda/callers): build_visibility flat (scope,name) map

  Pure function over (defs, enclosing). Memoized per-scope walk up the
  parent chain. Returns HashMap[(ScopeId, String), Unit] because
  HashMap[ScopeId, HashSet[String]] can't be a Memo value
  (moonbitlang/core HashSet has no Eq impl; Scope::memo requires T:Eq).
  Does NOT model shadowing — documented in the spec section 6, invariant 1."
  ```

---

### Task 4: Reshape `CallersPipeline` to add `visibility_observer` and `facts_observer`

**Files:**
- Modify: `examples/lambda/src/callers/callers.mbt:317-406`

- [ ] **Step 4.1: Add failing tests for `visible_from` and the reshaped pipeline**

  Append to `callers_test.mbt`:

  ```moonbit
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
  test "visible_from: malformed lambda still sees enclosing bindings" {
    // `\. body` — frame pushed without a Def (ident_after_lead returns
    // None at callers.mbt:204). The Enclosing edge is still emitted, so
    // the (empty) lambda scope inherits the top-level binding `f`.
    let src = "let f = 1\nlet g = \\. f\n"
    let p = build_test_pipeline(src)
    // Identify the malformed lambda's scope from the raw enclosing edges.
    let (_, _, enclosing) = extract_facts_full(parse_to_syntax(src))
    inspect(enclosing.length(), content="1")
    let malformed_scope = enclosing[0].0
    inspect(malformed_scope is LambdaScope(_, _), content="true")
    // The actual claim: f IS visible from the empty lambda scope.
    inspect(p.visible_from(malformed_scope, "f"), content="true")
    inspect(p.visible_from(malformed_scope, "not_a_real_name"), content="false")
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
  ```

- [ ] **Step 4.2: Run tests to verify they fail (compile error: `visible_from` undefined)**

  ```
  cd examples/lambda && moon test -p dowdiness/lambda/callers 2>&1 | tail -10
  ```

  Expected: compile error — `visible_from` not a method on `CallersPipeline`.

- [ ] **Step 4.3: Reshape the `CallersPipeline` struct**

  In `callers.mbt`, replace the struct definition (currently at lines ~317-322):

  ```moonbit
  pub struct CallersPipeline {
    priv rt : @incr.Runtime
    priv scope : @incr.Scope
    priv observer : @incr.Observer[@hashmap.HashMap[String, Array[Call]]]
    priv facts : @incr.Memo[(Array[Def], Array[Call])]
  }
  ```

  with:

  ```moonbit
  pub struct CallersPipeline {
    priv scope : @incr.Scope
    priv facts_observer : @incr.Observer[
      (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]),
    ]
    priv callers_observer : @incr.Observer[@hashmap.HashMap[String, Array[Call]]]
    priv visibility_observer : @incr.Observer[
      @hashmap.HashMap[(ScopeId, String), Unit],
    ]
  }
  ```

  Note: `rt` field is removed; `facts` (the bare Memo) is removed and replaced
  by `facts_observer` (the explicit GC anchor).

- [ ] **Step 4.4: Rewrite the constructor `CallersPipeline::CallersPipeline`**

  Replace the existing constructor body (currently lines ~336-363) with:

  ```moonbit
  pub fn CallersPipeline::CallersPipeline(
    rt : @incr.Runtime,
    syntax : @incr.Memo[@seam.SyntaxNode],
  ) -> CallersPipeline {
    let scope = @incr.Scope::new(rt)
    let facts = scope.memo(
      fn() { extract_facts_full(syntax.get()) },
      label="callers_facts",
    )
    let callers_index = scope.memo(
      fn() {
        let (_, calls, _) = facts.get()
        let buckets : @hashmap.HashMap[String, Array[Call]] = @hashmap.HashMap([])
        for c in calls {
          if c.is_call_position && c.resolved_scope == TopScope {
            match buckets.get(c.callee) {
              Some(bucket) => bucket.push(c)
              None => buckets.set(c.callee, [c])
            }
          }
        }
        buckets
      },
      label="callers_index",
    )
    let visibility = scope.memo(
      fn() {
        let (defs, _, enclosing) = facts.get()
        build_visibility(defs, enclosing)
      },
      label="callers_visibility",
    )
    let facts_observer = scope.add_observer(facts.observe())
    let callers_observer = scope.add_observer(callers_index.observe())
    let visibility_observer = scope.add_observer(visibility.observe())
    { scope, facts_observer, callers_observer, visibility_observer }
  }
  ```

  Key differences from today: three Memos labelled `callers_facts`,
  `callers_index`, `callers_visibility`. Three Observers, each registered
  via `scope.add_observer(memo.observe())` per the incr skill's GC anchor
  template.

- [ ] **Step 4.5: Update `callers_of` to use `callers_observer`**

  Replace the existing `callers_of` method:

  ```moonbit
  pub fn CallersPipeline::callers_of(
    self : CallersPipeline,
    name : String,
  ) -> Array[Call] {
    match self.callers_observer.get().get(name) {
      Some(bucket) => bucket.copy()
      None => []
    }
  }
  ```

- [ ] **Step 4.6: Update `defs_of` to read via `facts_observer`**

  Replace the existing `defs_of`:

  ```moonbit
  pub fn CallersPipeline::defs_of(
    self : CallersPipeline,
    name : String,
  ) -> Array[Def] {
    let (defs, _, _) = self.facts_observer.get()
    let result : Array[Def] = []
    for d in defs {
      if d.name == name {
        result.push(d)
      }
    }
    result
  }
  ```

- [ ] **Step 4.7: Add the new `visible_from` method**

  Append to `callers.mbt`, after `defs_of`:

  ```moonbit
  ///|
  /// True iff a binding named `name` is visible from `scope` — meaning it
  /// exists in `scope` itself or in any enclosing scope. Does NOT model
  /// shadowing (cannot answer "which binding wins"). Consumer-facing for
  /// rename + conflict detection. Returns false for unknown ScopeIds.
  pub fn CallersPipeline::visible_from(
    self : CallersPipeline,
    scope : ScopeId,
    name : String,
  ) -> Bool {
    self.visibility_observer.get().get((scope, name)) is Some(_)
  }
  ```

- [ ] **Step 4.8: Keep `dispose` unchanged but verify it still compiles**

  The existing `dispose` body is `self.scope.dispose()` — it doesn't
  reference any of the removed fields, so no change needed. Confirm
  by reading the file:

  ```
  grep -n "fn CallersPipeline::dispose" examples/lambda/src/callers/callers.mbt
  ```

  Expected: one match. Body should still be `self.scope.dispose()`.

- [ ] **Step 4.9: Run all callers tests and verify they pass**

  ```
  cd examples/lambda && moon test -p dowdiness/lambda/callers 2>&1 | tail -5
  ```

  Expected: `Total tests: 41, passed: 41, failed: 0.` (34 from Tasks 1-3 + 7 new).

- [ ] **Step 4.10: Verify the full lambda test suite picks up the new tests without regressing the baseline**

  ```
  cd examples/lambda && moon test 2>&1 | tail -3
  ```

  Expected: `Total tests: 615, passed: 607, failed: 8.` (599 baseline + 16 new across Tasks 1–4 = 615 total; 591 + 16 = 607 passing; 8 pre-existing failures unchanged). The 8 failures must be the same set the worktree started with (in `cst_tree_test.mbt` and `views_test.mbt`), NOT in `callers/`.

  Sanity-check that the failures are pre-existing:

  ```
  cd examples/lambda && moon test 2>&1 | grep "failed" | grep -v "passed:" | head -10
  ```

  Expected: failures only in files NOT under `src/callers/`.

- [ ] **Step 4.11: Commit**

  ```bash
  git add examples/lambda/src/callers/callers.mbt examples/lambda/src/callers/callers_test.mbt
  git commit -m "feat(lambda/callers): add visible_from + facts_observer GC anchor

  - Adds CallersPipeline::visible_from(scope, name) -> Bool for rename
    + conflict detection consumers.
  - Adds visibility_memo + visibility_observer to the pipeline.
  - Adds explicit facts_observer to anchor facts_memo (was vulnerable
    to rt.gc() before the first index read in the pre-existing
    pipeline shape — see callers.mbt:361 in the prior revision).
  - Drops the unused rt field from CallersPipeline.
  - 7 new visible_from tests covering TopScope, nested chains,
    shadowing-not-modeled, unknown ScopeIds, malformed lambdas, and
    let-paren params."
  ```

---

### Task 5: Regenerate `.mbti` and format

**Files:**
- Modify: `examples/lambda/src/callers/pkg.generated.mbti` (auto-regenerated)
- Modify: any file `moon fmt` chooses to touch

- [ ] **Step 5.1: Regenerate interface signatures**

  ```
  cd examples/lambda && moon info
  ```

  Expected: no errors. The `.mbti` file is rewritten in place.

- [ ] **Step 5.2: Inspect the `.mbti` diff**

  ```
  git diff examples/lambda/src/callers/pkg.generated.mbti
  ```

  Expected diff highlights:
  - `enum ScopeId` line gains `Hash` in its derive set.
  - New `pub fn extract_facts_full` signature.
  - New `pub fn build_visibility` signature.
  - New `pub fn CallersPipeline::visible_from` signature.
  - `extract_facts` signature unchanged.
  - `CallersPipeline::callers_of` / `defs_of` / `dispose` signatures unchanged.
  - `CallersPipeline::CallersPipeline` signature unchanged.

  If any signature you didn't expect to change is in the diff, **stop and investigate** before committing. The `.mbti` is the canonical public API surface.

- [ ] **Step 5.3: Run formatter**

  ```
  cd examples/lambda && moon fmt
  git diff --stat
  ```

  Expected: only the files Task 1-4 already modified appear in the stat,
  possibly with small whitespace changes.

- [ ] **Step 5.4: Run wall-warnings check (matches CI's `moon check -w @a`)**

  ```
  cd examples/lambda && moon check -w @a -p dowdiness/lambda/callers 2>&1 | tail -10
  ```

  Expected: `Finished. moon: ran N tasks, now up to date (0 warnings, 0 errors)`.

  If warnings appear in `src/callers/`, address them inline. If warnings
  appear only in OTHER files (pre-existing deprecation noise), they're
  not in scope for this PR — the `-p dowdiness/lambda/callers` flag scopes
  to the callers package so cross-file noise should not be reported.

- [ ] **Step 5.5: Commit**

  ```bash
  git add examples/lambda/src/callers/pkg.generated.mbti
  git commit -m "chore(lambda/callers): regenerate .mbti for visible_from + extract_facts_full"
  ```

---

### Task 6: Codex post-implementation review

**Files:** none — this task is a review checkpoint.

- [ ] **Step 6.1: Capture the full diff for Codex**

  ```
  git diff main -- examples/lambda/src/callers/ > /tmp/callers-visible-from.diff
  wc -l /tmp/callers-visible-from.diff
  ```

  Expected: ~200-250 lines of diff (signed: additions + context).

- [ ] **Step 6.2: Send the diff to Codex via `mcp__codex__codex-reply`**

  Continue on the same thread used during brainstorm (threadId from the
  prior session — if the session has rotated, start a new thread and
  include the spec doc reference in the prompt).

  Prompt skeleton (fill in the actual diff content):

  > "Post-implementation review for the `visible_from` PR specified in
  > `docs/plans/2026-05-19-callers-visible-from.md`. Diff below. Please
  > evaluate: (1) does the implementation match the spec's invariants
  > (especially §6 — Visible doesn't model shadowing, callers_of preserves
  > Tier 1, etc.); (2) are there any Memo body / GC anchor issues you'd
  > flag; (3) is the `visible_names_at` memoization correct (no
  > write-through of partially-built sets); (4) any test gaps."

- [ ] **Step 6.3: Address Codex feedback inline**

  For each finding:
  - If it's a clear bug, fix in the same commit/branch.
  - If it's a stylistic/scope-creep flag, note in the PR description
    rather than fixing in this PR.
  - If Codex disagrees with a spec-level decision (e.g., "shadowing should
    be modeled"), refer to the spec doc and the brainstorming history;
    don't unilaterally rescope.

- [ ] **Step 6.4: Commit any fixes from Codex review**

  ```bash
  git add examples/lambda/src/callers/
  git commit -m "fix(lambda/callers): address Codex review feedback

  <one-line summary of what was fixed>"
  ```

  Skip this step if Codex had no actionable findings; instead, just
  document the review pass in the PR description.

---

### Task 7: Final verification + push branch

**Files:** none — verification gate.

- [ ] **Step 7.1: Full lambda test suite**

  ```
  cd examples/lambda && moon test 2>&1 | tail -3
  ```

  Expected: `Total tests: 615, passed: 607, failed: 8.` (8 pre-existing
  v0.9.2 snapshot drift, identical set to the baseline).

- [ ] **Step 7.2: Full wall-warnings check at the module level**

  ```
  cd examples/lambda && moon check -w @a 2>&1 | tail -3
  ```

  Expected: existing warnings count unchanged from the worktree baseline
  (51 warnings, 0 errors). No new warnings introduced by this PR.

- [ ] **Step 7.3: Verify branch is on `feat/lambda-callers-escalation`**

  ```
  git -C /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/loom-callers-escalation branch --show-current
  ```

  Expected: `feat/lambda-callers-escalation`.

- [ ] **Step 7.4: Push the branch**

  ```bash
  git -C /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/loom-callers-escalation push -u origin feat/lambda-callers-escalation
  ```

---

### Task 8: Open the PR

**Files:** none — administrative.

- [ ] **Step 8.1: Create PR via `gh`**

  ```bash
  gh pr create --title "feat(lambda/callers): Tier 1+ visible_from projection (Memo, not Datalog)" --body "$(cat <<'EOF'
  ## Summary

  Ships `CallersPipeline::visible_from(scope, name) -> Bool` for rename + conflict-detection consumers, plus a `facts_observer` GC anchor that fixes a latent pre-existing GC gap.

  Implementation: pure Memo over a `(scope, name) -> Unit` visibility map, built from extended extraction (`extract_facts_full` now returns Enclosing edges alongside defs/calls). No Datalog cells were introduced.

  ## Why not Datalog

  The Tier 1+ trigger fired (second consumer of `ScopeId` in scope: rename + conflict detection). The schema-shape question went through two rounds of Codex review and concluded that Datalog gives **negative** value for this consumer given today's engine. The `@incr` Datalog relations are insert-only across revisions (no retract API; `current` accumulates monotonically — verified at `incr/cells/internal/kernel/fixpoint.mbt:39-46`), so a `Visible` Datalog relation would leak stale facts on every rename / delete edit. A pure Memo recomputes from scratch each revision: no leak, same per-revision algorithmic complexity, less infrastructure.

  Full reasoning + the engine-improvement timeline is in [`docs/plans/2026-05-19-callers-visible-from.md`](docs/plans/2026-05-19-callers-visible-from.md) §3 and §7.

  ## Changes
  - `examples/lambda/src/callers/callers.mbt`: `ScopeId derive(Hash)`; `collect_in` emits Enclosing edges; new `extract_facts_full` (3-tuple) with `extract_facts` kept as a 2-tuple wrapper for back-compat; new `build_visibility` pure function; pipeline gains `facts_observer` + `visibility_observer`; new `visible_from` method; `defs_of` reshape to use `facts_observer`; drops the unused `rt` field.
  - `examples/lambda/src/callers/callers_test.mbt`: 16 new tests (1 Hash compile-check, 4 enclosing-edge, 4 build_visibility, 7 visible_from).
  - `docs/plans/2026-05-19-callers-visible-from.md`: design spec.
  - `docs/plans/2026-05-19-callers-visible-from-plan.md`: implementation plan.
  - `docs/README.md`: index update.

  ## Test plan
  - [ ] `cd examples/lambda && moon test -p dowdiness/lambda/callers` → 41/41 pass
  - [ ] `cd examples/lambda && moon test` → 607/615 pass (8 failures are pre-existing v0.9.2 snapshot drift in cst_tree_test.mbt / views_test.mbt, identical to main)
  - [ ] `cd examples/lambda && moon check -w @a -p dowdiness/lambda/callers` → 0 warnings, 0 errors
  - [ ] `.mbti` diff inspected: only `ScopeId` Hash derive + 3 new public symbols + 1 new method appear

  ## Related
  - Spec: [docs/plans/2026-05-19-callers-visible-from.md](docs/plans/2026-05-19-callers-visible-from.md)
  - Plan: [docs/plans/2026-05-19-callers-visible-from-plan.md](docs/plans/2026-05-19-callers-visible-from-plan.md)
  - Tier 0: loom#124 (squash ea4d849)
  - Tier 1: loom#126 (squash 4604409)

  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  EOF
  )"
  ```

  Note: the `🤖 Generated` line is the project's standard PR footer per the brainstorming/handoff workflow.

- [ ] **Step 8.2: Verify CI is queued, and DO NOT merge until all checks are green**

  Per CLAUDE.md: `NEVER merge PRs until CI is fully green.` Run
  `gh pr checks <PR_NUMBER>` and show the raw output to the user before
  any merge. Skipped checks are NOT passing.

---

## Out of scope (do not touch in this PR)

- `incr/cells/` engine changes (Family A, retract, etc.) — separate work in `dowdiness/incr`.
- ID stability for `Def`/`Call`/`LambdaScope` (pain point #1) — separate concern, deferred.
- Migrating `views.mbt:39-41` `LambdaExprView::param()` to `ident_after_lead` — gated on a third consumer per the loom skill.
- canopy wiring of the new projection.
- A benchmark for `visible_from`. Honest perf framing is "same as Memo recompute per edit"; bench when a consumer surfaces a hot query path.

## Resolution path forward

Spec doc → this plan → implementation (Tasks 1–7) → Codex post-impl review (Task 6) → PR (Task 8) → CI green → merge to `loom/main`. Rename + conflict-detection consumer is a follow-up PR consuming `visible_from`. Datalog re-escalation is gated on engine retract / Family A landing in `dowdiness/incr`, independently of this PR.
