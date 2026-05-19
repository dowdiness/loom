# Tier 1+ callers projection: `visible_from` via Memo

**Status:** Draft (pending user approval). Spec for the Tier 1+ extension of the
`examples/lambda/src/callers/` projection.

**Branch:** `feat/lambda-callers-escalation`.

**Predecessor:** `loom#126` (squash `4604409`) shipped Tier 1 — scope structure
(`ScopeId`, `Def.scope`, `Call.resolved_scope`, `Call.is_call_position`).

**Successor (anticipated):** a rename + conflict-detection consumer of this
projection, scoped as a follow-up PR.

## 1. Problem

The Tier 1 `callers/` projection ships scope-aware extraction but exposes only
`callers_of(name)` and `defs_of(name)`. The first named follow-up consumer
(rename-across-scope **with conflict detection**) needs a third query: "is name
`n` visible from scope `s`?" — i.e., does any binding `n` exist in `s` or any
enclosing scope. Conflict detection asks this against a candidate new name to
catch capture and shadow conflicts.

The naive Memo implementation per query is `O(depth × bindings)`. A pre-built
index gives `O(1)` per query. The decision is *which* pre-built index.

## 2. Constraint that shapes the design

The `@incr` Datalog engine (`Relation`, `Rule`, `Runtime::fixpoint`) is
**insert-only across revisions**. Verified in `incr/cells/internal/kernel/fixpoint.mbt:39-46`:
`drain_delta` adds delta into current; no clear/reset of `current` happens
between fixpoint calls; no retract API exists on `Relation` or
`FunctionalRelation`. The research doc
`incr/docs/research/relation-delta-observer-design.md:25-28` describes
"rows disappear when a rule no longer fires" but this is aspirational —
no engine machinery implements it, and no test exercises it.

Consequence: Datalog facts populated from a Memo-driven extraction (Defs,
Calls, Enclosing edges) would **leak across edits**. A rename `f → fff`
would leave `Def("f", TopScope)` in `current` forever; the Visible relation
would incorrectly report `f` as visible in all scopes that ever held it.

## 3. Decision: ship `visible_from` as a pure Memo, not as a Datalog projection

A `Memo[HashMap[(ScopeId, String), Unit]]` answers `visible_from(scope, name)`
in `O(1)` per query, recomputes from scratch each revision (no leak across
edits), requires no new infrastructure, and clears all engine-related
correctness concerns trivially.

Datalog re-escalates for this codebase **when the engine ships retract**
(`Relation::subscribe_delta` / net-delta machinery, currently "Family A" in
the research doc). At that point, structural editor facts become a natural
Datalog target. See [§7. Why not Datalog yet](#7-why-not-datalog-yet).

## 4. Architecture

Single pipeline on one private `@incr.Scope` rooted at `parser.runtime()`.
Today's structure extended with one new Memo and one new public method:

```
parser.syntax_tree() ─┐
                      ▼
             facts_memo (extended shape)
                ├─→ callers_index (today's filter, unchanged semantics)
                └─→ visibility_memo (new)
                                 │
                                 ▼
                       3 persistent Observers
                       (facts, callers, visibility)
                                 │
                       Scope::dispose() cascades
```

Three Observers on three Memos. Same `Scope`, same `Runtime`. No new
Relations, no Rule, no `fixpoint()` calls.

## 5. Components

### 5.1 Extraction (extended)

`collect_in` walker takes a new accumulator parameter
`enclosing : Array[(ScopeId, ScopeId)]` and emits a `(child, parent)` edge
immediately before each frame push:

- LambdaExpr frame push (`callers.mbt:206` today): edge
  `(LambdaScope(start, end), stack[top].id)`.
- LetDef-with-ParamList frame push (`callers.mbt:245` today): edge
  `(LambdaScope(start, end), stack[top].id)`.

Stack bottom is always `TopScope` (initialized at `callers.mbt:284`), so
every outermost LambdaScope gets an edge to `TopScope`. Nested scopes get
edges to their immediate enclosing LambdaScope.

Two public extraction functions:

- `extract_facts(root) -> (Array[Def], Array[Call])` — **kept verbatim** as a
  wrapper that drops the enclosing array. The 23 existing tests use this
  signature and do not change.
- `extract_facts_full(root) -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)])` —
  `pub` so blackbox tests in `callers_test.mbt` can exercise it directly. Used
  by the pipeline's `facts_memo`. Not part of the consumer-facing API — the
  pipeline (`callers_of`, `defs_of`, `visible_from`) is the recommended surface.

### 5.2 Visibility build

```moonbit
pub fn build_visibility(
  defs : Array[Def],
  enclosing : Array[(ScopeId, ScopeId)],
) -> @hashmap.HashMap[(ScopeId, String), Unit]
```

Algorithm:

1. Collect all scopes from `defs.map(d => d.scope)` ∪ `enclosing.flat_map((c,p) => [c, p])`.
2. Build `parent : HashMap[ScopeId, ScopeId]` from `enclosing` (single parent
   per child by construction; if a duplicate appears, first wins —
   defensive against malformed input).
3. Build `own : HashMap[ScopeId, Array[String]]` from `defs`.
4. For each scope `s`, walk up the parent chain. At each step `s'`, union
   `own[s']`'s names into the result map keyed by `(s, name)`. Memoize each
   scope's "fully-built visibility name set" to avoid quadratic re-walks
   along shared chains.

Result: `HashMap[(ScopeId, String), Unit]` where `.get((s, n)).is_some()`
means "binding `n` exists in `s` or any enclosing scope."

Complexity: `O(|defs| + Σ scope_depths)`. Bounded by tree nesting depth.

### 5.3 Pipeline struct

```moonbit
pub struct CallersPipeline {
  priv scope : @incr.Scope
  priv facts_observer
    : @incr.Observer[(Array[Def], Array[Call], Array[(ScopeId, ScopeId)])]
  priv callers_observer
    : @incr.Observer[@hashmap.HashMap[String, Array[Call]]]
  priv visibility_observer
    : @incr.Observer[@hashmap.HashMap[(ScopeId, String), Unit]]
}
```

The `rt` field is removed (no consumer uses it now that `defs_of` reads
through `facts_observer`).

### 5.4 Public API

| Method | Reads via | Semantics |
|---|---|---|
| `callers_of(name) -> Array[Call]` | `callers_observer.get()` | Unchanged from Tier 1. Returns Calls with `is_call_position && resolved_scope == TopScope && callee == name`. Defensive `.copy()` on the bucket. |
| `defs_of(name) -> Array[Def]` | `facts_observer.get()` | Unchanged semantics. Reshape: was `rt.read(facts)`, now `facts_observer.get()` — same data, explicit GC anchor. |
| **`visible_from(scope, name) -> Bool`** | `visibility_observer.get()` | NEW. Returns true iff `n` is bound in `scope` or any enclosing scope. |
| `dispose() -> Unit` | — | Unchanged. `scope.dispose()` cascades to all three observers + owned Memos. Idempotent. |

### 5.5 ScopeId Hash derive

`callers.mbt:40` changes:

```moonbit
- pub(all) enum ScopeId {
-   TopScope
-   LambdaScope(Int, Int)
- } derive(Eq, Debug)
+ pub(all) enum ScopeId {
+   TopScope
+   LambdaScope(Int, Int)
+ } derive(Eq, Hash, Debug)
```

Required because `HashMap[(ScopeId, String), Unit]` needs `(ScopeId, String) : Hash`.
Repo precedent: `egraph/examples/lambda-opt/lang.mbt:4` derives `Hash` on the
same enum-with-payload shape.

## 6. Invariants and caveats

1. **`Visible(scope, name)` does not model shadowing.** It means "some
   binding `name` exists in `scope` or any enclosing scope." Sufficient for
   conservative conflict detection (rename PR will use it to detect capture
   conflicts); insufficient for resolution. A future "innermost binding for
   `(scope, name)`" API would be a separate Memo.

2. **TopScope is implicitly the root of every chain.** TopScope is never a
   child of an Enclosing edge. `visible_from(TopScope, name)` = "is `name` in
   TopScope's own bindings."

3. **`callers_of` preserves Tier 1 exactly.** The rename test at
   `callers_test.mbt:135-142` asserts `callers_of("f").length() == 1` after
   renaming `f → fff` — a `Visible`-derived implementation would say
   `Visible(TopScope, "f") = false` and the test would flip. `callers_index`
   continues to use `resolved_scope == TopScope` filtering, not `Visible`.

4. **BlockExpr does not open a new scope.** Inherited caveat from Tier 1
   (`callers.mbt:22`). Visibility inherits this: `{ let f = 2; f x }` reports
   `f` as visible at the enclosing scope, not at a fresh block scope.

5. **Three Observers, one Scope.** Each public method touches one observer
   directly. Memos compute lazily on first `observer.get()`; subsequent reads
   reuse cached values until inputs invalidate. `facts_observer` explicitly
   anchors `facts_memo` — fixes a latent GC gap in today's code at
   `callers.mbt:361` where only `index` was observed, leaving `facts`
   vulnerable to `rt.gc()` before the first read.

## 7. Why not Datalog yet

Three reasons, in order of weight:

1. **Engine constraint** (§2): monotonic relations leak structural facts
   across edits. The `Visible` query would return stale data for any name
   that ever existed in any revision.

2. **The Tier 1+ trigger's named win was incrementality across edits**
   (per the escalation framing in the task instructions). Engine constraints
   make that win structurally unavailable today. The remaining argument —
   "establish the canonical Datalog idiom in this codebase" — does not
   outweigh adding new infrastructure for a single Bool query.

3. **Memo answers the consumer's read pattern with strictly less machinery.**
   No `Hash` bound on facts, no rule semantics to reason about, no fixpoint
   convergence cost, no in-Memo side effects, no GC chain that doesn't
   actually GC-anchor (Datalog Relations have empty `gc_dependencies` —
   would require explicit `Scope::add_cell_ids` registration as a parallel
   mechanism).

Where Datalog **does** shine in this codebase today (monotonic by design):

- **Memo Event Observation visualization tap** (ADR 2026-05-17, queued on
  the incr side per the task instructions). Recompute events are
  monotonic by design — they never retract. "What triggered this chain"
  is a natural transitive query.
- **Pre-built classification indexes** built once at grammar-definition
  time (`IsExpr(kind)`, `IsCallSite(node)`).
- **Cross-file/cross-language reference indexing** within a session.
- **Reachability from fixed entry points** for unused-code detection.

After Family A (`Relation::subscribe_delta` / engine retract) lands,
structural editor facts — Defs, Calls, Enclosing — become a natural
Datalog target. The rename + conflict detection consumer's full
implementation should be revisited at that point.

See §10 for resolution timeline.

## 8. Tests

Existing 23 tests in `examples/lambda/src/callers/callers_test.mbt` continue
to pass without modification (`extract_facts` signature preserved).

New tests for `visible_from` (snapshot-based, no fixpoint determinism
concerns):

1. **TopScope binding visible from nested LambdaScope.** `let f = 1` plus
   `\x. f x` → `visible_from(LambdaScope of x, "f") == true`.
2. **LambdaScope param visible inside its body, NOT outside.**
   `\x. x` → `visible_from(LambdaScope, "x") == true`,
   `visible_from(TopScope, "x") == false`.
3. **Nested visibility through ancestor chain.**
   `\x. \y. x y` → `visible_from(inner LambdaScope, "x") == true`.
4. **Shadowing caveat is documented behavior, not error.**
   `let f = 1\n\f. f` → both top-level `f` and lambda param `f` produce
   `defs_of("f").length() == 2`, and `visible_from(LambdaScope, "f") == true`.
   The test name explicitly says "shadowing not modeled — visibility is
   conservative."
5. **Unknown ScopeId returns false.**
   `visible_from(LambdaScope(99999, 99999), "anything") == false`.
6. **Malformed lambda with no param token.**
   `\. body` → frame pushed with no Def, but enclosing edge still emitted;
   `visible_from(empty LambdaScope, "name_in_top_scope") == true`.
7. **Let-paren parameters visible inside body.**
   `let f(x, y) = x y` → `visible_from(LambdaScope of f, "x") == true`,
   `visible_from(LambdaScope of f, "y") == true`.

Estimated 6-8 new test cases.

## 9. Code changes (file-by-file)

| File | Change | Approx LOC |
|---|---|---|
| `examples/lambda/src/callers/callers.mbt` | Hash derive; extend `collect_in` to emit enclosing edges; new `extract_facts_full`; new `build_visibility`; new pipeline fields and observers; new `visible_from` method; `defs_of` reshape; drop `rt` field | +60-90 |
| `examples/lambda/src/callers/callers_test.mbt` | Add 6-8 `visible_from` test cases | +30-50 |
| `examples/lambda/src/callers/pkg.generated.mbti` | Regenerated by `moon info` after the source change | auto |
| `docs/plans/2026-05-19-callers-visible-from.md` | This file | new |
| `docs/README.md` | Add link to this file under Active Plans | +1 |

Total: ~100-150 lines. **Medium band** per the project's process calibration
(plan → implement inline → Codex review → PR).

## 10. Resolution timeline

| Step | When |
|---|---|
| Spec approval | This PR cycle |
| Implementation + 6-8 new tests, all 23 existing tests pass, `moon check -w @a` clean | This PR |
| Codex post-implementation review on the implementation | Before requesting human review |
| PR merges to `loom/main` | After CI green |
| Rename + conflict-detection consumer PR | Separate PR — consumes `visible_from` |
| Datalog re-escalation for this projection | Gated on engine retract / Family A landing in `dowdiness/incr`. Not blocked by anything in this PR. |

## 11. Out of scope

- Engine retract / `Relation::subscribe_delta` / Family A. Tracked in `dowdiness/incr`.
- ID stability for `Def`/`Call`/`LambdaScope` (pain point #1 from the original prototype). Deferred; design here does not foreclose interned ScopeIds later.
- Migrating `views.mbt:39-41` `LambdaExprView::param()` from `find_token` to
  `ident_after_lead`. Gated on a third consumer per the loom skill.
- Bench harness for `visible_from`. The honest perf framing is "same as Memo
  recompute per edit"; no separate bench unless a consumer surfaces a hot
  query path.
- `children_iter` / lazy SyntaxNode iteration (ROADMAP #59/#60). Independent perf
  work.

## 12. Decision record

This plan documents a **principled non-escalation** to Datalog for this
projection. The Tier 1+ trigger fired (second consumer in scope), but the
engine constraint discovered during design made the originally-claimed win
unavailable. A future ADR may be warranted when Family A lands and Datalog
becomes the natural target — at that point, this plan's §7 reasoning should
be revisited and either superseded or confirmed as still applicable to other
projections in the codebase.

No new ADR is added by this plan itself. The decision recorded here is
scoped to the `callers/` projection and does not change architecture
elsewhere.
