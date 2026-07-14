# ParserContext Lookahead Rename Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the unconditional parser-state rollback helper from `ParserContext::speculative` to `ParserContext::lookahead` without changing its behavior.

**Architecture:** `ParserContext::lookahead` remains a minimal callback wrapper around `checkpoint()` and `restore()`. It always restores parser-owned checkpoint state after its callback and returns the callback value; conditional parsing that commits on success continues to use an explicit checkpoint/restore pair.

**Tech Stack:** MoonBit; Loom core parser; existing white-box tests; generated `pkg.generated.mbti`; Markdown and JSX example grammars.

## Global Constraints

- Remove `ParserContext::speculative` completely: no alias, deprecation shim, re-export, or remaining caller.
- Do not add conditional-backtracking helpers, grammar IR variants, grammar annotations, or checkpoint fields.
- Preserve the rollback boundary: position, events, parser-added diagnostics, open-node state, reuse cursor/count, and lex mode.
- Do not promise rollback for external closure state, I/O, in-place diagnostic mutation, or parser configuration outside `checkpoint()`.
- Use `moon ide find-references` before the public-symbol edit and `moon ide analyze`/diagnostics after it.
- Run focused tests before and after the implementation; run `moon fmt`, `moon check --warn-list +73`, and `moon info` before review.

---

### Task 1: Pin the public lookahead rollback contract

**Files:**
- Modify: `loom/core/parser_context_wbtest.mbt:168-189,656-673`
- Modify: `loom/core/parser_robustness_wbtest.mbt:234-280,324-399`

**Interfaces:**
- Consumes: the existing `ParserContext::speculative(Self[T, K], () -> R) -> R` declaration.
- Produces: tests that require `ParserContext::lookahead(Self[T, K], () -> R) -> R` and establish unconditional restoration.

- [x] **Step 1: Add a lookahead test beside the direct lex-mode checkpoint test.**

```moonbit
///|
test "lookahead: restores lex mode and preserves callback result" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  ctx.set_lex_mode(7)
  let result = ctx.lookahead(() => {
    ctx.set_lex_mode(42)
    "observed"
  })
  inspect(result, content="observed")
  inspect(ctx.lex_mode(), content="7")
}
```

- [x] **Step 2: Replace the node-stack regression with a lookahead test.**

Keep the existing setup and assertions, but rename the test to `finish_nodes_until: lookahead restores node stack` and invoke `ctx.lookahead`. Its callback starts `KNum` and `KPlus`, calls `ctx.finish_nodes_until(KRoot)`, returns that `Bool`, and the test asserts the returned `true` plus intact `KExpr` and `KRoot` stack order.

- [x] **Step 3: Add position/event and diagnostic lookahead restoration coverage.**

```moonbit
///|
test "lookahead: rewinds position, events, and diagnostics" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let result = ctx.lookahead(() => {
    ctx.emit_token(KNum)
    ctx.error("lookahead error")
    ctx.at_eof()
  })
  inspect(result, content="false")
  inspect(ctx.position, content="0")
  inspect(ctx.peek(), content="Num(1)")
  inspect(ctx.events.length(), content="1")
  inspect(ctx.diagnostics.length(), content="0")
  ctx.finish_node()
}
```

- [x] **Step 4: Add a reuse-cursor lookahead regression.**

Preserve the direct `checkpoint()`/`restore()` regression. Add a separate lookahead test using the same `grammar_one_expr`, old tree, `ReuseCursor`, and parser setup:

```moonbit
let reused = ctx.lookahead(() => {
  ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  ctx.reuse_count
})
inspect(reused, content="1")
inspect(ctx.reuse_count, content="0")
inspect(ctx.position, content="0")
ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
inspect(ctx.reuse_count, content="1")
inspect(ctx.at_eof(), content="true")
```

This proves the cursor is restored as well as the count: the same candidate is reusable after the lookahead callback.

- [x] **Step 5: Run the new focused tests and verify they fail.**


Run from `loom/`:

```bash
rtk moon test -p dowdiness/loom/core --filter '*lookahead*'
```
Expected: compilation failure because `ParserContext::lookahead` does not yet exist.

- [x] **Step 6: Commit the test-first change.**

```bash
rtk git add loom/core/parser_context_wbtest.mbt loom/core/parser_robustness_wbtest.mbt
rtk git commit -m "test(core): specify lookahead rollback"
```

### Task 2: Perform the clean public API cutover

**Files:**
- Modify: `loom/core/parser_events.mbt:208-236`
- Modify: `loom/core/pkg.generated.mbti:308` via `moon info`
- Modify: `examples/jsx/cst_parser.mbt:31-46`
- Modify: `examples/markdown/block_reparse.mbt:490-539`
- Modify: `examples/markdown/cst_parser.mbt:168-178,337-344,650-659,1039-1048`
- Modify: `examples/markdown/list_boundary.mbt:98-109`
- Modify: `examples/markdown/setext_policy.mbt:56-85`

**Interfaces:**
- Consumes: failing tests requiring `ParserContext::lookahead(Self[T, K], () -> R) -> R`.
- Produces: the only public API spelling for unconditional parser-state rollback.

- [x] **Step 1: Use semantic references before editing the exported method.**

Run from `loom/`:

```bash
rtk moon ide find-references ParserContext::speculative
```

Record the declaration and every caller. Do not use `moon ide rename` for this
method: its preview resolves this spelling as the `ParserContext` type and
proposes a type-wide rename. Rename only the method declaration and these
verified call sites with scoped edits:

- `examples/jsx/cst_parser.mbt:38`
- `examples/markdown/block_reparse.mbt:495`
- `examples/markdown/cst_parser.mbt:173,341,653,1042`
- `examples/markdown/list_boundary.mbt:103`
- `examples/markdown/setext_policy.mbt:61,71`
- `loom/core/parser_context_wbtest.mbt:674`

- [x] **Step 2: Preserve the implementation exactly while changing its public name and doc comment.**

```moonbit
///|
/// Run `body` as pure lookahead, then restore checkpointed parser execution
/// state and return the body's result.
///
/// Use for lookahead whose effects are limited to token consumption, events,
/// diagnostic additions, open-node count/stack, reuse cursor/count, and lex
/// mode. It does not roll back in-place diagnostic mutation or parser
/// configuration such as goal sources, goal subsumption checks, or reuse
/// diagnostics.
pub fn[T, K, R] ParserContext::lookahead(
  self : ParserContext[T, K],
  body : () -> R,
) -> R {
  let cp = self.checkpoint()
  let result = body()
  self.restore(cp)
  result
}
```

Keep `checkpoint`, execute body, `restore`, and return order unchanged.

- [x] **Step 3: Update all pure-lookahead callers only.**

Change `ctx.speculative(` to `ctx.lookahead(` in the six listed example files. Do not change explicit `checkpoint()`/`restore()` conditional branch code such as `checkpoint/restore: speculative parse picks successful branch`.

- [x] **Step 4: Generate and inspect the public interface.**


Run from `loom/`:

```bash
rtk moon info
```

Expected interface delta:

```moonbit
pub fn[T, K, R] ParserContext::lookahead(Self[T, K], () -> R) -> R
```

There must be no generated `ParserContext::speculative` declaration.

- [x] **Step 5: Run focused core tests and prove the new behavior compiles and passes.**


Run from `loom/`:

```bash
rtk moon test -p dowdiness/loom/core --filter '*lookahead*'
```

Expected: all lookahead rollback tests pass.

- [x] **Step 6: Commit the source and caller cutover.**

```bash
rtk git add loom/core/parser_events.mbt loom/core/pkg.generated.mbti examples/jsx/cst_parser.mbt examples/markdown/block_reparse.mbt examples/markdown/cst_parser.mbt examples/markdown/list_boundary.mbt examples/markdown/setext_policy.mbt
rtk git commit -m "refactor(core): rename speculative to lookahead"
```

### Task 3: Update the durable API documentation

**Files:**
- Modify: `docs/architecture/generic-parser.md:149-189`
- Modify: `docs/decisions/2026-07-14-lookahead-rollback-boundary.md:1-84`
- Modify: `docs/README.md:64-72,125-140`

**Interfaces:**
- Consumes: the finished `ParserContext::lookahead` public method.
- Produces: documentation whose terminology matches the sole public API and retains the established rollback boundary.

- [x] **Step 1: Update the architecture API list and guidance.**

Replace `ctx.speculative(body)` with `ctx.lookahead(body)` and reword the guidance to begin:

```markdown
Use `ctx.lookahead(body)` for pure lookahead: it restores the checkpointed
execution state documented by `ParserContext::checkpoint`.
```

Retain the warning that it is not a general configuration transaction and the explicit checkpoint/restore guidance for success-committing parses.

- [x] **Step 2: Rename and update the existing ADR.**

Rename its file and title to `2026-07-14-lookahead-rollback-boundary.md` / `# ADR: ParserContext Lookahead Rollback Boundary`. Replace public-API uses of `speculative` with `lookahead`, link this implementation plan, and preserve its state boundary, non-transactional exclusions, issue/PR provenance, and consumer-evidence rule; this is a terminology correction, not a new design decision.

- [x] **Step 3: Update the documentation index.**

Change the ADR summary at `docs/README.md` to name `ParserContext::lookahead`.
Add the active #716 implementation-plan entry to that index with the relative
target `superpowers/plans/2026-07-14-parser-context-lookahead-rename.md`.

- [x] **Step 4: Commit documentation with the API terminology correction.**

```bash
rtk git add docs/architecture/generic-parser.md docs/decisions/2026-07-14-lookahead-rollback-boundary.md docs/README.md docs/superpowers/plans/2026-07-14-parser-context-lookahead-rename.md
rtk git commit -m "docs: name pure parser lookahead"
```

### Task 4: Verify complete cutover and package behavior

**Files:**
- Verify: all files listed in Tasks 1–3

**Interfaces:**
- Consumes: the completed source, test, generated-interface, and documentation cutover.
- Produces: evidence that #716 preserves rollback behavior and leaves no stale public terminology.

- [x] **Step 1: Run semantic API and diagnostics checks.**

Run from the repository root:

```bash
rtk moon ide find-references ParserContext::lookahead
rtk moon ide analyze loom/core
```

Then run from `loom/`:

```bash
rtk moon check --warn-list +73
```

Expected: the method has the intended callers and core has no diagnostics.

- [x] **Step 2: Run affected test suites.**
Run the following commands from their named module directories:

```bash
# cwd: loom/
rtk moon test -p dowdiness/loom/core
# cwd: examples/markdown/
rtk moon test
# cwd: examples/jsx/
rtk moon test
```

Expected: every test passes.

- [x] **Step 3: Format, regenerate, and rerun package verification.**

Run the formatter in each modified MoonBit module, then regenerate and check core:

```bash
# cwd: loom/
rtk moon fmt
rtk moon info
rtk moon check core
# cwd: examples/markdown/
rtk moon fmt
rtk moon check
# cwd: examples/jsx/
rtk moon fmt
rtk moon check
```

Expected: formatters leave intended source, the generated core interface contains only `ParserContext::lookahead`, and all checks pass.

- [x] **Step 4: Verify stale-name absence with a scoped repository search.**

Search `loom`, `examples`, and live API documentation for `ParserContext::speculative` and `ctx.speculative`. Expected: zero matches. Permit historical archive prose that describes prior terminology only if it is clearly historical and not an API reference.

- [x] **Step 5: Commit formatter-generated changes only when present.**

```bash
rtk git add loom/core/pkg.generated.mbti
rtk git diff --cached --quiet || rtk git commit -m "chore(core): refresh generated interface"
```

### Task 5: Review and deliver

**Files:**
- Modify after verification: `docs/superpowers/plans/2026-07-14-parser-context-lookahead-rename.md`
- Move after completion: `docs/archive/completed-phases/2026-07-14-parser-context-lookahead-rename.md`
- Modify: `docs/README.md`

**Interfaces:**
- Consumes: green verification from Task 4.
- Produces: independent-review evidence, a closed issue/PR, and an archived plan that follows the documentation protocol.

- [x] **Step 1: Request independent review from a model different from the implementation model.**

Provide the reviewer the diff and the rollback contract. Require a pass/fail verdict, at most three findings with exact file:line citations, and evidence that it checked caller migration, rollback-on-success, generated interface, documentation, and accidental conditional-parse conversion.

- [x] **Step 2: Resolve all confirmed review findings and rerun the affected focused checks.**

For each confirmed finding, add a behavioral regression test first when the defect changes observable behavior; then make the minimal source correction and rerun its core/example test scope.

- [x] **Step 3: Close the implementation plan according to the documentation protocol.**

After every acceptance criterion has command evidence, set `**Status:** Complete` and add:

```markdown
## Completion

- Issue: [#716](https://github.com/dowdiness/loom/issues/716)
- Verification: focused core, Markdown, JSX, check, format, and generated-interface commands passed.

## Decision record

- No ADR needed: the existing 2026-07-14 rollback-boundary ADR was updated in place; this plan only executes its terminology correction.
```

Move the plan to `docs/archive/completed-phases/2026-07-14-parser-context-lookahead-rename.md` and update its link in `docs/README.md` in the same commit.

- [x] **Step 4: Create the pull request.**

Push `fix/716-parser-context-lookahead`, create a PR with a body containing a literal `Closes #716` line, and include the exact verification commands and independent-review verdict. Follow CI until green.

## Completion

- Issue: [#716](https://github.com/dowdiness/loom/issues/716)
- Pull request: [#717](https://github.com/dowdiness/loom/pull/717)
- Verification: focused core, Markdown, JSX, check, format, generated-interface, docs-health, and CI checks passed.

Decision record:

- Updated ADR: [ParserContext Lookahead Rollback Boundary](../../decisions/2026-07-14-lookahead-rollback-boundary.md) records the public terminology correction and rollback boundary.
