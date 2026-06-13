# ParserContext grammar-author boundary — design

**Issue:** loom#251 — Make ParserContext grammar-author API boundary explicit before stabilization
**Status:** Complete (2026-06-11 — PR #290)
**Date:** 2026-06-12

## Completion note

Implemented by [PR #290](https://github.com/dowdiness/loom/pull/290), which
closed [issue #251](https://github.com/dowdiness/loom/issues/251). The PR
privatized all 14 `ParserContext` parser-state fields, moved the lone
cross-package raw-field white-box test into `loom/src/core/`, regenerated the
interfaces with the `ParserContext` field block collapsed to `// private fields`,
and updated `docs/architecture/generic-parser.md` to document the method-only
grammar-author contract.

Decision record:

- [ADR: ParserContext Grammar-Author Method-Only Boundary](../../decisions/2026-06-13-parsercontext-method-only-boundary.md)

## Problem

`ParserContext[T, K]` (defined in `loom/src/core/parser.mbt`) is the value grammar
authors receive via the `parse_root : (ParserContext[T, K]) -> Unit` callback. It is
declared `pub struct` (not `pub(all)`), so its fields are already *read-only* outside
`core` — but they remain *visible* in `loom/src/core/pkg.generated.mbti`. Visibility
reads as a stable contract, so the intended "grammar code talks to ParserContext through
methods" boundary is **social, not enforced**. Before Loom stabilizes its public API the
contract must be explicit: methods are the grammar-author surface; parser-state fields are
internal implementation detail.

## Decision

Make the grammar-author surface exactly the public methods. Demote **all 14**
parser-state fields to language-enforced `priv`. Keep `ParserContext` a `pub struct`
(the `loom` facade re-exports it via `pub using @core {type ParserContext}`, so `pub` is
sufficient and no facade edit is needed). Do not add escape-hatch accessors preemptively —
if a real grammar-author read need appears later, add a named accessor then with explicit
semantics.

### The 14 fields to privatize

```
spec, token_count, get_token, get_start, get_end, source, position,
events, diagnostics, error_count, open_nodes, reuse_cursor,
reuse_diagnostics, reuse_count
```

This mirrors the existing precedent in the same file: `Checkpoint` is a
`pub(all) struct` whose fields are `priv position` / `priv events_len`. Per-field `priv`
inside a public struct hides the field from the generated interface while keeping the
type name and methods public.

## Audit findings (basis for low compatibility cost)

- **Cross-package non-test reads of raw fields: 0.** Nothing in `incremental`, `pipeline`,
  `viz`, or any example reads these fields outside tests.
- **Cross-package test reads: exactly 1** — `examples/lambda/src/cst_parser_wbtest.mbt:5`
  reads `ctx.open_nodes`. This compiles today only because the field is `pub`. MoonBit
  visibility is package-level, so making the field `priv` in `core` hides it from the
  lambda package's whitebox tests too.
- **Construction:** No struct-literal construction of `ParserContext` anywhere; all callers
  use `ParserContext::new` / `::new_indexed`. Privatizing fields cannot break construction.
- **Core's own whitebox tests** read these fields heavily (`position`×27, `reuse_count`×30,
  `events`×9, …) but they are **same-package** (`core`), so `priv` keeps them compiling.
- **Facade:** `loom/src/pkg.generated.mbti` re-exports the type only
  (`pub using @core {type ParserContext}`); field visibility follows the `core` definition,
  so privatizing in `core` automatically hides fields at the facade.

## Changes

1. **`loom/src/core/parser.mbt`** — add `priv` to each of the 14 fields. Rewrite the struct
   doc comment to state: the stable grammar-author surface is the methods; fields are
   private internal state, not API.

2. **`loom/src/core/parser_wbtest.mbt`** — add the relocated invariant test
   `"finish_node without matching start_node is ignored"` (constructs a fresh ctx, calls
   `finish_node()`, asserts `open_nodes == 0`). It exercises core's `finish_node` underflow
   guard and so belongs to `core`. No equivalent core test exists today, so this is a
   genuine move, not a duplicate.

3. **`examples/lambda/src/cst_parser_wbtest.mbt`** — remove that test (the only cross-package
   raw-field read).

4. **Docs** — update `docs/architecture/generic-parser.md` (9 `ParserContext` mentions) to
   describe the method-only grammar-author contract and mark raw parser state as internal.

## Verification

- `moon info` in `loom/` → regenerate `pkg.generated.mbti`. Expect the `ParserContext` field
  block to disappear; **no** method signatures or trait bounds change.
- `git diff loom/src/core/pkg.generated.mbti` → confirm the diff is *only* field removal
  (API-regression guard per CLAUDE.md — widening a bound or dropping a method would be a
  regression).
- `moon check && moon test` in `loom/` and `examples/lambda/`.
- `moon fmt` before commit.

## Fallback

The all-private `pub struct` shape is confirmed valid by in-module precedent (Codex
design validation, 2026-06-12): `ImperativeParser[Ast]` (`loom/src/incremental/
imperative_parser.mbt:5`) and `Parser[Ast]` (`loom/src/pipeline/parser.mbt:18`) are
already `pub struct` with every field `priv`; their generated `.mbti` renders the body as
`pub struct … { // private fields }`. The expected `ParserContext` `.mbti` diff is the
14-field block collapsing to `// private fields`.

If — against this precedent — `moonc` rejects the shape, **stop and surface that
explicitly**; do not silently switch to an abstract type. The decision is `pub struct` +
per-field `priv`; any deviation is a new design choice for the user.

## Non-goals

- No new accessor methods (no preemptive escape hatches).
- No change to `ParserContext` methods, constructors, or trait bounds.
- No facade (`loom/src/loom.mbt`) edits.
- Not related to #267 / PR #289 (SyntaxNode constructor dedup in `seam`) — different package,
  different concern.

## Acceptance criteria (from #251)

- [x] Stable grammar-author surface explicitly documented (struct doc + arch doc).
- [x] `pkg.generated.mbti` no longer exposes raw parser internals as stable API.
- [x] In-repo examples do not read parser cursor/error fields directly (lambda read removed).
- [x] No new helpers added without a concrete grammar-author use case (none added).
