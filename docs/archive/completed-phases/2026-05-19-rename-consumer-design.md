# Rename + conflict-detection consumer of `visible_from`

**Status:** Complete. Implemented on branch `feat/lambda-rename-consumer`
through the rename consumer commits ending at `6a9d183`.

**Completion note:** The implementation adds `CallersPipeline::facts()`,
the new `examples/lambda/src/rename/` package, public `plan_rename`, and
the sibling/capture/shadow diagnostics described below.

Decision record:

- [ADR: Lambda Rename Consumer](../../decisions/2026-05-20-lambda-rename-consumer.md).

**Branch:** `feat/lambda-rename-consumer`.

**Predecessor:** loom#129 (squash `3682e59`) shipped `CallersPipeline::visible_from` plus the supporting `enclosing` edges, `Hash` derive on `ScopeId`, and the `facts_observer` GC anchor.

**Successor (anticipated):** an editor-side rename UI consumer (Codemirror/Zed/etc.) — out of scope here. This spec defines the *analysis layer*; the editor decides how to render conflicts and whether to apply edits.

## 1. Problem

PR #129 named rename-with-conflict-detection as the motivating consumer of `visible_from` (§1, §11). The pipeline's current public surface is:

- `defs_of(name) -> Array[Def]` — name-keyed
- `callers_of(name) -> Array[Call]` — name-keyed, strict-filtered to `resolved_scope == TopScope` *and* `is_call_position == true`
- `visible_from(scope, name) -> Bool` — membership only, deliberately does not model shadowing (§6.1 of the predecessor spec)
- `build_visibility(defs, enclosing) -> HashMap[(ScopeId, String), Unit]` — pure helper exposing the same data flatly

This surface is sufficient for "highlight callers of `f`" but insufficient for "rename `f → g`":

- **Target lookup** requires offset-keyed access; `defs_of` is name-keyed.
- **Caller enumeration** needs *all* references to the target, not just top-scope-resolved call-position calls; `callers_of` strict-filtering excludes lambda-parameter references entirely.
- **Capture / shadow detection** needs binding-identity reasoning that `visible_from`'s Bool-only return explicitly cannot provide.

The rename consumer must close these gaps without re-opening the Datalog-deferral argument from the predecessor spec (§7).

## 2. Constraints that shape the design

- **Pipeline data is the source of truth, not a duplicate extraction.** Re-walking the syntax tree per rename throws away the incremental `facts` Memo's cached state. The rename consumer reads cached facts, never re-extracts.
- **`Def.start/end` and `Call.start/end` are enclosing-node ranges, not identifier-token ranges.** Verified at `examples/lambda/src/callers/callers.mbt:205, :227, :248, :274` — for let definitions, lambda parameters, let-paren parameters, and var references respectively, `start/end` is the wider AST node. `Def.name_start/name_end` carries the binding identifier range; reference edits still compute the identifier token from the `VarRef` node.
- **`visible_from` returns `Bool`, not binding identity.** The rename consumer reconstructs shadowing semantics client-side; the pipeline stays minimal.
- **Curried / nested let-paren is not modeled by the current extractor.** `examples/lambda/src/callers/callers.mbt:241` puts all params from one `ParamList` into the same `LambdaScope`. Multi-`ParamList` let-paren (`let f (x) (y) = ...`) is not modeled as nested scopes. V1 ships uncurried support only and documents the gap.
- **One-shot computation, not a long-lived reactive cell.** `plan_rename` is called when the user invokes a rename action. It reads pipeline state once and returns a value; it does not register dependent cells in `@incr`.

## 3. Decision: ship `plan_rename` as a new `examples/lambda/src/rename/` package; extend callers with one accessor

Two atomic changes:

1. **Callers package** adds one method:
   ```
   pub fn CallersPipeline::facts(self)
     -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)])
   ```
   Returns defensive copies of the cached `facts` Memo content via untracked observer read. Mirrors the defensive-copy discipline of `callers_of` at `callers.mbt:526`.

2. **New `examples/lambda/src/rename/` package** owns rename-specific logic. Imports `@callers`, `@seam`, and `@core` (for `Diagnostic`).

No new `@incr` Memos, Observers, Relations, or Scopes. No changes to `extract_facts`, `build_visibility`, `callers_of`, or `defs_of`. The pipeline's API expansion is bounded to one accessor.

## 4. Architecture

Single public entry point:

```
plan_rename(
  pipeline : @callers.CallersPipeline,
  source   : String,
  syntax   : @seam.SyntaxNode,
  offset   : Int,
  new_name : String,
) -> RenamePlan
```

Data flow:

```
plan_rename(...)
  │
  ▼
  pipeline.facts() ─→ (defs, calls, enclosing)         [one untracked read]
  │
  ├─→ locate_target(defs, offset)            ─→ target : Def?
  │
  ├─→ compute_edits(target, calls, syntax)   ─→ Array[TextEdit]
  │     ├─ name_range_of(target, syntax)              [def-site identifier range]
  │     └─ calls filtered by (resolved_scope, callee)  [reference sites]
  │
  └─→ check_conflicts(target, new_name, defs, enclosing) ─→ Array[Diagnostic]
        ├─ sibling-def
        ├─ capture (conservative descendant scan)
        └─ shadow
```

All side effects are reads. No mutation of `source`, `syntax`, or pipeline state.

## 5. Components

### 5.1 Types

```
pub struct RenamePlan {
  target      : @callers.Def?
  edits       : Array[TextEdit]
  diagnostics : Array[@core.Diagnostic]
}

pub struct TextEdit {
  start    : Int
  end      : Int
  new_text : String
}
```

`RenamePlan.target` is `None` when no def is found at the given offset (an input error, surfaced as an Error-severity Diagnostic with `code = "rename.no_target_at_offset"`). Editors apply edits **only if** `diagnostics` contains no Error-severity entries (or surface them and let the user override).

### 5.2 Target lookup

```
fn locate_target(defs : Array[Def], syntax : SyntaxNode, offset : Int) -> Def?
```

For each candidate `d` in `defs`, read `(name_start, name_end) = name_range_of(d, syntax)` (see §5.3) and accept `d` iff `name_start <= offset < name_end`. Returns the unique matching def, or `None` if none.

Why not use `d.start <= offset < d.end`: `Def.start/end` is the *enclosing-node range* (verified at `callers.mbt:205, :227, :248` for lambda param, let definition, and let-paren param respectively). The let-paren node's range contains its parameter's range; the lambda node's range contains its body. Filtering by the wider range would match multiple defs simultaneously (e.g., clicking inside the body of `\x. f(x)` would match the lambda param `x`, even though the offset is on `f`).

The identifier-token range is the *clickable region* — exactly the bytes the user clicked on the binding's name.

If no def's identifier range contains the offset, target = `None` and an Error diagnostic `rename.no_target_at_offset` is emitted.

### 5.3 Name-range extraction (review fix)

```
fn name_range_of(def : Def, syntax : SyntaxNode) -> (Int, Int)
```

Returns the stored `def.name_start/name_end` identifier-token range. This is the source of every def-site TextEdit's `(start, end)`.

`Def.start/end` remains the containing syntax-node range for consumers that need a wider binding span. The extra name range is what lets rename disambiguate bindings that share a containing node, including `let f (f) = ...` and duplicate let-paren parameters such as `let f(x, x) = ...`.

### 5.4 Edit computation

```
fn compute_edits(target : Def, calls : Array[Call], syntax : SyntaxNode, new_name : String)
  -> Array[TextEdit]
```

Edit set:

1. Def-site edit: `TextEdit(name_start, name_end, new_name)` from `name_range_of(target, syntax)`.
2. Reference edits: for each `c : Call` where `c.callee == target.name`, compute the call's identifier-token range and resolve the name from that source position. The resolver chooses completed `let` bindings in source order, confines block-local `let` visibility to the containing `SourceFile` or `BlockExpr`, and uses the latest same-name let-paren parameter slot for duplicate parameters.

The reference filter uses raw `calls` from `pipeline.facts()`, not `callers_of`, because:

- `callers_of` strict-filters to `is_call_position == true` (excludes references in non-call positions like `let g = f` where `f` is on the value side)
- `callers_of` strict-filters to `resolved_scope == TopScope` (excludes lambda-parameter and let-paren-parameter references)

For top-level let renames specifically, `callers_of` would suffice as an optimization, but adding that fast path is YAGNI in v1.

### 5.5 Innermost-binding resolver (client-side)

```
fn resolve_innermost(
  scope     : ScopeId,
  name      : String,
  defs      : Array[Def],
  enclosing : Array[(ScopeId, ScopeId)],
) -> Def?
```

Walks the parent chain from `scope` upward via `enclosing` edges. At each visited scope `S`, checks whether any `Def` in `defs` has `d.scope == S && d.name == name`. Returns the first matching completed `let` in that scope, or the latest matching scope-binding parameter slot when duplicate let-paren parameters share one collapsed `LambdaScope`.

`TopScope` has no parent edge — the walk terminates after checking TopScope's bindings.

This is the *only* shadowing-aware operation the rename package needs. It does not propagate back into the pipeline.

**Ambiguity tiebreaker**: if multiple scope-binding defs share the same `(name, scope)` pair (duplicate let-paren params per `callers.mbt:241`), `resolve_innermost` returns the later parameter slot. This matches the right-folded nested-lambda desugaring: in `let f(x, x) = x`, the body `x` resolves to the second parameter. Duplicate top-level definitions still follow the module's sequential source-order rules.

### 5.6 Conflict detection

Three checks, each emitting an `@core.Diagnostic` with structured fields. Capture is **two-pass** (forward + converse) — both report under the same `rename.capture` code with distinguishing labels.

#### Sibling-def

```
defs.any(d => d.name == new_name && defs_are_siblings(target, d, syntax))
```

If true: `code = "rename.sibling_collision"`, severity = Error, primary = target name range, labels = [(collider name range, "existing binding")]. Scope-binding parameters collide with other parameters in the same modeled scope. Plain `let` bindings collide only with another plain `let` in the same `SourceFile` or `BlockExpr` container; a block-local `let` may legally shadow an enclosing lambda or let-paren parameter.

#### Capture — forward pass

Detects: existing references to *target* would post-rename re-resolve to a closer `new_name` binding.

```
for d in defs where d.name == new_name:
    if target.scope is strict ancestor of d.scope (via enclosing chain):
        emit rename.capture (forward)
```

The pipeline does not record per-call *lexical* scopes — only `resolved_scope` (where the binding lives). Worst case: a rewritten call's lexical position is the deepest descendant of `target.scope`. Any `new_name` binding strictly between `target.scope` and that depth would intercept the call after rename. The forward pass scans all such descendant defs; some flagged defs may not be on the actual call's chain (false positive), but no real captures escape.

Diagnostic shape: severity = Error, primary = target *def* identifier range (not a specific call site — the analysis cannot identify which rewritten call is under the intercepting def's lexical chain without per-call lexical scope data; see §9.6), labels = [(intercepting def's identifier range, "would intercept renamed references in this subtree")].

#### Capture — converse pass

Detects: existing references to a *different* `new_name` binding would post-rename re-resolve to the renamed target.

```
for c in calls where c.callee == new_name:
    if c.resolved_scope is ancestor-or-equal of target.scope (via enclosing chain):
        if target is not visible at c's source position under sequential let rules:
            skip
        # This call previously resolved to its own new_name binding.
        # After rename, target.scope (which now binds new_name) may sit
        # between the call's lexical position and c.resolved_scope, so
        # the call re-resolves to target.
        emit rename.capture (converse)
```

Same conservative rationale: the precise determination requires knowing the call's lexical scope (not recorded); the safe overcounting check uses ancestor-or-equal of `target.scope`, then applies the same source-order/container visibility gate used for edit planning.

Diagnostic shape: severity = Error, primary = converse call site, labels = [(target name range, "renamed binding would intercept")].

#### Shadow

```
let outer = resolve_innermost(parent_of(target.scope), new_name, defs, enclosing)
```

If `outer.is_some()`: the rename would shadow `outer` (the rename target now binds `new_name` at `target.scope`, eclipsing the previously-visible outer binding). Shadow is legal but worth flagging.

Diagnostic shape: `code = "rename.shadow"`, severity = Warning, primary = target name range, labels = [(outer def range, "shadowed binding")].

Note: shadow and converse-capture are related. Shadow flags the rename's effect on *outer reference resolution* (the outer `new_name` is no longer reachable from `target.scope`'s descendants). Converse-capture flags the rename's effect on *existing call rewrites* (calls to `new_name` outside the target's scope chain are unaffected; calls inside are intercepted). They can co-occur; emitting both is correct.

### 5.7 Diagnostic codes summary

| Code | Severity | Meaning |
|---|---|---|
| `rename.no_target_at_offset` | Error | Input offset doesn't land on a def's identifier range |
| `rename.sibling_collision` | Error | new_name already bound in target's scope |
| `rename.capture` | Error | Forward or converse capture detected (label distinguishes which) |
| `rename.shadow` | Warning | Rename shadows an outer new_name binding |
| `rename.no_op` | Info | new_name == target.name; no edits emitted |

**Note**: lexical validation of `new_name` (is it a valid identifier per the lambda grammar?) is *not* the rename consumer's responsibility in v1. The consumer produces edits with whatever string is passed; if the result is unparseable, the parser's own diagnostics surface that. This keeps the rename package decoupled from lexer specifics. Editors that want pre-flight identifier validation should run their own check before calling `plan_rename`.

## 6. Conflict semantics worked examples

All examples use the lambda example's actual grammar: `let name = expr\n` at top level, `\param. body` for lambdas, `f x` for application, `let f (x) = body` for let-paren parameters. No arithmetic operators, no `let ... in`, no semicolons.

### 6.1 Smoke (no conflict)

Source: `let f = \x. x\nlet result = f (f y)\n`
Rename: target = `Def("f", TopScope, ...)` at the first `let`, new_name = `fff`.
Edits: def site (`f` after `let`) + two call references (the `f`s inside `f (f y)`), all rewriting `f → fff`.
Diagnostics: empty.

### 6.2 Sibling collision

Source: `let f = a\nlet g = b\n`
Rename: target = `f`, new_name = `g`.
Sibling-def fires (both at TopScope). Edits are still computed; editor decides whether to override.

### 6.3 Forward capture

Source: `let h = \f. \g. f g\n` — outer lambda param `f`, inner lambda param `g`; rename target = outer `f`, new_name = `g`.

`target.scope` is the outer `LambdaScope(...)`. The inner lambda pushes its own `LambdaScope(inner_start, inner_end)` with an `enclosing` edge to the outer scope (per `callers.mbt:211`), giving us a Def `Def("g", InnerLambdaScope, ...)`. That inner scope is a strict descendant of `target.scope`.

Before rename, the inner body `f g` has `f` resolved to the outer param and `g` resolved to the inner param. After renaming the outer `f` to `g`, the rewritten reference (now spelled `g`) would still bind to the inner parameter via lexical lookup — not to the renamed outer param. The rename's target reference is captured by an unrelated binding.

Forward-pass fires: there exists a `new_name` def at a strict descendant of `target.scope`. Edits are still computed; the diagnostic flags the unsafe rewrite for editor display.

Note: a plain top-level `let g = ...` does *not* create a new scope (per `callers.mbt:238`, only `LetDef` with a `ParamList` pushes a frame). So the forward-capture trigger requires a nested *lambda* or a *let-paren*, not a plain non-parametric `let`. Plain-let bindings in the same scope as the target trigger sibling-def (§6.2) instead.

### 6.4 Converse capture

Source: `let g = a\nlet h = \f. f g\n`
Rename: target = `f` (lambda param, scope = `LambdaScope(...)`), new_name = `g`.

There's a call `c = Call("g", TopScope, ...)` from the body `f g`. `c.resolved_scope == TopScope` is an *ancestor* of `target.scope`. The converse pass fires: after rename, the parameter (now named `g` at `LambdaScope(...)`) sits between the call's lexical position and `TopScope`, so the call re-resolves to the parameter.

Shadow also fires here (the rename shadows outer `let g`). Both diagnostics are emitted; both are correct expressions of the same underlying meaning shift, viewed from different angles (call-site rewrite vs binding reachability).

### 6.5 Shadow without converse capture

Source: `let g = a\nlet h = \f. f\n` — rename target = lambda `f` in the second let, new_name = `g`.
target.scope = `LambdaScope(...)`. resolve_innermost(parent = TopScope, "g") finds outer `let g`. Shadow diagnostic emitted (Warning, not Error — legal but flagged). No converse-capture because the lambda body `f` never references `g`.

### 6.6 Sequential top-level self-reference

Source: `let f = \x. f x\n`
Target: `f` at TopScope. The lambda module uses sequential, non-recursive
top-level semantics, so the reference inside the definition's own initializer is
not bound to that same `f`.
Edits: def site `f` (after `let`) only.
Diagnostics: empty (no collision).

## 7. Test fixtures

Fixtures in `examples/lambda/src/rename/rename_test.mbt` use the lambda example's actual grammar (`let name = expr\n` chains; `\x. body` lambdas; `f x` application; `let f (x) = body` let-paren).

1. **Smoke (top-level let)** — `let f = \x. x\nlet r = f (f y)\n` → rename `f → fff`. Verify three edits (def site + two body references), no diagnostics.
2. **Sibling collision** — `let f = a\nlet g = b\n` → rename `f → g`. Verify Error diagnostic, edits still produced.
3. **Forward capture (nested lambda)** — `let h = \f. \g. f g\n` → rename outer `f → g`. Verify Error diagnostic with `code = "rename.capture"` and forward label (inner lambda's `g` parameter would intercept the rewritten reference).
4. **Converse capture + shadow** — `let g = a\nlet h = \f. f g\n` → rename param `f → g`. Verify Error (`rename.capture` converse) AND Warning (`rename.shadow`) — both fire on this fixture.
5. **Shadow without converse-capture** — `let g = a\nlet h = \f. f\n` → rename param `f → g`. Verify Warning diagnostic only (shadows outer `g`; no call sites affected because body doesn't reference `g`).
6. **Sequential top-level self-reference** — `let f = \x. f x\n` → rename `f → fff`. Verify only the def-site `f` is rewritten.
7. **Let-paren parameter rename** — `let f (x) = x\n` → rename param `x → y`. Verify two edits (param def site + body reference), no diagnostics (parameter rename in same scope).
8. **No-op** — rename `f → f`. Verify no edits, single Info diagnostic.
9. **Offset miss** — offset inside whitespace or on the `let` keyword. Verify `rename.no_target_at_offset` Error, no edits.
10. **Name-range correctness (meta)** — for each binding kind (LetDef, lambda param, let-paren param), verify the def-site edit's `(start, end)` is the identifier-token range, not the enclosing-node range.
11. **Let-paren repeated name** — `let f (f) = f\n` → rename the parameter `f → g`. Verify the function-name binding is not edited.
12. **Top-level source order** — `let a = f\nlet f = z\nlet b = f\n` → rename the later `f`. Verify the earlier free reference is not rewritten.
13. **Sequential top-level self-reference** — `let f = f\nlet g = f\n` → rename the first `f`. Verify the initializer `f` is not rewritten but the later reference is.
14. **Sequential duplicate top-level name** — `let f = a\nlet f = f\nlet g = f\n`. Verify the second definition's initializer sees the previous `f`, and later references see the second `f`.
15. **Block-local initializer** — `let h = \x. { let x = x; x }\n`. Verify the block binding does not rewrite its own initializer.
16. **Block-local body reference** — `let h = \x. { let y = x; y }\n`. Verify a unique block-local binding edits its body reference.
17. **Block-local visibility boundary** — `let h = { let x = a; x } x\n`. Verify the block binding does not rewrite the trailing reference outside the block.
18. **Duplicate let-paren parameter slots** — `let f(x, x) = x\n`. Verify each parameter is targetable by its own identifier range and the body reference belongs to the later duplicate slot.
19. **Shadow source order** — `let h = \f. f\nlet g = a\n`. Verify renaming `f → g` does not warn about shadowing a later top-level binding.
20. **Converse-capture source order** — `let h = g\nlet f = a\n`. Verify renaming `f → g` does not emit `rename.capture` for the earlier unresolved `g`.
21. **Block-local let shadow** — `let h = \x. { let y = a; y }\n`. Verify renaming block-local `y → x` does not emit `rename.sibling_collision`.

## 8. Out of scope for v1

- **Curried let-paren / nested-ParamList renames**: `let f (x) (y) = ...` — the extractor doesn't model these as nested scopes (`callers.mbt:241`). Renaming within them is undefined behavior in v1; document and skip.
- **Let-paren-bound self-reference**: `let f (x) = f x` — interaction between let-paren parameter scope and top-level sequential visibility is subtle; defer.
- **Cross-file rename**: lambda example has no module system.
- **Undo construction**: rename returns edits; the editor builds undo from the inverse edits or from `TextDelta`-style retain/insert/delete tracking. Not the analysis layer's concern.
- **Preview snippets**: editor concern.
- **Optimization fast path** for top-level renames using `callers_of`'s strict-filter index. YAGNI in v1; raw filter on `calls` from `facts()` is `O(calls)` which is fine.

## 9. Why not (alternatives considered)

### 9.1 Extend `visible_from` to return `Def?` instead of `Bool`

Would make capture detection trivially correct in the pipeline. Rejected: re-opens the Datalog-deferral argument from the predecessor spec §7 — once visibility carries binding identity, the same engine constraint (insert-only relations) applies, and the rename consumer would need either eager rebuild semantics (current) or wait for Family A (deferred). Keeping visibility membership-only preserves the deferral.

### 9.2 Add shadowing to the pipeline (e.g., `resolve_innermost` as a `CallersPipeline` method)

Considered. Rejected: rename is the only consumer that needs binding identity (callers' UI use case is "what calls what," not "which binding wins"). Adding a Memo + Observer for shadowing semantics expands the GC-anchor surface (three Observers becomes four) for one consumer. Keeping `resolve_innermost` client-side keeps the pipeline's responsibility tight.

### 9.3 Put `plan_rename` in the callers package

Rejected: callers is a query projection (what calls what, what's visible). Rename is mutation planning. Combining them muddies the responsibility map (Principle 3 from the user's design principles: "Map existing responsibilities before designing new ones"). Two packages with a clean dependency edge is cleaner.

### 9.4 Use `extract_facts` directly from rename, skip `CallersPipeline::facts()`

Rejected: `extract_facts` is `pub` and reusable, but calling it per rename invocation re-walks the syntax tree — throwing away the cached `facts` Memo. The pipeline already maintains incremental cached facts; the rename consumer should read them. The `facts()` accessor is the minimal exposure of that cache.

### 9.5 Add `name_start`/`name_end` to `Def`

Accepted during PR review. The original rename-only syntax scan could disambiguate binding kind, but not repeated parameter slots with the same spelling inside one `ParamList`. Storing the identifier-token range on `Def` preserves the existing containing-node `start/end` fields while giving every binding a stable clickable/editable range.

### 9.6 Extend `Call` with lexical scope (the precision fix for capture conservatism)

Considered. Deferred. The forward-capture and converse-capture passes are conservative because `Call` records only `resolved_scope` (where the binding lives), not lexical scope (where the call is written). With lexical scope per call, capture detection could pinpoint which specific call sites are affected, eliminating false positives.

Adding lexical scope is a small extractor change in `callers.mbt` — push the current top-of-stack scope id onto `Call` at construction time (`callers.mbt:270` area). Compatibility cost is one new field and one extractor line.

Not done in v1 because:
- The conservative analysis is sound; only false-positive noise is at stake.
- Adding the field cascades into Tier 1+ semantic tests (snapshot-based) and the `Call` struct's public interface.
- Editor UX needs to be observed first — if reviewers find false positives acceptable, the precision is YAGNI.

Promotion criterion: if real-world rename usage produces too many false-positive capture warnings, add `lexical_scope: ScopeId` to `Call` and tighten both capture passes to filter by lexical chain inclusion.

## 10. Risks

- **Capture-check overcounting noise**: conservative descendant scan emits false positives when the actual call's lexical chain doesn't pass through the flagged def. Mitigation: editor UI presents conflicts as "review before applying"; not blocking. Long-term fix: lexical-scope-per-call would require an extractor pass extension — punted to a follow-up.
- **Binding range API churn**: `Def` now carries both containing-node and identifier-token ranges. Mitigation: generated interfaces and callers tests pin the field shape, while rename fixtures 10, 11, and 18 cover the ranges that feed edits.
- **Diagnostic schema coupling to editor**: the codes (`rename.capture`, etc.) become an implicit interface. Mitigation: document codes in this spec; the editor consumer's choice to dispatch on codes is its responsibility.
- **`pipeline.facts()` defensive-copy cost**: every rename invocation pays an `O(defs + calls + enclosing)` copy. Mitigation: ranges are typically small (10s to 100s of items per file); copy cost is dominated by the rename's own work. If profiling shows it hot, expose a `facts_views() -> (ArrayView[Def], ...)` instead.

## 11. Decision record

This spec is recorded by [ADR: Lambda Rename Consumer](../../decisions/2026-05-20-lambda-rename-consumer.md). The architectural decision *not* to extend the pipeline with shadowing semantics is documented in §9.1–§9.2.

If the conservative capture rule (§5.6) proves too noisy in practice, a follow-up ADR may codify a revised conflict-severity policy. Until then, the spec stands as the design record.
