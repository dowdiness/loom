# Block Reparse Ancestor Widening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reparse the first strict block ancestor that a language explicitly accepts with new candidate context, so Markdown sibling-to-nested list edits retain CST parity.

**Architecture:** `loom/core` enumerates strict reparseable ancestors from innermost to outermost. For each candidate it extracts and lexes the new range, rejects balance failures globally, then asks a context-aware language selector for a reparser. Only selector `None` advances to a parent; every failure after selection returns the existing fallback result. Markdown first probes the actual strict candidate selected for the boundary regression, then derives its candidate-level ownership rejection from the observed old/new range and token prefixes.

**Tech Stack:** MoonBit; `@dowdiness/loom/core`; `@dowdiness/seam`; Markdown, JSON, and Lambda example grammars.

## Global Constraints
- Preserve the single-edit strict-interior rule: `edit.start > block.start()` and `edit.start + edit.new_len < block.end() + edit.delta()`.
- Candidate order is innermost to outermost.
- Per candidate: extract → lex → balance; balance failure returns `None` without widening.
- Only selector `None` permits a parent candidate; parse/tree-build/splice/diagnostic failures return `None` without widening.
- Pass old `SyntaxNode`, new candidate `String`, and `Array[TokenInfo[T]]` to each selector.
- Do not add a Markdown-specific fresh parser or duplicate list grammar.
- Preserve JSON and Lambda behavior by ignoring the new context in their selectors.
- `moon check examples/markdown` after every MoonBit edit; use the exact targeted test before the package suite.

---

### Task 1: Pin Core Candidate-Widening Semantics

**Files:**
- Modify: `loom/core/parser_robustness_wbtest.mbt:92-183`
- Modify: `loom/core/block_reparse.mbt:94-123,345-418`

**Interfaces:**
- Consumes: existing `find_reparseable_ancestor`, `reparse_block`, `BlockReparseSpec`, and `test_spec` fixtures.
- Produces: white-box coverage for selector-decline widening and no-widen-after-selection failure; an internal ordered candidate enumerator for `reparse_block`.

- [ ] **Step 1: Add failing core tests for explicit decline and selected-parser failure**

Add nested `KExpr` test grammars in `parser_robustness_wbtest.mbt`. Build an old CST with a strict inner `KExpr` inside an outer `KExpr`. Configure `is_reparseable` for both. In the selector, record the candidate starts and return `None` for the inner candidate and `Some(parse_expr)` for the outer candidate. Assert the reparse result is `Some` and the selector observed `[inner.start(), outer.start()]` in that order.

Add a paired test whose inner selector returns `Some(fn(ctx) { () })`, producing no replacement node. Assert `reparse_block(...) is None` and the selector saw only the inner candidate. This distinguishes an explicit selector decline from a selected parser execution failure.

- [ ] **Step 2: Run the new core tests before implementation**

Run: `rtk moon test loom/core --filter "reparse_block selector decline widens to parent"`

Expected: FAIL because the current `reparse_block` stops after the first `get_reparser == None`.

Run: `rtk moon test loom/core --filter "reparse_block selected failure does not widen"`

Expected: PASS on the current implementation and after widening; the current core already returns `None` after `parse_block_isolated` produces no node. This test pins the rule that widening is selector-only.

- [ ] **Step 3: Implement ordered candidate enumeration and selector context**

In `loom/core/block_reparse.mbt`, add an internal helper with this shape:

```moonbit
fn find_reparseable_ancestors(
  tree : @seam.SyntaxNode,
  edit : Edit,
  is_reparseable : (@seam.RawKind) -> Bool,
) -> Array[(@seam.SyntaxNode, Array[Int])]
```

Start at `tree.find_at(edit.start)`, walk `.parent()`, apply the current strict-interior predicate, and append each candidate with the existing `build_physical_path` result. Keep `find_reparseable_ancestor` as the first-candidate public helper by returning the first entry of this ordered array.

Change `BlockReparseSpec.get_reparser` to:

```moonbit
get_reparser : (
  @seam.SyntaxNode,
  String,
  Array[TokenInfo[T]],
) -> ((ParserContext[T, K]) -> Unit)?
```

Rewrite `reparse_block` as a loop over `find_reparseable_ancestors(...)`. For each candidate, calculate the candidate-local new end, extract `block_text`, lex it, and immediately return `None` on a balance failure. Call the selector only after balance succeeds. Continue only when the selector returns `None`; after `Some(reparse_fn)`, preserve the existing isolated parse, splice, and diagnostic merge code and return its result directly, including `None` on any failure.

- [ ] **Step 4: Run core tests and typecheck**

Run: `rtk moon check loom/core`

Expected: success.

Run: `rtk moon test loom/core --filter "reparse_block"`

Expected: the new widening/failure-boundary tests and existing diagnostic-offset test pass.

- [ ] **Step 5: Commit the core contract**

```bash
rtk git add loom/core/block_reparse.mbt loom/core/parser_robustness_wbtest.mbt loom/core/pkg.generated.mbti
rtk git commit -m "feat(core): widen declined block reparses"
```

### Task 2: Migrate Existing Selector Callers Without Semantic Drift

**Files:**
- Modify: `examples/json/block_reparse.mbt:23-57`
- Modify: `examples/lambda/block_reparse.mbt:4-31`
- Modify: `examples/markdown/block_reparse.mbt:555-596`
- Modify: `loom/core/parser_robustness_wbtest.mbt:145-155`
- Regenerate: `loom/core/pkg.generated.mbti`

**Interfaces:**
- Consumes: `BlockReparseSpec.get_reparser(old_node, new_text, tokens)` from Task 1.
- Produces: migrated JSON, Lambda, Markdown, and white-box selector initializers.

- [ ] **Step 1: Update every existing initializer to the new signature**

Change each selector to accept `node, _, _` when its existing behavior needs only the old node:

```moonbit
get_reparser: fn(node, _, _) {
  // retain the existing node-kind/depth logic unchanged
}
```

Do this for JSON, Lambda, and the existing core test fixture. Change Markdown's selector entry point to accept named `node, _, tokens` so Task 3 can use `tokens` without another API migration.

- [ ] **Step 2: Check all migrated packages**

Run: `rtk moon check loom/core && rtk moon check examples/json && rtk moon check examples/lambda && rtk moon check examples/markdown`

Expected: success; any remaining `get_reparser: fn(node)` compiler diagnostic identifies a missed callsite and must be migrated before proceeding.

- [ ] **Step 3: Commit callsite migration**

```bash
rtk git add loom/core/parser_robustness_wbtest.mbt loom/core/pkg.generated.mbti examples/json/block_reparse.mbt examples/lambda/block_reparse.mbt examples/markdown/block_reparse.mbt
rtk git commit -m "refactor: pass block reparse selector context"
```

### Task 3: Derive and Apply Markdown Ownership Rejection

**Files:**
- Modify: `examples/markdown/block_reparse.mbt:116-170,451-567`
- Test: `examples/markdown/incremental_test.mbt:88-161,238-299`

**Interfaces:**
- Consumes: the Task 1 selector arguments and unchanged `parse_list_item` / `parse_list_at_min_indent` grammar entry points.
- Produces: a selector that declines exactly the observed ownership-changing candidate; a regression test that proves the fallback or parent widening restores full-parse parity.

- [ ] **Step 1: Capture the actual strict candidate before writing the policy**

Temporarily add a diagnostic test beside `incremental: nested list indentation edits match full parse`. For each of the four ownership transitions in that test — child indent, child outdent, top-level sibling joining an existing nested list, and nested sibling outdenting after an existing nested list — parse the old CST and call `@core.find_reparseable_ancestor` with that assertion's exact edit.

Print each selected node kind, start/end, `node.text()` prefix, and the first three tokens from the candidate's re-lexed new text. The tab-indented text-only edit is a reuse control, not an ownership-transition probe.

Run: `rtk moon test examples/markdown`

Expected: the output identifies the strict candidate for all four transitions. Delete the temporary diagnostic test immediately after recording all four observations in this plan's Task 3 implementation notes; do not retain debug output in production or tests.

- [ ] **Step 2: Derive the selector predicate from the probe**

Update this task's implementation notes with the observed candidate kind and token transition. Add a helper that checks only that candidate's observed ownership-changing transition, using existing visual-column helpers rather than byte counts. The helper must return false for the same transition inside an already-nested item so ordinary local nested edits retain reuse.

In `markdown_block_reparse_spec.get_reparser(node, _, tokens)`, return `None` only when the helper reports that observed transition. Preserve the existing old-node marker extraction and parser closure in every other case.

- [ ] **Step 3: Let the normal fallback or selected parent establish ownership**

Do not add a fresh parser or duplicate list grammar. If a strict reparseable parent is observed, accept it only when its existing isolated reparser validates the new stream and parses with `parse_list_at_min_indent`. If no parent exists, the selector decline must let the established normal incremental/full-parse fallback rebuild the document. Keep `is_unordered_list_token_stream` and `unordered_list_context_allows_reparse` unchanged unless the probe proves the parent is selected and its existing validation rejects a structurally valid stream.


- [ ] **Step 4: Verify the regression and retained reuse behavior**

Run: `rtk moon test examples/markdown --filter "nested list indentation edits match full parse"`

Expected: PASS with incremental CST and diagnostics equal to a full parse.

Run: `rtk moon test examples/markdown --filter "unordered list middle item edits use block reparse"`

Expected: PASS; both existing reuse-count assertions remain `1`.

Run: `rtk moon check examples/markdown && rtk moon test examples/markdown`

Expected: check success and the complete Markdown package suite passes.

- [ ] **Step 5: Commit the Markdown ownership fix**

```bash
rtk git add examples/markdown/block_reparse.mbt examples/markdown/incremental_test.mbt examples/markdown/pkg.generated.mbti
rtk git commit -m "fix(markdown): widen ownership-changing list reparses"
```

### Task 4: Close the Documentation and Verify the Integrated Contract

**Files:**
- Modify: `docs/superpowers/plans/2026-07-15-block-reparse-ancestor-widening.md`
- Modify: `docs/README.md`
- Create or modify: `docs/decisions/<dated-block-reparse-ancestor-widening>.md` only if the completed public `BlockReparseSpec` contract requires an ADR under `docs/development/agent-docs-protocol.md`.

**Interfaces:**
- Consumes: passing core and Markdown checks from Tasks 1–3.
- Produces: completed-plan status, documentation index integrity, and an ADR/no-ADR closure decision.

- [ ] **Step 1: Run integrated verification**

Run: `rtk moon check && rtk moon test loom/core && rtk moon test examples/json && rtk moon test examples/lambda && rtk moon test examples/markdown`

Expected: all commands succeed. The Markdown parity regression and core widening boundary tests are included in their package suites.

- [ ] **Step 2: Record the plan completion and architecture decision**

Because this changes the public `BlockReparseSpec` contract and establishes reusable widening policy, create an ADR under `docs/decisions/` with Context, Decision, Rationale, Consequences, and a link to this archived plan. Mark this plan `**Status:** Complete`, add command evidence and the commit/PR reference, move it to `docs/archive/completed-phases/`, and update `docs/README.md` links in the same change.

- [ ] **Step 3: Commit documentation closure**

```bash
rtk git add docs/README.md docs/superpowers/plans/2026-07-15-block-reparse-ancestor-widening.md docs/archive/completed-phases/ docs/decisions/
rtk git commit -m "docs: record block reparse widening decision"
```
