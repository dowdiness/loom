# Rename + conflict-detection consumer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [2026-05-19-rename-consumer-design.md](2026-05-19-rename-consumer-design.md)

**Goal:** Ship `plan_rename(pipeline, source, syntax, offset, new_name) -> RenamePlan` in a new `examples/lambda/src/rename/` package, plus one accessor (`CallersPipeline::facts`) on the callers pipeline. Editor consumers use the RenamePlan's edits + diagnostics to drive rename UI.

**Architecture:** Single-pipeline, single-revision computation. Reads cached facts from `CallersPipeline::facts()`; performs target lookup via identifier-token range; computes edits + three conflict classes (sibling-def, forward+converse capture, shadow) using a client-side innermost-binding resolver. No new @incr Memos or Observers in the rename package itself — `plan_rename` is one-shot.

**Tech Stack:** MoonBit 0.9.2, `@callers` (loom#129 facade), `@seam`, `@core` (for `Diagnostic`/`TextRange`/`DiagnosticSeverity`/`DiagnosticLabel`), `@hashmap`, `@hashset`. Test runner: `moon test`.

**Worktree:** Branch `feat/lambda-rename-consumer` checked out at `/home/antisatori/ghq/github.com/dowdiness/canopy/loom/`. All paths in this plan are relative to that loom-repo root.

**Baseline:** Post-#129 main. `cd examples/lambda && moon test` passes for callers; `examples/lambda/src/rename/` does not yet exist.

**Command convention:** Bash snippets show plain `moon ...` invocations. When executed through Claude Code, the RTK hook transparently rewrites them to `rtk moon ...` for token savings. Either form works.

**Current execution note:** Task 0 is already complete on this branch
(`270d3bc docs(plans): implementation plan for rename consumer`). Start
implementation at Task 1. Task 0 remains below as historical context only.

---

## File Structure

Changed files:

| File | Responsibility | Net change |
|---|---|---|
| `examples/lambda/src/callers/callers.mbt` | Add `CallersPipeline::facts()` accessor | +18 LOC |
| `examples/lambda/src/callers/callers_test.mbt` | Add facts-accessor test | +20 LOC |
| `examples/lambda/src/callers/pkg.generated.mbti` | Auto-regenerated | auto |
| `examples/lambda/src/rename/moon.pkg` | New package manifest | +14 LOC |
| `examples/lambda/src/rename/rename.mbt` | Public API: types + plan_rename | ~120 LOC |
| `examples/lambda/src/rename/target.mbt` | locate_target + name_range_of | ~80 LOC |
| `examples/lambda/src/rename/resolve.mbt` | resolve_innermost | ~30 LOC |
| `examples/lambda/src/rename/conflicts.mbt` | sibling/capture(forward+converse)/shadow | ~120 LOC |
| `examples/lambda/src/rename/rename_test.mbt` | 10 fixtures | ~250 LOC |
| `examples/lambda/src/rename/pkg.generated.mbti` | Auto-generated | auto |
| `docs/README.md` | Index this plan | +1 LOC |

Total: ~650 LOC of source + ~250 LOC of tests + 1 manifest. One PR; Full band per `~/.claude/CLAUDE.md` process calibration.

## Execution Dependencies

- Task 0 is complete; do not re-run it.
- Task 1 must land before any rename-package tests use
  `CallersPipeline::facts()`.
- Task 2 creates the package skeleton.
- Task 3 (`name_range_of`) and Task 5 (`resolve_innermost`) can be worked
  independently after Task 2. Task 4 depends on Task 3 because
  `locate_target` delegates to `name_range_of`.
- Task 6 depends on Task 3. Task 8 also depends on Task 5's
  `parent_scope_of` helper. Tasks 8-10 depend on the enclosing edges exposed
  through Task 1's `pipeline.facts()` accessor.
- `@callers.extract_facts(syntax)` is intentionally still the
  backward-compatible 2-tuple API `(defs, calls)`. Tests that need
  `enclosing` must build a `CallersPipeline` and read `pipeline.facts()`.
- Verification convention: Task 1 uses the callers package test because the
  rename package does not exist yet; Task 2 verifies the new package compiles;
  Task 3 onward runs `moon test -p dowdiness/lambda/rename 2>&1 | tail -10`
  and confirms the test count grows monotonically.

---

## Task 0: Commit this plan and index it (already complete)

**Files:**
- Added: `docs/plans/2026-05-19-rename-consumer-plan.md`
- Modified: `docs/README.md` (plan entry under Active Plans)

> Already complete in `270d3bc`; skip this task during implementation.

- [x] **Step 0.1: Verify the plan exists and docs/README.md hasn't been edited yet for this plan**

  ```bash
  git status -s
  ```

  Historical expected output before `270d3bc`:
  ```
  ?? docs/plans/2026-05-19-rename-consumer-plan.md
  ```

- [x] **Step 0.2: Update docs/README.md to index the implementation plan**

  Edit `docs/README.md` under "### Active Plans". Replace the existing rename-design entry with:

  ```markdown
  - [plans/2026-05-19-rename-consumer-design.md](plans/2026-05-19-rename-consumer-design.md) — Rename + conflict-detection consumer of `visible_from`: new `examples/lambda/src/rename/` package; one-method callers API expansion (`facts()`); two-pass capture detection
  - [plans/2026-05-19-rename-consumer-plan.md](plans/2026-05-19-rename-consumer-plan.md) — Implementation plan for the rename consumer (TDD, 13 tasks)
  ```

- [x] **Step 0.3: Commit**

  ```bash
  git add docs/plans/2026-05-19-rename-consumer-plan.md docs/README.md
  git commit -m "docs(plans): implementation plan for rename consumer

  TDD-structured plan executing the rename-consumer design spec
  (committed earlier on this branch). 13 tasks covering: facts()
  accessor on callers pipeline, rename package skeleton, name-range
  extraction, target lookup, innermost resolver, edit computation,
  three conflict checks (sibling, capture forward+converse, shadow),
  plan_rename wiring, and 10 test fixtures.

  Indexed in docs/README.md."
  ```

- [x] **Step 0.4: Verify the commit landed**

  ```bash
  git log -1 --stat
  ```

  Expected: two files changed (docs/README.md, docs/plans/2026-05-19-rename-consumer-plan.md).

---

## Task 1: Add `CallersPipeline::facts()` accessor on the callers pipeline

**Files:**
- Modify: `examples/lambda/src/callers/callers.mbt` — add `pub fn CallersPipeline::facts(self)` near `defs_of` (after the existing methods, just before `dispose`)
- Modify: `examples/lambda/src/callers/callers_test.mbt` — add test for facts() returning defensive copies
- Modify: `examples/lambda/src/callers/pkg.generated.mbti` — regenerated

### Step 1.1: Write the failing test for `CallersPipeline::facts()`

Append to `examples/lambda/src/callers/callers_test.mbt`:

```moonbit
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
  // Mutating returned arrays must NOT affect subsequent reads — defensive copy.
  defs.push(Def::{ name: "INJECT", scope: TopScope, start: 0, end: 0 })
  calls.clear()
  enclosing.clear()
  let (defs2, calls2, _) = pipeline.facts()
  // Original cached facts unchanged.
  inspect(defs2.iter().any(fn(d) { d.name == "INJECT" }), content="false")
  inspect(calls2.length() >= 1, content="true")
  pipeline.dispose()
}
```

### Step 1.2: Run test to verify it fails

```bash
cd examples/lambda && moon test -p dowdiness/lambda/callers -f callers_test.mbt 2>&1 | tail -20
```

Expected: compile error or method-not-found, e.g. `The value facts is not found in the current scope` or similar — `facts()` does not yet exist on `CallersPipeline`.

### Step 1.3: Implement `CallersPipeline::facts()`

Locate the `CallersPipeline::dispose` definition in `callers.mbt` (currently around line 513). Insert directly above it:

```moonbit
///|
/// Read the cached `(defs, calls, enclosing)` facts as defensive copies.
/// Mirrors the defensive-copy discipline of `callers_of`. Returned arrays
/// are independent from the cached Memo state — callers may mutate them
/// without affecting subsequent reads. Use this when a consumer needs
/// access to the unfiltered fact relations (e.g., for non-top-level call
/// enumeration that `callers_of`'s strict filter excludes).
pub fn CallersPipeline::facts(
  self : CallersPipeline,
) -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]) {
  let (defs, calls, enclosing) = self.facts_observer.get()
  (defs.copy(), calls.copy(), enclosing.copy())
}
```

### Step 1.4: Run test to verify it passes

```bash
cd examples/lambda && moon test -p dowdiness/lambda/callers -f callers_test.mbt 2>&1 | tail -10
```

Expected: all callers tests pass, including the new `pipeline: facts() returns defensive copies`.

### Step 1.5: Regenerate `.mbti` interface and format

```bash
cd examples/lambda && moon info && moon fmt
git diff src/callers/pkg.generated.mbti
```

Expected `.mbti` diff: one new line under `CallersPipeline` methods:

```
pub fn CallersPipeline::facts(Self) -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)])
```

No other diff in `.mbti` (no unintended trait-bound changes or signature shifts).

### Step 1.6: Commit

```bash
git add examples/lambda/src/callers/callers.mbt \
        examples/lambda/src/callers/callers_test.mbt \
        examples/lambda/src/callers/pkg.generated.mbti
git commit -m "feat(lambda/callers): expose facts() accessor on CallersPipeline

Returns defensive copies of the cached (defs, calls, enclosing) tuple
from the facts Memo. Mirrors the defensive-copy discipline of
callers_of. Unblocks consumers that need unfiltered call/def
relations — specifically the rename consumer for offset-based target
lookup and lambda-parameter reference enumeration that callers_of's
strict filter excludes."
```

---

## Task 2: Create the rename package skeleton

**Files:**
- Create: `examples/lambda/src/rename/moon.pkg` — package manifest with dependencies
- Create: `examples/lambda/src/rename/rename.mbt` — public types (RenamePlan, TextEdit) only
- Create: `examples/lambda/src/rename/rename_test.mbt` — empty test file (so `moon test` finds the package)

### Step 2.1: Create `moon.pkg`

Create `examples/lambda/src/rename/moon.pkg` with:

```
import {
  "dowdiness/seam" @seam,
  "dowdiness/lambda/callers" @callers,
  "dowdiness/lambda/syntax" @syntax,
  "dowdiness/loom/core" @core,
  "moonbitlang/core/hashmap",
  "moonbitlang/core/hashset",
  "moonbitlang/core/debug",
}

import {
  "dowdiness/lambda" @lambda,
  "dowdiness/loom" @loom,
  "dowdiness/incr" @incr,
} for "test"
```

### Step 2.2: Create `rename.mbt` with public types

Create `examples/lambda/src/rename/rename.mbt`:

```moonbit
// Rename + conflict-detection consumer of `CallersPipeline`.
//
// `plan_rename(pipeline, source, syntax, offset, new_name)` returns a
// `RenamePlan` carrying source edits and `@core.Diagnostic` conflicts.
// Three conflict classes are detected: sibling-def collision, capture
// (two-pass: forward + converse), and shadow.
//
// Conflict detection is conservative: the analysis layer overcounts to
// guarantee soundness because `Call.resolved_scope` records the
// binding scope, not the call's lexical scope. False positives surface
// in editor UI as "review before applying"; false negatives are
// correctness bugs. See docs/plans/2026-05-19-rename-consumer-design.md.

///|
/// Source-text edit produced by a rename. `(start, end)` is a half-open
/// byte range into the source; `new_text` is the replacement.
pub struct TextEdit {
  start : Int
  end : Int
  new_text : String
} derive(Eq, @debug.Debug)

///|
pub impl Show for TextEdit with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// The result of a rename request: the target def (or None if the
/// offset doesn't land on a binding identifier), the set of source
/// edits, and a diagnostics array carrying conflicts and input errors.
///
/// Editors should apply edits only if `diagnostics` contains no
/// `Error`-severity entries (or surface them and let the user override).
pub struct RenamePlan {
  target : @callers.Def?
  edits : Array[TextEdit]
  diagnostics : Array[@core.Diagnostic]
}
```

### Step 2.3: Create empty `rename_test.mbt`

Create `examples/lambda/src/rename/rename_test.mbt`:

```moonbit
// Test fixtures for `plan_rename`. Fixtures are added one-by-one as
// each implementation task lands. See plan file for the fixture list.
```

### Step 2.4: Verify package compiles

```bash
cd examples/lambda && moon check
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: no errors. The package compiles with just types and an empty test
file; rename-package test count is expected to be zero at this point.

### Step 2.5: Generate `.mbti` and format

```bash
cd examples/lambda && moon info && moon fmt
```

A new file `src/rename/pkg.generated.mbti` should appear.

### Step 2.6: Commit

```bash
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): scaffold rename package with public types

Creates the rename package with RenamePlan and TextEdit public types.
No logic yet — subsequent tasks add target lookup, edit computation,
conflict detection, and the plan_rename entry point.

Imports @callers (just merged in #129), @seam, @core (for Diagnostic),
and the standard hashmap/hashset. Test imports @lambda + @loom + @incr
to support the fixture pattern used by callers_test.mbt."
```

---

## Task 3: Implement `name_range_of` — identifier-token range extraction

**Files:**
- Create: `examples/lambda/src/rename/target.mbt` — `name_range_of`
- Modify: `examples/lambda/src/rename/rename_test.mbt` — add tests for `name_range_of`

`name_range_of(def, syntax)` walks the syntax tree from `def.start..def.end` finding the `IdentToken` whose text equals `def.name`. The token's byte range is returned.

Per spec §5.3, three binding kinds need support:
- LetDef: identifier is the first `IdentToken` after `LetKeyword`
- Lambda parameter: identifier is the first `IdentToken` after `LambdaToken`
- Let-paren parameter: identifier is inside the `ParamList`, an `IdentToken` matching `def.name`

The simplest robust algorithm: walk every token under the def's containing node; return the byte range of the first `IdentToken` whose text equals `def.name`. For the let-paren case with multiple params, we filter by both name AND a positional constraint (matched token must be inside the def's `Def.start..Def.end`).

### Step 3.1: Write failing tests for `name_range_of`

Append to `examples/lambda/src/rename/rename_test.mbt`:

```moonbit
///|
fn parse_to_syntax(source : String) -> @seam.SyntaxNode {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  rt.read(parser.syntax_tree())
}

///|
test "name_range_of: top-level LetDef identifier" {
  let src = "let foo = bar\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let foo_def = defs.iter().find(fn(d) { d.name == "foo" }).unwrap()
  let (start, end) = name_range_of(foo_def, syntax)
  // "foo" sits at offsets 4..7 in "let foo = bar\n"
  inspect(start, content="4")
  inspect(end, content="7")
}

///|
test "name_range_of: lambda parameter identifier" {
  let src = "let id = \\x. x\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let x_def = defs.iter().find(fn(d) { d.name == "x" }).unwrap()
  let (start, end) = name_range_of(x_def, syntax)
  // "x" parameter sits at offset 10 in "let id = \x. x\n"
  inspect(start, content="10")
  inspect(end, content="11")
}

///|
test "name_range_of: let-paren parameter identifier" {
  let src = "let f (x) = x\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let x_def = defs.iter().find(fn(d) { d.name == "x" }).unwrap()
  let (start, end) = name_range_of(x_def, syntax)
  // "x" inside the ParamList sits at offset 7 in "let f (x) = x\n"
  inspect(start, content="7")
  inspect(end, content="8")
}
```

### Step 3.2: Run tests to verify they fail

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -15
```

Expected: compile error — `name_range_of` is not defined.

### Step 3.3: Implement `name_range_of`

Create `examples/lambda/src/rename/target.mbt`:

```moonbit
///|
/// Find the byte range of the identifier token corresponding to `def`
/// in the syntax tree. Walks tokens under the def's containing node,
/// returning the first `IdentToken` whose text equals `def.name` and
/// whose byte range falls inside `[def.start, def.end)`.
///
/// Why we can't just use `def.start..def.end`: `Def.start/end` is the
/// enclosing-node range (LetDef, lambda, or let-paren), not the
/// identifier-token range. See spec §5.3.
pub fn name_range_of(
  def : @callers.Def,
  syntax : @seam.SyntaxNode,
) -> (Int, Int) {
  // Recursively walk; return on first match.
  match find_ident_in(syntax, def) {
    Some(range) => range
    // The def came from extract_facts(syntax), so the identifier MUST
    // exist somewhere under syntax. If we got here, the syntax tree
    // doesn't match the def — caller-side bug.
    None => fail("name_range_of: no IdentToken matched def \\{def.name} in \\{def.start}..\\{def.end}")
  }
}

///|
/// DFS for an `IdentToken` whose text == def.name and whose byte range
/// is inside the def's containing-node range.
fn find_ident_in(
  node : @seam.SyntaxNode,
  def : @callers.Def,
) -> (Int, Int)? {
  // Stop descending into subtrees that don't intersect the def's range.
  if node.end() <= def.start || node.start() >= def.end {
    return None
  }
  for child in node.children() {
    match child {
      @seam.SyntaxElement::Token(tok) =>
        if @syntax.SyntaxKind::from_raw(tok.kind()) == @syntax.IdentToken
          && tok.text() == def.name
          && tok.start() >= def.start
          && tok.end() <= def.end {
          return Some((tok.start(), tok.end()))
        }
      @seam.SyntaxElement::Node(child_node) =>
        match find_ident_in(child_node, def) {
          Some(r) => return Some(r)
          None => ()
        }
    }
  }
  None
}
```

### Step 3.4: Run tests to verify they pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 3 new tests pass.

### Step 3.5: Format and commit

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): name_range_of identifies token-range of a Def

Def.start/end is the enclosing-node range (LetDef/lambda/let-paren),
not the identifier-token range. Rename needs identifier-only edits.
This helper walks the syntax tree under the def's containing node,
finds the IdentToken matching def.name, and returns its byte range.

Tests cover all three binding kinds: top-level LetDef, lambda
parameter, and let-paren parameter. Per spec §5.3, this is the
rename package's compensation for Def's wider-range semantics."
```

---

## Task 4: Implement `locate_target` — offset-keyed target lookup

**Files:**
- Modify: `examples/lambda/src/rename/target.mbt` — add `locate_target`
- Modify: `examples/lambda/src/rename/rename_test.mbt` — tests

Per spec §5.2: filter `defs` by `name_range_of(d, syntax)` containing the offset. Return the unique matching def, or None.

### Step 4.1: Write failing tests

Append to `examples/lambda/src/rename/rename_test.mbt`:

```moonbit
///|
test "locate_target: hits top-level LetDef name" {
  let src = "let foo = bar\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  // Click on "foo" at offset 5 (mid-identifier).
  let target = locate_target(defs, syntax, 5)
  inspect(target is Some(_), content="true")
  inspect(target.unwrap().name, content="foo")
}

///|
test "locate_target: hits lambda parameter, not enclosing LetDef" {
  let src = "let id = \\x. x\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  // Click on "x" parameter at offset 10.
  let target = locate_target(defs, syntax, 10)
  inspect(target is Some(_), content="true")
  inspect(target.unwrap().name, content="x")
  // The let-bound "id" definition's range CONTAINS offset 10 too, but
  // its identifier "id" is at offsets 4..6 — not at 10. So locate_target
  // correctly picks "x", not "id".
}

///|
test "locate_target: returns None for whitespace offset" {
  let src = "let foo = bar\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  // Offset 3 is the space between "let" and "foo".
  let target = locate_target(defs, syntax, 3)
  inspect(target is None, content="true")
}
```

### Step 4.2: Run tests to verify they fail

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: compile error — `locate_target` not defined.

### Step 4.3: Implement `locate_target`

Append to `examples/lambda/src/rename/target.mbt`:

```moonbit
///|
/// Find the def whose identifier range contains `offset`. Returns None
/// if no def matches (offset is in whitespace, between identifiers, on
/// a keyword, etc.). Returns at most one def — by construction of the
/// extractor, distinct defs have distinct identifier-token ranges.
pub fn locate_target(
  defs : Array[@callers.Def],
  syntax : @seam.SyntaxNode,
  offset : Int,
) -> @callers.Def? {
  for d in defs {
    let (name_start, name_end) = name_range_of(d, syntax)
    if offset >= name_start && offset < name_end {
      return Some(d)
    }
  }
  None
}
```

### Step 4.4: Run tests to verify they pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 3 new tests pass.

### Step 4.5: Commit

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): locate_target picks the def at a byte offset

Iterates defs; for each, asks name_range_of for the identifier range
and accepts on half-open [name_start, name_end) containment of offset.
Returns None for whitespace/keyword offsets.

Key invariant exercised by the tests: clicking inside a lambda body
where the body offset is contained by the enclosing LetDef's wider
range — yet locate_target picks the lambda parameter (the identifier
range the offset actually hits), not the let. Verifies the
identifier-range-based lookup correctly resolves this ambiguity."
```

---

## Task 5: Implement `resolve_innermost` — client-side innermost-binding resolver

**Files:**
- Create: `examples/lambda/src/rename/resolve.mbt`
- Modify: `examples/lambda/src/rename/rename_test.mbt` — tests

Per spec §5.5: walks parent chain from `scope` upward via `enclosing` edges; at each visited scope, finds the first matching def. Terminates at TopScope.

### Step 5.1: Write failing tests

Append to `rename_test.mbt`:

```moonbit
///|
test "resolve_innermost: finds binding in same scope" {
  let defs : Array[@callers.Def] = [
    Def::{ name: "x", scope: TopScope, start: 4, end: 5 },
  ]
  let enclosing : Array[(@callers.ScopeId, @callers.ScopeId)] = []
  let result = resolve_innermost(TopScope, "x", defs, enclosing)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().name, content="x")
}

///|
test "resolve_innermost: walks parent chain" {
  let inner = @callers.ScopeId::LambdaScope(10, 20)
  let defs : Array[@callers.Def] = [
    Def::{ name: "x", scope: TopScope, start: 4, end: 5 },
  ]
  let enclosing : Array[(@callers.ScopeId, @callers.ScopeId)] = [
    (inner, TopScope),
  ]
  let result = resolve_innermost(inner, "x", defs, enclosing)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().scope is TopScope, content="true")
}

///|
test "resolve_innermost: innermost wins" {
  let inner = @callers.ScopeId::LambdaScope(10, 20)
  let defs : Array[@callers.Def] = [
    Def::{ name: "x", scope: TopScope, start: 4, end: 5 },
    Def::{ name: "x", scope: inner, start: 11, end: 12 },
  ]
  let enclosing : Array[(@callers.ScopeId, @callers.ScopeId)] = [
    (inner, TopScope),
  ]
  let result = resolve_innermost(inner, "x", defs, enclosing)
  inspect(result is Some(_), content="true")
  // Should resolve to the inner binding (start=11), not the outer (start=4).
  inspect(result.unwrap().start, content="11")
}

///|
test "resolve_innermost: returns None when no binding visible" {
  let defs : Array[@callers.Def] = [
    Def::{ name: "x", scope: TopScope, start: 4, end: 5 },
  ]
  let enclosing : Array[(@callers.ScopeId, @callers.ScopeId)] = []
  let result = resolve_innermost(TopScope, "y", defs, enclosing)
  inspect(result is None, content="true")
}
```

### Step 5.2: Run tests to verify they fail

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: compile error — `resolve_innermost` not defined.

### Step 5.3: Implement `resolve_innermost`

Create `examples/lambda/src/rename/resolve.mbt`:

```moonbit
///|
/// Walks the parent chain from `scope` upward via `enclosing` edges,
/// returning the closest Def matching `name`. TopScope has no parent
/// edge; the walk terminates after checking TopScope's bindings.
///
/// Ambiguity tiebreaker: when multiple defs share the same `(name, scope)`
/// pair (malformed input or duplicate let-paren params), returns the one
/// appearing first in the `defs` array. Matches the extractor's emission
/// order.
pub fn resolve_innermost(
  scope : @callers.ScopeId,
  name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> @callers.Def? {
  let visited : @hashset.HashSet[@callers.ScopeId] = @hashset.HashSet([])
  resolve_innermost_from(scope, name, defs, enclosing, visited)
}

///|
fn resolve_innermost_from(
  current : @callers.ScopeId,
  name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  visited : @hashset.HashSet[@callers.ScopeId],
) -> @callers.Def? {
  if visited.contains(current) {
    // Defensive against malformed cyclic input — should not occur
    // for facts produced by CallersPipeline::facts().
    return None
  }
  visited.add(current)
  // Find first matching def at `current` scope.
  for d in defs {
    if d.scope == current && d.name == name {
      return Some(d)
    }
  }
  match parent_scope_of(current, enclosing) {
    Some(parent) => resolve_innermost_from(parent, name, defs, enclosing, visited)
    None => None
  }
}

///|
fn parent_scope_of(
  scope : @callers.ScopeId,
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> @callers.ScopeId? {
  for edge in enclosing {
    if edge.0 == scope {
      return Some(edge.1)
    }
  }
  None
}
```

### Step 5.4: Run tests to verify they pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 4 new tests pass.

### Step 5.5: Commit

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): resolve_innermost walks parent chain

Client-side innermost-binding resolver: walks enclosing edges from
the query scope upward, returning the first def matching the name.
Terminates at TopScope (no parent edge). Defensive against cyclic
input via a visited set.

This is the only shadowing-aware operation the rename package needs.
Lives in the consumer, not the pipeline — keeps visible_from's
Bool-only semantics intact (spec §9.2)."
```

---

## Task 6: Implement `compute_edits` — generate the edit set

**Files:**
- Modify: `examples/lambda/src/rename/rename.mbt` — add `compute_edits` (private helper)
- Modify: `examples/lambda/src/rename/rename_test.mbt` — tests

Per spec §5.4: def-site edit (via `name_range_of`) + every Call where `c.callee == target.name && c.resolved_scope == target.scope` (using raw calls, NOT `callers_of`'s strict-filtered index).

### Step 6.1: Write failing tests

Append to `rename_test.mbt`:

```moonbit
///|
test "compute_edits: top-level let rename produces def-site + caller edits" {
  let src = "let f = \\x. x\nlet r = f y\n"
  let syntax = parse_to_syntax(src)
  let (defs, calls) = @callers.extract_facts(syntax)
  let f_def = defs.iter().find(fn(d) {
    d.name == "f" && d.scope is TopScope
  }).unwrap()
  let edits = compute_edits(f_def, calls, syntax, "fff")
  // Expect 2 edits: def site + one caller. Order doesn't matter.
  inspect(edits.length(), content="2")
  // Every edit replaces with "fff"
  for e in edits {
    inspect(e.new_text, content="fff")
  }
}

///|
test "compute_edits: ignores calls in a different scope" {
  // `\f. f` — lambda param f, body f refers to param (LambdaScope-resolved).
  // Renaming top-level `f` (which doesn't exist here) would be a no-op
  // for the body reference; instead, rename top-level `g` (does exist) and
  // verify the body f is untouched.
  let src = "let g = \\f. f\n"
  let syntax = parse_to_syntax(src)
  let (defs, calls) = @callers.extract_facts(syntax)
  let g_def = defs.iter().find(fn(d) { d.name == "g" }).unwrap()
  let edits = compute_edits(g_def, calls, syntax, "ggg")
  // Only the def site itself; no callers of g in the source.
  inspect(edits.length(), content="1")
}
```

### Step 6.2: Run tests to verify they fail

Expected: compile error — `compute_edits` not defined.

### Step 6.3: Implement `compute_edits` (private)

Append to `examples/lambda/src/rename/rename.mbt`:

```moonbit
///|
/// Produce the edit set for renaming `target` to `new_name`. Includes
/// the def-site identifier edit + every reference Call whose `callee`
/// equals the target's name and whose `resolved_scope` matches the
/// target's scope (uses raw calls, NOT `callers_of`'s strict-filtered
/// index — see spec §5.4).
fn compute_edits(
  target : @callers.Def,
  calls : Array[@callers.Call],
  syntax : @seam.SyntaxNode,
  new_name : String,
) -> Array[TextEdit] {
  let edits : Array[TextEdit] = []
  // Def-site edit.
  let (name_start, name_end) = name_range_of(target, syntax)
  edits.push(TextEdit::{
    start: name_start,
    end: name_end,
    new_text: new_name,
  })
  // Reference edits.
  for c in calls {
    if c.callee == target.name && c.resolved_scope == target.scope {
      edits.push(TextEdit::{
        start: c.start,
        end: c.end,
        new_text: new_name,
      })
    }
  }
  edits
}
```

### Step 6.4: Run tests to verify they pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 2 new tests pass.

### Step 6.5: Commit

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): compute_edits emits def-site + reference edits

Edit set is the def-site identifier (via name_range_of) plus every
Call where (callee, resolved_scope) matches the target. Uses raw
calls from CallersPipeline::facts(), not callers_of — the strict
filter in callers_of would exclude lambda-parameter references and
non-call-position references, which rename must rewrite.

Per spec §5.4: this is one of the two big reasons we added facts()
to the pipeline in Task 1 (the other being offset-keyed target
lookup)."
```

---

## Task 7: Implement sibling-def conflict check

**Files:**
- Create: `examples/lambda/src/rename/conflicts.mbt`
- Modify: `rename_test.mbt` — tests

Per spec §5.6: `defs.any(d => d.scope == target.scope && d.name == new_name)` → Error diagnostic.

### Step 7.1: Write failing tests

Append to `rename_test.mbt`:

```moonbit
///|
test "check_sibling_collision: same-scope name match fires" {
  let src = "let f = a\nlet g = b\n"
  let syntax = parse_to_syntax(src)
  let (defs, _) = @callers.extract_facts(syntax)
  let f_def = defs.iter().find(fn(d) { d.name == "f" }).unwrap()
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
  let f_def = defs.iter().find(fn(d) { d.name == "f" }).unwrap()
  let result = check_sibling_collision(f_def, "totally_new", defs, syntax)
  inspect(result is None, content="true")
}
```

### Step 7.2: Run tests to verify they fail

Expected: compile error — `check_sibling_collision` not defined.

### Step 7.3: Implement `check_sibling_collision`

Create `examples/lambda/src/rename/conflicts.mbt`:

```moonbit
///|
/// Sibling-def collision check: returns Some(diagnostic) iff another
/// def shares target's scope and has the proposed new_name.
pub fn check_sibling_collision(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  for d in defs {
    if d.scope == target.scope && d.name == new_name {
      let (target_start, target_end) = name_range_of(target, syntax)
      let (collider_start, collider_end) = name_range_of(d, syntax)
      return Some(make_sibling_diagnostic(
        target_start,
        target_end,
        collider_start,
        collider_end,
        new_name,
      ))
    }
  }
  None
}

///|
fn make_sibling_diagnostic(
  target_start : Int,
  target_end : Int,
  collider_start : Int,
  collider_end : Int,
  new_name : String,
) -> @core.Diagnostic {
  let primary = text_range_or_fail(target_start, target_end)
  let collider_range = text_range_or_fail(collider_start, collider_end)
  @core.Diagnostic::{
    source: @core.DiagnosticSource::DiagnosticSource("rename"),
    severity: @core.DiagnosticSeverity::Error,
    code: Some(@core.DiagnosticCode::DiagnosticCode("rename.sibling_collision")),
    message: "Cannot rename to '\\{new_name}': another binding with that name already exists in the same scope",
    primary: Some(primary),
    labels: [
      @core.DiagnosticLabel::{
        range: collider_range,
        message: Some("existing binding"),
      },
    ],
    notes: [],
    token: None,
  }
}

///|
fn text_range_or_fail(start : Int, end : Int) -> @core.TextRange {
  match try? @core.TextRange::from_offsets(start, end) {
    Ok(range) => range
    Err(_) => fail("rename: invalid diagnostic range")
  }
}
```

> **Note for implementers:** The range helper above matches the current `@core.TextRange::from_offsets` API and converts impossible invalid ranges into a local failure. Still verify `@core.Diagnostic`, `@core.DiagnosticSource`, `@core.DiagnosticSeverity`, `@core.DiagnosticCode`, and `@core.DiagnosticLabel` before broad edits. Run `moon ide doc "@core.Diagnostic*"` and adjust uniformly if signatures drift. The diagnostic shape (severity, code, primary, labels) is non-negotiable per spec §5.7; only the MoonBit syntax for constructing those values varies.

### Step 7.4: Run tests to verify they pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 2 new tests pass. If `@core.Diagnostic` constructor signatures differ from the template above, fix the constructor calls in Step 7.3 until tests pass.

### Step 7.5: Commit

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): sibling-def collision check

Emits an Error-severity @core.Diagnostic when another def at the
same scope shares the proposed new_name. Diagnostic carries primary
range = target identifier range, label = collider identifier range.

Code = 'rename.sibling_collision' for downstream dispatch."
```

---

## Task 8: Implement forward-capture conflict check

**Files:**
- Modify: `examples/lambda/src/rename/conflicts.mbt`
- Modify: `rename_test.mbt`

Per spec §5.6 forward pass: for each `d` in `defs` where `d.name == new_name`, check whether `target.scope` is a strict ancestor of `d.scope` via the enclosing chain. If yes → Error diagnostic.

### Step 8.1: Add helper `is_strict_ancestor` and tests

Append to `rename_test.mbt`:

```moonbit
///|
test "is_strict_ancestor: TopScope is ancestor of LambdaScope" {
  let inner = @callers.ScopeId::LambdaScope(10, 20)
  let enclosing : Array[(@callers.ScopeId, @callers.ScopeId)] = [
    (inner, TopScope),
  ]
  inspect(is_strict_ancestor(TopScope, inner, enclosing), content="true")
}

///|
test "is_strict_ancestor: equal scopes return false (strict)" {
  let enclosing : Array[(@callers.ScopeId, @callers.ScopeId)] = []
  inspect(is_strict_ancestor(TopScope, TopScope, enclosing), content="false")
}

///|
test "is_strict_ancestor: unrelated scopes return false" {
  let a = @callers.ScopeId::LambdaScope(10, 20)
  let b = @callers.ScopeId::LambdaScope(30, 40)
  let enclosing : Array[(@callers.ScopeId, @callers.ScopeId)] = [
    (a, TopScope),
    (b, TopScope),
  ]
  inspect(is_strict_ancestor(a, b, enclosing), content="false")
}
```

### Step 8.2: Implement `is_strict_ancestor`

Append to `examples/lambda/src/rename/conflicts.mbt`:

```moonbit
// Uses the private `parent_scope_of` helper added in Task 5. MoonBit files
// in the same package share private declarations.

///|
/// True iff `ancestor` is a strict ancestor of `descendant` on the
/// enclosing chain. Equal scopes return false. Walks descendant
/// upward via parent edges.
pub fn is_strict_ancestor(
  ancestor : @callers.ScopeId,
  descendant : @callers.ScopeId,
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> Bool {
  if ancestor == descendant {
    return false
  }
  let visited : @hashset.HashSet[@callers.ScopeId] = @hashset.HashSet([])
  is_strict_ancestor_from(ancestor, descendant, enclosing, visited)
}

///|
fn is_strict_ancestor_from(
  ancestor : @callers.ScopeId,
  current : @callers.ScopeId,
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  visited : @hashset.HashSet[@callers.ScopeId],
) -> Bool {
  if visited.contains(current) {
    return false
  }
  visited.add(current)
  match parent_scope_of(current, enclosing) {
    Some(parent) =>
      if parent == ancestor {
        true
      } else {
        is_strict_ancestor_from(ancestor, parent, enclosing, visited)
      }
    None => false
  }
}
```

### Step 8.3: Run is_strict_ancestor tests

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 3 new tests pass.

### Step 8.4: Write failing test for `check_forward_capture`

Append to `rename_test.mbt`:

```moonbit
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
  let pipeline = @callers.CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  let (defs, calls, enclosing) = pipeline.facts()
  pipeline.dispose()
  (syntax, defs, calls, enclosing)
}

///|
test "check_forward_capture: descendant binding fires" {
  // `let h = \f. \g. f g\n` — inner g shadows outer f-after-rename.
  let src = "let h = \\f. \\g. f g\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let outer_f = defs.iter().find(fn(d) {
    d.name == "f" && !(d.scope is TopScope)
  }).unwrap()
  let result = check_forward_capture(outer_f, "g", defs, enclosing, syntax)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().severity is @core.DiagnosticSeverity::Error, content="true")
}

///|
test "check_forward_capture: no descendant with new_name returns None" {
  let src = "let f = \\x. x\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let f_def = defs.iter().find(fn(d) {
    d.name == "f" && d.scope is TopScope
  }).unwrap()
  let result = check_forward_capture(f_def, "totally_new", defs, enclosing, syntax)
  inspect(result is None, content="true")
}
```

### Step 8.5: Implement `check_forward_capture`

Append to `conflicts.mbt`:

```moonbit
///|
/// Forward-capture check: scan defs of `new_name` for any whose scope
/// is a strict descendant of `target.scope`. Conservative — overcounts
/// in cases where the call's actual lexical chain doesn't pass through
/// the flagged def, but never undercounts.
pub fn check_forward_capture(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  for d in defs {
    if d.name == new_name && is_strict_ancestor(target.scope, d.scope, enclosing) {
      let (target_start, target_end) = name_range_of(target, syntax)
      let (intercept_start, intercept_end) = name_range_of(d, syntax)
      return Some(@core.Diagnostic::{
        source: @core.DiagnosticSource::DiagnosticSource("rename"),
        severity: @core.DiagnosticSeverity::Error,
        code: Some(@core.DiagnosticCode::DiagnosticCode("rename.capture")),
        message: "Forward capture: renaming to '\\{new_name}' would be intercepted by an existing binding in a nested scope",
        primary: Some(text_range_or_fail(target_start, target_end)),
        labels: [
          @core.DiagnosticLabel::{
            range: text_range_or_fail(intercept_start, intercept_end),
            message: Some("would intercept renamed references in this subtree"),
          },
        ],
        notes: ["Conservative check: false positives may occur if the actual lexical chain doesn't pass through this binding."],
        token: None,
      })
    }
  }
  None
}
```

### Step 8.6: Run forward-capture tests and commit

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 2 new check_forward_capture tests pass (total fixtures: 13).

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): forward-capture conflict check

Scans defs of new_name for any whose scope is a strict descendant
of target.scope on the enclosing chain. Conservative — overcounts to
guarantee soundness in absence of per-call lexical-scope tracking
(spec §5.6). Diagnostic code = rename.capture, label distinguishes
forward from converse pass."
```

---

## Task 9: Implement converse-capture conflict check

**Files:**
- Modify: `conflicts.mbt`, `rename_test.mbt`

Per spec §5.6 converse pass: for each Call where `c.callee == new_name`, check whether `c.resolved_scope` is ancestor-or-equal of `target.scope` → Error diagnostic.

### Step 9.1: Write failing test

Append to `rename_test.mbt`:

```moonbit
///|
test "check_converse_capture: existing call to new_name with target as descendant" {
  // `let g = a\nlet h = \f. f g\n` — rename param f -> g.
  // The body `f g` has a Call("g", TopScope) that would re-resolve
  // to the renamed parameter (LambdaScope, a descendant of TopScope).
  let src = "let g = a\nlet h = \\f. f g\n"
  let (syntax, defs, calls, enclosing) = facts_for_test(src)
  let f_param = defs.iter().find(fn(d) {
    d.name == "f" && !(d.scope is TopScope)
  }).unwrap()
  let result = check_converse_capture(f_param, "g", calls, enclosing, syntax)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().severity is @core.DiagnosticSeverity::Error, content="true")
}

///|
test "check_converse_capture: no matching calls returns None" {
  let src = "let f = a\n"
  let (syntax, defs, calls, enclosing) = facts_for_test(src)
  let f_def = defs.iter().find(fn(d) { d.name == "f" }).unwrap()
  let result = check_converse_capture(f_def, "totally_new", calls, enclosing, syntax)
  inspect(result is None, content="true")
}
```

### Step 9.2: Implement `check_converse_capture`

Append to `conflicts.mbt`:

```moonbit
///|
/// Converse-capture check: scan calls whose callee == new_name. If any
/// call's resolved_scope is ancestor-or-equal of target.scope, the
/// rename may intercept that call's resolution. Conservative.
pub fn check_converse_capture(
  target : @callers.Def,
  new_name : String,
  calls : Array[@callers.Call],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  for c in calls {
    if c.callee == new_name {
      let is_ancestor_or_equal = c.resolved_scope == target.scope
        || is_strict_ancestor(c.resolved_scope, target.scope, enclosing)
      if is_ancestor_or_equal {
        let (target_start, target_end) = name_range_of(target, syntax)
        return Some(@core.Diagnostic::{
          source: @core.DiagnosticSource::DiagnosticSource("rename"),
          severity: @core.DiagnosticSeverity::Error,
          code: Some(@core.DiagnosticCode::DiagnosticCode("rename.capture")),
          message: "Converse capture: renaming to '\\{new_name}' would intercept an existing reference to a different '\\{new_name}' binding",
          primary: Some(text_range_or_fail(c.start, c.end)),
          labels: [
            @core.DiagnosticLabel::{
              range: text_range_or_fail(target_start, target_end),
              message: Some("renamed binding would intercept"),
            },
          ],
          notes: ["Conservative check: false positives may occur if the call's lexical chain doesn't pass through the renamed scope."],
          token: None,
        })
      }
    }
  }
  None
}
```

### Step 9.3: Run converse-capture tests and commit

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 2 new tests pass.

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): converse-capture conflict check

Scans calls to new_name. If any call's resolved_scope is
ancestor-or-equal of target.scope, the rename may intercept its
resolution. Diagnostic shares code rename.capture with forward
pass; primary range is the existing call site, label points at
the renamed target."
```

---

## Task 10: Implement shadow conflict check

**Files:**
- Modify: `conflicts.mbt`, `rename_test.mbt`

Per spec §5.6: `resolve_innermost(parent_of(target.scope), new_name, defs, enclosing)`. If Some → Warning diagnostic.

### Step 10.1: Write failing test

Append to `rename_test.mbt`:

```moonbit
///|
test "check_shadow: param shadows outer let binding" {
  let src = "let g = a\nlet h = \\f. f\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let f_param = defs.iter().find(fn(d) {
    d.name == "f" && !(d.scope is TopScope)
  }).unwrap()
  let result = check_shadow(f_param, "g", defs, enclosing, syntax)
  inspect(result is Some(_), content="true")
  inspect(result.unwrap().severity is @core.DiagnosticSeverity::Warning, content="true")
}

///|
test "check_shadow: no outer binding returns None" {
  let src = "let h = \\f. f\n"
  let (syntax, defs, _, enclosing) = facts_for_test(src)
  let f_param = defs.iter().find(fn(d) {
    d.name == "f" && !(d.scope is TopScope)
  }).unwrap()
  let result = check_shadow(f_param, "g", defs, enclosing, syntax)
  inspect(result is None, content="true")
}
```

### Step 10.2: Implement `check_shadow`

Append to `conflicts.mbt`:

```moonbit
///|
/// Shadow check: if an outer binding of `new_name` exists at any
/// ancestor of `target.scope`, the rename would shadow it. Warning
/// severity — shadowing is legal but worth flagging.
pub fn check_shadow(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  // Find parent of target.scope. TopScope has no parent — no shadow possible.
  let mut parent : @callers.ScopeId? = None
  for edge in enclosing {
    if edge.0 == target.scope {
      parent = Some(edge.1)
      break
    }
  }
  match parent {
    None => None
    Some(p) =>
      match resolve_innermost(p, new_name, defs, enclosing) {
        None => None
        Some(outer) => {
          let (target_start, target_end) = name_range_of(target, syntax)
          let (outer_start, outer_end) = name_range_of(outer, syntax)
          Some(@core.Diagnostic::{
            source: @core.DiagnosticSource::DiagnosticSource("rename"),
            severity: @core.DiagnosticSeverity::Warning,
            code: Some(@core.DiagnosticCode::DiagnosticCode("rename.shadow")),
            message: "Renaming to '\\{new_name}' shadows an outer binding",
            primary: Some(text_range_or_fail(target_start, target_end)),
            labels: [
              @core.DiagnosticLabel::{
                range: text_range_or_fail(outer_start, outer_end),
                message: Some("shadowed binding"),
              },
            ],
            notes: [],
            token: None,
          })
        }
      }
  }
}
```

### Step 10.3: Run shadow tests and commit

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: 2 new tests pass.

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): shadow conflict check

Looks up parent of target.scope and runs resolve_innermost for
new_name from that parent. If found, target rename would shadow it
— Warning severity (legal, but worth flagging). Code = rename.shadow."
```

---

## Task 11: Wire up `plan_rename` entry point + smoke fixture

**Files:**
- Modify: `examples/lambda/src/rename/rename.mbt` — add `plan_rename`
- Modify: `rename_test.mbt` — add smoke fixture (fixture 1 from spec §7)

### Step 11.1: Write failing test (fixture 1: smoke)

Append to `rename_test.mbt`:

```moonbit
///|
/// Helper: build a CallersPipeline + extract syntax in one call.
fn setup_pipeline(
  source : String,
) -> (@callers.CallersPipeline, @seam.SyntaxNode, @incr.Runtime) {
  let rt = @incr.Runtime::new()
  let parser = @loom.new_parser(source, @lambda.lambda_grammar, runtime=rt)
  let pipeline = @callers.CallersPipeline::CallersPipeline(rt, parser.syntax_tree())
  let syntax = rt.read(parser.syntax_tree())
  (pipeline, syntax, rt)
}

///|
test "fixture 1 (smoke): top-level let rename, three edits, no diagnostics" {
  let src = "let f = \\x. x\nlet r = f (f y)\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  // Click offset 4 = the "f" identifier in "let f = ..."
  let plan = plan_rename(pipeline, src, syntax, 4, "fff")
  inspect(plan.target is Some(_), content="true")
  inspect(plan.target.unwrap().name, content="f")
  // 3 edits: def + 2 references inside "f (f y)"
  inspect(plan.edits.length(), content="3")
  for e in plan.edits {
    inspect(e.new_text, content="fff")
  }
  // No conflicts.
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}
```

### Step 11.2: Run test to verify failure

Expected: compile error — `plan_rename` not defined.

### Step 11.3: Implement `plan_rename`

Append to `examples/lambda/src/rename/rename.mbt`:

```moonbit
///|
/// Plan a rename: locate the target def at `offset`, compute the edit
/// set, run conflict detection, and return a `RenamePlan` bundling
/// all of it.
///
/// Returns `RenamePlan { target: None, edits: [], diagnostics: [no_target] }`
/// when the offset doesn't land on a binding identifier.
///
/// No-op case: if `new_name == target.name`, returns an Info diagnostic
/// (`rename.no_op`) and no edits.
pub fn plan_rename(
  pipeline : @callers.CallersPipeline,
  _source : String,
  syntax : @seam.SyntaxNode,
  offset : Int,
  new_name : String,
) -> RenamePlan {
  let (defs, calls, enclosing) = pipeline.facts()
  // 1. Locate target.
  let target = locate_target(defs, syntax, offset)
  match target {
    None =>
      return RenamePlan::{
        target: None,
        edits: [],
        diagnostics: [
          @core.Diagnostic::{
            source: @core.DiagnosticSource::DiagnosticSource("rename"),
            severity: @core.DiagnosticSeverity::Error,
            code: Some(@core.DiagnosticCode::DiagnosticCode("rename.no_target_at_offset")),
            message: "No binding identifier at offset \\{offset}",
            primary: None,
            labels: [],
            notes: [],
            token: None,
          },
        ],
      }
    Some(_) => ()
  }
  let target = target.unwrap()
  // 2. No-op case.
  if new_name == target.name {
    return RenamePlan::{
      target: Some(target),
      edits: [],
      diagnostics: [
        @core.Diagnostic::{
          source: @core.DiagnosticSource::DiagnosticSource("rename"),
          severity: @core.DiagnosticSeverity::Info,
          code: Some(@core.DiagnosticCode::DiagnosticCode("rename.no_op")),
          message: "new_name equals existing name — nothing to do",
          primary: None,
          labels: [],
          notes: [],
          token: None,
        },
      ],
    }
  }
  // 3. Compute edits.
  let edits = compute_edits(target, calls, syntax, new_name)
  // 4. Run conflict checks.
  let diagnostics : Array[@core.Diagnostic] = []
  match check_sibling_collision(target, new_name, defs, syntax) {
    Some(d) => diagnostics.push(d)
    None => ()
  }
  match check_forward_capture(target, new_name, defs, enclosing, syntax) {
    Some(d) => diagnostics.push(d)
    None => ()
  }
  match check_converse_capture(target, new_name, calls, enclosing, syntax) {
    Some(d) => diagnostics.push(d)
    None => ()
  }
  match check_shadow(target, new_name, defs, enclosing, syntax) {
    Some(d) => diagnostics.push(d)
    None => ()
  }
  RenamePlan::{ target: Some(target), edits, diagnostics }
}
```

### Step 11.4: Run smoke test to verify it passes

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -10
```

Expected: smoke fixture passes; total test count includes all unit tests from Tasks 3-10 + this new smoke fixture.

### Step 11.5: Commit

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/rename/
git commit -m "feat(lambda/rename): plan_rename wires the components

Public entry point: locate target -> early-return on miss or no-op
-> compute edits -> run four conflict checks (sibling, forward
capture, converse capture, shadow) -> bundle into RenamePlan.

Smoke fixture (spec §7 fixture 1) passes: top-level let f rename to
fff in 'let f = \\x. x\\nlet r = f (f y)' produces 3 edits and no
diagnostics."
```

---

## Task 12: Remaining test fixtures (fixtures 2-10 from spec §7)

**Files:**
- Modify: `rename_test.mbt`

Each fixture is its own commit for bisectability — if a fixture exposes a bug, the bug-fix commit is local.

### Step 12.1: Fixture 2 — sibling collision

Append to `rename_test.mbt`:

```moonbit
///|
test "fixture 2 (sibling collision): rename f -> g when g exists at same scope" {
  let src = "let f = a\nlet g = b\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  // Click "f" at offset 4.
  let plan = plan_rename(pipeline, src, syntax, 4, "g")
  inspect(plan.target.unwrap().name, content="f")
  // Edits are still computed even with a conflict (editor decides).
  inspect(plan.edits.length() >= 1, content="true")
  // Sibling collision diagnostic fires.
  let has_collision = plan.diagnostics.iter().any(fn(d) {
    d.code is Some(@core.DiagnosticCode::DiagnosticCode("rename.sibling_collision"))
  })
  inspect(has_collision, content="true")
  pipeline.dispose()
}
```

Run, commit:

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 2 — sibling collision"
```

### Step 12.2: Fixture 3 — forward capture

```moonbit
///|
test "fixture 3 (forward capture): outer f rename to g, inner g intercepts" {
  let src = "let h = \\f. \\g. f g\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  // "f" lambda param sits at offset 9 (after "let h = \\").
  let plan = plan_rename(pipeline, src, syntax, 9, "g")
  inspect(plan.target.unwrap().name, content="f")
  let has_capture = plan.diagnostics.iter().any(fn(d) {
    d.code is Some(@core.DiagnosticCode::DiagnosticCode("rename.capture"))
  })
  inspect(has_capture, content="true")
  pipeline.dispose()
}
```

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 3 — forward capture"
```

### Step 12.3: Fixture 4 — converse capture + shadow co-occur

```moonbit
///|
test "fixture 4 (converse capture + shadow): rename param f -> g where outer g exists" {
  let src = "let g = a\nlet h = \\f. f g\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  // The "f" parameter sits at offset 19 ("let g = a\\nlet h = \\" = 18 chars; "f" at 19).
  // Verify the exact offset against the source-string layout if the test fails.
  let plan = plan_rename(pipeline, src, syntax, 19, "g")
  inspect(plan.target.unwrap().name, content="f")
  let has_capture = plan.diagnostics.iter().any(fn(d) {
    d.code is Some(@core.DiagnosticCode::DiagnosticCode("rename.capture"))
  })
  let has_shadow = plan.diagnostics.iter().any(fn(d) {
    d.code is Some(@core.DiagnosticCode::DiagnosticCode("rename.shadow"))
  })
  inspect(has_capture, content="true")
  inspect(has_shadow, content="true")
  pipeline.dispose()
}
```

> **Implementer note:** If offset 19 doesn't land on `f`, compute the actual offset by counting: `let g = a` is 9 chars (0..8), `\n` at 9, `let h = \\` is 8 chars (10..17), so `f` starts at 18 (`\\f` is two chars in the source string but the backslash counts as one byte; the parameter identifier `f` is at offset 19 — wait, that's not right either). Compute carefully and adjust. The principle is: pick any offset inside the `f`'s identifier-token range that `locate_target` will accept.

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 4 — converse capture + shadow co-occur"
```

### Step 12.4: Fixture 5 — shadow without converse capture

```moonbit
///|
test "fixture 5 (shadow only): rename param f -> g, no body reference to g" {
  let src = "let g = a\nlet h = \\f. f\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  // f parameter (compute offset analogously).
  let plan = plan_rename(pipeline, src, syntax, 19, "g")
  let has_shadow = plan.diagnostics.iter().any(fn(d) {
    d.code is Some(@core.DiagnosticCode::DiagnosticCode("rename.shadow"))
  })
  let has_capture = plan.diagnostics.iter().any(fn(d) {
    d.code is Some(@core.DiagnosticCode::DiagnosticCode("rename.capture"))
  })
  inspect(has_shadow, content="true")
  inspect(has_capture, content="false")
  pipeline.dispose()
}
```

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 5 — shadow without converse capture"
```

### Step 12.5: Fixture 6 — top-level recursion

```moonbit
///|
test "fixture 6 (top-level recursion): rename f -> fff, both refs rewritten" {
  let src = "let f = \\x. f x\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 4, "fff")
  inspect(plan.target.unwrap().name, content="f")
  // 2 edits: def-site + recursive call.
  inspect(plan.edits.length(), content="2")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}
```

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 6 — top-level recursion"
```

### Step 12.6: Fixture 7 — let-paren parameter

```moonbit
///|
test "fixture 7 (let-paren parameter): rename x -> y in let f (x) = x" {
  let src = "let f (x) = x\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  // "x" parameter inside ParamList; offset 7 (between the parens).
  let plan = plan_rename(pipeline, src, syntax, 7, "y")
  inspect(plan.target.unwrap().name, content="x")
  // 2 edits: param def-site + body reference.
  inspect(plan.edits.length(), content="2")
  inspect(plan.diagnostics.length(), content="0")
  pipeline.dispose()
}
```

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 7 — let-paren parameter rename"
```

### Step 12.7: Fixture 8 — no-op

```moonbit
///|
test "fixture 8 (no-op): rename f -> f produces single Info diagnostic" {
  let src = "let f = a\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  let plan = plan_rename(pipeline, src, syntax, 4, "f")
  inspect(plan.edits.length(), content="0")
  inspect(plan.diagnostics.length(), content="1")
  inspect(
    plan.diagnostics[0].code is Some(@core.DiagnosticCode::DiagnosticCode("rename.no_op")),
    content="true",
  )
  inspect(plan.diagnostics[0].severity is @core.DiagnosticSeverity::Info, content="true")
  pipeline.dispose()
}
```

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 8 — no-op (new_name == target.name)"
```

### Step 12.8: Fixture 9 — offset miss

```moonbit
///|
test "fixture 9 (offset miss): whitespace offset returns no_target diagnostic" {
  let src = "let f = a\n"
  let (pipeline, syntax, _rt) = setup_pipeline(src)
  // Offset 3 = space between "let" and "f".
  let plan = plan_rename(pipeline, src, syntax, 3, "fff")
  inspect(plan.target is None, content="true")
  inspect(plan.edits.length(), content="0")
  inspect(
    plan.diagnostics[0].code is Some(@core.DiagnosticCode::DiagnosticCode("rename.no_target_at_offset")),
    content="true",
  )
  pipeline.dispose()
}
```

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 9 — offset miss"
```

### Step 12.9: Fixture 10 — name-range correctness (meta-check)

```moonbit
///|
test "fixture 10 (name-range correctness): edit byte ranges are identifier-token, not node, ranges" {
  // Verify per binding kind that the def-site edit's (start, end) is the
  // identifier-token range — NOT the wider enclosing-node range.

  // LetDef: "let foo = bar" — identifier "foo" at 4..7.
  let src1 = "let foo = bar\n"
  let (pipeline1, syntax1, _) = setup_pipeline(src1)
  let plan1 = plan_rename(pipeline1, src1, syntax1, 5, "renamed")
  let def_edit1 = plan1.edits.iter().find(fn(e) { e.start == 4 }).unwrap()
  inspect(def_edit1.end, content="7")
  pipeline1.dispose()

  // Lambda param: "let id = \\x. x" — "x" parameter at 10..11.
  let src2 = "let id = \\x. x\n"
  let (pipeline2, syntax2, _) = setup_pipeline(src2)
  let plan2 = plan_rename(pipeline2, src2, syntax2, 10, "y")
  let def_edit2 = plan2.edits.iter().find(fn(e) { e.start == 10 }).unwrap()
  inspect(def_edit2.end, content="11")
  pipeline2.dispose()

  // Let-paren param: "let f (x) = x" — "x" at offset 7..8.
  let src3 = "let f (x) = x\n"
  let (pipeline3, syntax3, _) = setup_pipeline(src3)
  let plan3 = plan_rename(pipeline3, src3, syntax3, 7, "y")
  let def_edit3 = plan3.edits.iter().find(fn(e) { e.start == 7 }).unwrap()
  inspect(def_edit3.end, content="8")
  pipeline3.dispose()
}
```

```bash
cd examples/lambda && moon test -p dowdiness/lambda/rename 2>&1 | tail -5
git add examples/lambda/src/rename/rename_test.mbt
git commit -m "test(lambda/rename): fixture 10 — name-range correctness meta-check

Verifies that for each binding kind (LetDef, lambda param, let-paren
param), the def-site edit's (start, end) is the identifier-token
range — NOT the wider enclosing-node range. This is the regression
test for Codex's BLOCK F (round 3 review) discovery that Def.start/end
is node-range, not identifier-range."
```

---

## Task 13: Final verification — moon info + fmt + full test suite + .mbti audit

**Files:** Any auto-regenerated files.

### Step 13.1: Run full test suite

```bash
cd examples/lambda && moon test 2>&1 | tail -20
```

Expected: every test passes. Note pre-existing v0.9.2 snapshot failures unrelated to rename (acceptable if they were also failing on main before this branch).

### Step 13.2: Regenerate interfaces and format

```bash
cd examples/lambda && moon info && moon fmt
```

### Step 13.3: Audit `.mbti` diffs

```bash
git diff src/callers/pkg.generated.mbti src/rename/pkg.generated.mbti 2>&1 | head -80
```

Expected:
- `src/callers/pkg.generated.mbti`: one new line for `facts()` (already committed in Task 1, but re-running `moon info` should produce zero diff here)
- `src/rename/pkg.generated.mbti`: full new interface listing types (`RenamePlan`, `TextEdit`) and pub functions (`plan_rename`, `name_range_of`, `locate_target`, `resolve_innermost`, `check_sibling_collision`, `is_strict_ancestor`, `check_forward_capture`, `check_converse_capture`, `check_shadow`)

If there are unexpected `.mbti` diffs (e.g., a function got a wider trait bound than intended), investigate before committing.

### Step 13.4: Final commit (if any cleanup needed)

```bash
git status
git add -p   # interactive review
git commit -m "chore(lambda/rename): regenerate .mbti + format" || echo "nothing to commit"
```

### Step 13.5: Push branch + open PR

```bash
git push -u origin feat/lambda-rename-consumer
gh pr create --title "feat(lambda): rename + conflict-detection consumer of visible_from" --body "$(cat <<'EOF'
## Summary

Implements the rename + conflict-detection consumer designed in
[2026-05-19-rename-consumer-design.md](docs/plans/2026-05-19-rename-consumer-design.md).
Follows the implementation plan
[2026-05-19-rename-consumer-plan.md](docs/plans/2026-05-19-rename-consumer-plan.md).

- New `examples/lambda/src/rename/` package with `plan_rename(...) -> RenamePlan`
- One-line callers-API expansion: `CallersPipeline::facts()` accessor
- Three conflict classes: sibling-def, capture (forward + converse), shadow
- Conflicts emitted as `@core.Diagnostic` with structured codes for editor dispatch
- 10 behavioral fixtures + per-component unit tests

Design validated through 5 Codex review rounds before implementation.

## Test plan

- [ ] `cd examples/lambda && moon test` — all tests pass including 10 new rename fixtures + ~20 component unit tests
- [ ] `git diff src/callers/pkg.generated.mbti` — only `facts()` accessor added
- [ ] Smoke fixture verifies happy path (3 edits, 0 diagnostics)
- [ ] Forward-capture fixture verifies the nested-lambda case (Codex round-2 example correction)
- [ ] Name-range correctness fixture verifies identifier-only edit ranges (Codex BLOCK F regression test)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 13.6: Verify PR CI status

```bash
gh pr checks $(gh pr list --head feat/lambda-rename-consumer --json number --jq '.[0].number')
```

Expected: CodeRabbit + WIP pass (loom has no MoonBit CI per session notes; rely on local `moon test`).

---

## Out of scope (deferred to follow-up PRs)

Per spec §8:

- **Curried let-paren** (`let f (x) (y) = ...`) — extractor doesn't model nested ParamList scopes
- **Cross-file rename** — lambda example has no module system
- **Undo construction** — editor concern
- **Preview snippets** — editor concern
- **Optimization fast path** for top-level renames using `callers_of`'s strict-filter index (YAGNI)
- **Extending `Call` with lexical scope** for precision (spec §9.6) — promotion criterion: if false-positive rate proves too high in real-world usage

---

## Notes for implementers

- **Diagnostic API surface verification:** Tasks 7-10 use `@core.Diagnostic`, `@core.TextRange`, `@core.DiagnosticSeverity`, `@core.DiagnosticCode`, `@core.DiagnosticSource`, and `@core.DiagnosticLabel`. Current plan snippets use `TextRange::from_offsets` through `text_range_or_fail`, matching the checked-in `@core` API. Run `moon ide doc "@core.Diagnostic*"` and `moon ide peek-def @core.Diagnostic` BEFORE Task 7 to confirm the API has not drifted, and adjust the diagnostic-construction code uniformly across Tasks 7-10 if needed. The diagnostic shape (severity, code, primary, labels) is non-negotiable per spec §5.7; only the MoonBit syntax for constructing those values varies.

- **Offset calculations in fixtures:** Fixtures 4 and 5 depend on exact byte offsets in source strings containing `\n` and `\\`. If a fixture fails on the locate_target call, recompute the offset by hand: each `\\` is one source byte (the backslash); each `\n` is one source byte (a newline). The compiler escapes both in the MoonBit string literal but the run-time string has single bytes.

- **No `loop` keyword** in MoonBit 0.9.2 — use `for ... in` per `~/.claude/moonbit-base.md`. Already followed in the code blocks above.

- **`@debug.Debug` derive** for new structs; do NOT derive `Show` for containers (deprecation per v0.9.2).

- **Verification before completion:** Per `superpowers:verification-before-completion`, Task 1 verifies with `moon test -p dowdiness/lambda/callers -f callers_test.mbt 2>&1 | tail -10` because the rename package does not exist yet. Task 2 verifies the new package compiles and runs the empty rename package test command. From Task 3 onward, run `moon test -p dowdiness/lambda/rename 2>&1 | tail -10` after each task's commit and confirm the test count grows monotonically. Do not claim a task complete until verification passes.
