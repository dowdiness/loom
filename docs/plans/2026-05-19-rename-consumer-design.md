# Rename + conflict-detection consumer of `visible_from`

**Status:** Draft (pending user approval). Spec for the first named follow-up consumer of the Tier 1+ callers projection (`visible_from`).

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
- **`Def.start/end` is the enclosing-node range, not the identifier-token range.** Verified at `examples/lambda/src/callers/callers.mbt:205, :227, :248` — for let definitions, lambda parameters, and let-paren parameters respectively, `start/end` is the wider AST node. Edits must target the identifier subrange.
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
fn locate_target(defs : Array[Def], offset : Int) -> Def?
```

Filters `defs` by `d.start <= offset < d.end`; on tie, returns the innermost (smallest `d.end - d.start`; tie-break by max `d.start`). Returns `None` if no def contains the offset.

The innermost-wins rule resolves cases like `let f (x) = ...` where the let-paren node contains the param node — clicking on `x` should target the parameter, not the let.

### 5.3 Name-range extraction (the Codex BLOCK F fix)

```
fn name_range_of(def : Def, syntax : SyntaxNode) -> (Int, Int)
```

Walks the syntax tree from the node containing `def.start..def.end` to find the identifier token matching `def.name`. Returns the token's byte range. This is the source of every TextEdit's `(start, end)`.

Three call paths based on def's binding kind, detected by inspecting the containing AST node:
- **LetDef**: identifier follows the `let` keyword
- **Lambda parameter** (`\x. body`): identifier follows the `\` lambda introducer
- **Let-paren parameter** (`let f (x) = ...`): identifier is inside the `ParamList`

The helper uses `@seam.SyntaxNode::children()` + `@seam.SyntaxToken::text()` (per `seam/syntax_node.mbt:30`) to walk.

### 5.4 Edit computation

```
fn compute_edits(target : Def, calls : Array[Call], syntax : SyntaxNode, new_name : String)
  -> Array[TextEdit]
```

Edit set:

1. Def-site edit: `TextEdit(name_start, name_end, new_name)` from `name_range_of(target, syntax)`.
2. Reference edits: for each `c : Call` where `c.callee == target.name && c.resolved_scope == target.scope`, emit `TextEdit(c.start, c.end, new_name)`.

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

Walks the parent chain from `scope` upward via `enclosing` edges. At each visited scope `S`, checks whether any `Def` in `defs` has `d.scope == S && d.name == name`. Returns the first match.

`TopScope` has no parent edge — the walk terminates after checking TopScope's bindings.

This is the *only* shadowing-aware operation the rename package needs. It does not propagate back into the pipeline.

### 5.6 Conflict detection

Three checks, each emitting an `@core.Diagnostic` with structured fields. Capture is **two-pass** (forward + converse) — both report under the same `rename.capture` code with distinguishing labels.

#### Sibling-def

```
defs.any(d => d.scope == target.scope && d.name == new_name)
```

If true: `code = "rename.sibling_collision"`, severity = Error, primary = target name range, labels = [(collider name range, "existing binding")].

#### Capture — forward pass

Detects: existing references to *target* would post-rename re-resolve to a closer `new_name` binding.

```
for d in defs where d.name == new_name:
    if target.scope is strict ancestor of d.scope (via enclosing chain):
        emit rename.capture (forward)
```

The pipeline does not record per-call *lexical* scopes — only `resolved_scope` (where the binding lives). Worst case: a rewritten call's lexical position is the deepest descendant of `target.scope`. Any `new_name` binding strictly between `target.scope` and that depth would intercept the call after rename. The forward pass scans all such descendant defs; some flagged defs may not be on the actual call's chain (false positive), but no real captures escape.

Diagnostic shape: severity = Error, primary = nearest target-reference range, labels = [(intercepting def range, "would intercept renamed reference")].

#### Capture — converse pass

Detects: existing references to a *different* `new_name` binding would post-rename re-resolve to the renamed target.

```
for c in calls where c.callee == new_name:
    if c.resolved_scope is ancestor-or-equal of target.scope (via enclosing chain):
        # This call previously resolved to its own new_name binding.
        # After rename, target.scope (which now binds new_name) may sit
        # between the call's lexical position and c.resolved_scope, so
        # the call re-resolves to target.
        emit rename.capture (converse)
```

Same conservative rationale: the precise determination requires knowing the call's lexical scope (not recorded); the safe overcounting check uses ancestor-or-equal of `target.scope`.

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
| `rename.no_target_at_offset` | Error | Input offset doesn't land on a def |
| `rename.invalid_new_name` | Error | new_name isn't a valid lambda identifier |
| `rename.sibling_collision` | Error | new_name already bound in target's scope |
| `rename.capture` | Error | Some descendant scope has new_name; rename intercepts references |
| `rename.shadow` | Warning | Rename shadows an outer new_name binding |
| `rename.no_op` | Info | new_name == target.name; no edits emitted |

## 6. Conflict semantics worked examples

### 6.1 Smoke (no conflict)

Source: `let f = ...; f (f 1)`
Rename: target = `Def("f", TopScope, ...)`, new_name = `fff`.
Edits: def site + two call references, all rewriting `f → fff`.
Diagnostics: empty.

### 6.2 Sibling collision

Source: `let f = ...; let g = ...`
Rename: target = `f`, new_name = `g`.
Sibling-def fires (both at TopScope). Edits are still computed; editor decides whether to override.

### 6.3 Forward capture

Source: `(\f. let g = 1 in f + g)` then a rename at the *outer* lambda param: target = `f`, new_name = `g`.

`target.scope` is the outer `LambdaScope(...)`. The inner `let g = 1` introduces a Def `Def("g", InnerLambdaScope, ...)` whose scope is a strict descendant of `target.scope`. The reference `f` inside the let body had resolved upward to the parameter; post-rename, that reference becomes `g` and would resolve to the inner `let g` instead of the renamed parameter.

Forward-pass fires: there exists a `new_name` def in a descendant of `target.scope`. Edits are still computed; the diagnostic flags the unsafe rewrite for editor display.

### 6.4 Converse capture

Source: `let g = 1 in (\f. f + g)`
Rename: target = `f` (lambda param, scope = `LambdaScope(...)`), new_name = `g`.

There's a call `c = Call("g", TopScope, ...)` from the `+ g` expression. `c.resolved_scope == TopScope` is an *ancestor* of `target.scope`. The converse pass fires: after rename, the parameter (now named `g` at `LambdaScope(...)`) sits between the call's lexical position and `TopScope`, so the call re-resolves to the parameter.

Shadow also fires here (the rename shadows outer `let g`). Both diagnostics are emitted; both are correct expressions of the same underlying meaning shift, viewed from different angles (call-site rewrite vs binding reachability).

### 6.5 Shadow

Source: `let g = ...; (\f. f)` — rename target = lambda `f`, new_name = `g`.
target.scope = `LambdaScope(...)`. resolve_innermost(parent = TopScope, "g") finds outer `let g`. Shadow diagnostic emitted (Warning, not Error — legal but flagged).

### 6.6 Top-level recursive

Source: `let f = (\x. f x)`
Target: `f` at TopScope. The recursive call `f x` resolves to TopScope.
Edits: def site `f` + recursive call `f`. Both rewritten.
Diagnostics: empty (no collision).

## 7. Test fixtures

Nine fixtures in `examples/lambda/src/rename/rename_test.mbt`:

1. **Smoke** — `let f = (\x. x); f (f 1)` → rename `f → fff`. Verify three edits, no diagnostics.
2. **Sibling collision** — `let f = 1; let g = 2` → rename `f → g`. Verify Error diagnostic, edits still produced.
3. **Forward capture** — `(\f. let g = 1 in f + g)` → rename outer `f → g`. Verify Error diagnostic (inner `let g` would intercept the renamed reference).
4. **Converse capture** — `let g = 1 in (\f. f + g)` → rename param `f → g`. Verify Error diagnostic (the renamed `g` parameter intercepts the previously-free `g` reference). Shadow also fires for this fixture.
5. **Shadow without converse-capture** — `let g = 1; (\f. f)` → rename param `f → g`. Verify Warning diagnostic only (shadows outer `g`; no call sites affected).
6. **Top-level recursion** — `let f = (\x. f x)` → rename `f → fff`. Verify both `f` references rewritten.
7. **No-op** — rename `f → f`. Verify no edits, single Info diagnostic.
8. **Offset miss** — offset inside whitespace. Verify Error diagnostic, no edits.
9. **Name-range correctness** — for each binding kind (LetDef, lambda param, let-paren param), verify the edit's `(start, end)` is the identifier-token range, not the enclosing-node range.

## 8. Out of scope for v1

- **Curried let-paren / nested-ParamList renames**: `let f (x) (y) = ...` — the extractor doesn't model these as nested scopes (`callers.mbt:241`). Renaming within them is undefined behavior in v1; document and skip.
- **Let-paren-bound recursion**: `let f (x) = f x` — interaction between let-paren scope and self-reference is subtle; defer.
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

Considered. Rejected for v1: would expand the callers public API and require all existing consumers to adapt. The need is rename-specific — `defs_of` UI consumers ("highlight where this is bound") want the wider node range. A 20-line `name_range_of` helper in the rename package is cheaper than a pipeline-wide API change. May revisit if a second consumer surfaces the same need.

## 10. Risks

- **Capture-check overcounting noise**: conservative descendant scan emits false positives when the actual call's lexical chain doesn't pass through the flagged def. Mitigation: editor UI presents conflicts as "review before applying"; not blocking. Long-term fix: lexical-scope-per-call would require an extractor pass extension — punted to a follow-up.
- **Name-range extraction brittleness**: `name_range_of` depends on the lambda grammar's surface syntax. If the grammar changes (e.g., adding patterns to let definitions), the helper breaks silently. Mitigation: test family 9 covers each binding kind; new kinds added to the grammar must add corresponding tests in the same PR.
- **Diagnostic schema coupling to editor**: the codes (`rename.capture`, etc.) become an implicit interface. Mitigation: document codes in this spec; the editor consumer's choice to dispatch on codes is its responsibility.
- **`pipeline.facts()` defensive-copy cost**: every rename invocation pays an `O(defs + calls + enclosing)` copy. Mitigation: ranges are typically small (10s to 100s of items per file); copy cost is dominated by the rename's own work. If profiling shows it hot, expose a `facts_views() -> (ArrayView[Def], ...)` instead.

## 11. Decision record

This spec captures the design; no ADR is needed because the design fits within the predecessor's architectural envelope (callers pipeline as analysis layer; consumers stack on top without growing the pipeline). The architectural decision *not* to extend the pipeline with shadowing semantics is documented in §9.1–§9.2.

If the conservative capture rule (§5.6) proves too noisy in practice, a follow-up ADR may codify a revised conflict-severity policy. Until then, the spec stands as the design record.
