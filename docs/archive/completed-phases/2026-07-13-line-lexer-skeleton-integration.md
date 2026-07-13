# Line-mode Lexer Skeleton Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `--line-lexer` generate helpers that integrate automatically with `lexer_skeleton.g.mbt`, while preserving handwritten mode overrides.

**Architecture:** `line_lexer.g.mbt` will own `generated_lex_<mode>` helpers. `lexer_skeleton.g.mbt` will retain dispatch and public `lex_<mode>` override points, delegating generated line modes to those helpers. Existing untouched abort stubs are migrated by an exact textual replacement; non-identical bodies are user-owned and never rewritten.

**Tech Stack:** MoonBit, `moon` native target, loomgen fixture regeneration, MoonBit workbench tests.

**Status:** Complete

**Completion:** Implemented for [#699](https://github.com/dowdiness/loom/issues/699) in source commits `86d953a`, `f5a7cb6`, `5de95b5`, and `4144ce7`; delivered as [PR #706](https://github.com/dowdiness/loom/pull/706). Verification: `moon check --deny-warn --target native`; `moon test --target native` — 3446 passed; focused loomgen and generated-fixture tests; two deterministic fixture regeneration passes.

**Decision record:** [ADR: Line-mode lexer skeleton integration](../../decisions/2026-07-13-line-lexer-skeleton-integration.md).

## Global Constraints

- Preserve `emit_lexer_skeleton` all-stub output when `--line-lexer` is absent.
- Keep `lex_<mode>` as the user override API and use `generated_lex_<mode>` only for generated helpers.
- Replace only Loom's exact historical aborting stub body during existing-skeleton migration; preserve any non-identical function byte-for-byte.
- Keep `--force-lexer` as the only explicit whole-skeleton overwrite mechanism.
- Preserve existing line-pattern matching and `#loom.fallback_lex` behavior.
- Run `moon fmt`, focused native tests, fixture regeneration twice, and the generated Markdown lexer end-to-end test.

---

### Task 1: Define helper and skeleton integration contracts

**Files:**
- Modify: `loomgen/emit_lexer_skeleton.mbt:1-70`
- Modify: `loomgen/emit_line_lexer.mbt:31-205`
- Test: `loomgen/regression_wbtest.mbt:255-268`
- Test: `loomgen/emit_lexer_wbtest.mbt:720-754,916-985`
- Modify: `loomgen/fixtures/line_pattern_fixture.g.mbt`

**Interfaces:**
- Consumes: `mode_to_fn_name(mode : String) -> String` and parsed `#loom.line_mode` variants.
- Produces: `generated_line_lexer_fn_name(mode : String) -> String`, `collect_line_lexer_modes(term_enum_decl : EnumDecl?) -> Array[String]`, `emit_lexer_skeleton_with_line_delegates(modes, line_modes, token_type, core_qual) -> String`, and `integrate_line_lexer_skeleton(existing, line_modes, token_type, core_qual) -> String`.

- [x] **Step 1: Write failing line-helper naming assertions**

Add a workbench test that parses `fixtures/line_pattern_fixture.mbt`, emits the line lexer, and asserts:

```moonbit
inspect(generated.contains("fn generated_lex_line_start"), content="true")
inspect(generated.contains("fn lex_line_start"), content="false")
```

Update the existing fallback-isolation test to search for `fn generated_lex_line_start` and `fn generated_lex_block_quote_line_start` before slicing generated output.

- [x] **Step 2: Run focused emission tests and confirm failure**

Run:

```bash
moon test loomgen --target native --filter emit_line_lexer
```

Expected: the helper-name assertions fail because line emitters still define `lex_<mode>` directly.

- [x] **Step 3: Emit generated helper names and expose line-mode collection**

Move line-mode collection into a shared helper that returns a deterministically sorted array. Define:

```moonbit
fn generated_line_lexer_fn_name(mode : String) -> String {
  "generated_" + mode_to_fn_name(mode)
}
```

Pass that name to `emit_mode_line_lexer`; do not alter the function body’s matching, fallback, or recovery behavior. Preserve `emit_line_lexer` returning `None` when no candidates or line modes exist.

- [x] **Step 4: Add failing skeleton delegate and migration tests**

In `regression_wbtest.mbt`, add tests that verify:

```moonbit
let output = emit_lexer_skeleton_with_line_delegates(
  ["Inline", "LineStart"], ["LineStart"], "Token", "@core",
)
inspect(output.contains("generated_lex_line_start(source, pos)"), content="true")
inspect(output.contains("abort(\"lex_inline not implemented\")"), content="true")
```

Add migration input containing one exact old `lex_line_start` aborting stub and one custom `lex_inline` body. Assert the former becomes the delegate, the latter remains byte-identical, and applying `integrate_line_lexer_skeleton` twice returns the same text.

- [x] **Step 5: Implement shared skeleton rendering and conservative migration**

Refactor skeleton emission around one private renderer that chooses either:

```moonbit
fn lex_line_start(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
  generated_lex_line_start(source, pos)
}
```

or the existing exact aborting stub.

Keep `emit_lexer_skeleton` as the all-stub compatibility wrapper. Implement the delegate-aware emitter with the supplied line-mode set. Implement migration by replacing only the exact stub text generated by the same shared renderer; never perform a broad function-name or regular-expression rewrite.

- [x] **Step 6: Regenerate and verify emitter fixtures**

Update `loomgen/fixtures/line_pattern_fixture.g.mbt` through the established fixture regeneration path. Run:

```bash
moon fmt loomgen
moon test loomgen --target native --filter emit_line_lexer
moon test loomgen --target native --filter emit_lexer_skeleton
```

Expected: all focused tests pass; all-stub golden output remains unchanged and the line-lexer golden uses `generated_lex_line_start`.

- [x] **Step 7: Commit the isolated emitter contract**

```bash
git add loomgen/emit_lexer_skeleton.mbt loomgen/emit_line_lexer.mbt loomgen/regression_wbtest.mbt loomgen/emit_lexer_wbtest.mbt loomgen/fixtures/line_pattern_fixture.g.mbt
git commit -m "feat(loomgen): delegate line lexer helpers from skeleton"
```

### Task 2: Integrate preflighted line modes into CLI output

**Files:**
- Modify: `loomgen/main.mbt:315-480,837-850,919-975`
- Modify: `fixtures/line_lexer_regression/regenerate.sh`
- Modify: `fixtures/line_lexer_regression/lexer_skeleton.g.mbt`
- Modify: `fixtures/line_lexer_regression/line_lexer_support.mbt`

**Interfaces:**
- Consumes: `collect_line_lexer_modes`, `emit_lexer_skeleton_with_line_delegates`, `integrate_line_lexer_skeleton`, and the preflighted `--line-lexer` content.
- Produces: a skeleton whose untouched stubs are automatically delegated during a valid `--line-lexer` invocation and an end-to-end fixture with no handwritten dispatch implementation.

- [x] **Step 1: Add failing fixture-level integration expectation**

Remove the handwritten `pub fn lex` dispatcher and `lex_inline` from `line_lexer_support.mbt`. Direct `regenerate.sh` to use the fixture directory as `syntax-out`, then commit `lexer_skeleton.g.mbt` with the generated `lex` dispatcher, generated line-mode delegate, and the handwritten `lex_inline` body replacing its canonical aborting stub. Keep the skeleton’s other generated content unchanged.

- [x] **Step 2: Run fixture regeneration and prove the current failure**

Run:

```bash
fixtures/line_lexer_regression/regenerate.sh
moon test fixtures/line_lexer_regression --target native
```

Expected: compilation fails because no generated `lex` dispatcher exists in the fixture package.

- [x] **Step 3: Carry line-mode metadata through preflight and output writing**

Extend the preflighted line-lexer job to contain its output path, helper content, and collected line-mode names. Add that line-mode set to `write_outputs`.

When the skeleton is absent or `--force-lexer` is set, use the delegate-aware skeleton renderer whenever the line-mode set is non-empty. When a skeleton already exists and line generation is requested, read it and run conservative migration; write only when migration changed the file. Preserve the previous no-rewrite path when no line lexer is requested.

- [x] **Step 4: Run the regenerated fixture end to end**

Regenerate the fixture and run:

```bash
moon fmt fixtures/line_lexer_regression
moon test fixtures/line_lexer_regression --target native
```

Expected: both existing Markdown LF and CRLF tokenization tests pass through the generated dispatcher and delegate, while the handwritten `lex_inline` override inside the skeleton supplies line fallback.

- [x] **Step 5: Prove deterministic round-trip output**

Run the regeneration script twice, then compare generated output checksums:

```bash
fixtures/line_lexer_regression/regenerate.sh
sha256sum fixtures/line_lexer_regression/line_lexer.g.mbt fixtures/line_lexer_regression/lexer_skeleton.g.mbt
fixtures/line_lexer_regression/regenerate.sh
sha256sum fixtures/line_lexer_regression/line_lexer.g.mbt fixtures/line_lexer_regression/lexer_skeleton.g.mbt
```

Expected: the two checksum pairs are identical.

- [x] **Step 6: Commit CLI integration and regression fixture**

```bash
git add loomgen/main.mbt fixtures/line_lexer_regression
git commit -m "feat(loomgen): integrate generated line modes with skeleton"
```

### Task 3: Document the generated-file contract and record the decision

**Files:**
- Modify: `loomgen/README.md:33-64`
- Create: `docs/decisions/2026-07-13-line-lexer-skeleton-integration.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-07-13-line-lexer-skeleton-design.md`
- Modify: `docs/superpowers/plans/2026-07-13-line-lexer-skeleton-integration.md`

**Interfaces:**
- Consumes: the emitted helper/delegate naming and migration behavior established in Tasks 1–2.
- Produces: public documentation describing generated helpers, preserved overrides, migration boundaries, and the durable rationale ADR.

- [x] **Step 1: Document the automatic integration contract**

Replace the current claim that generated functions “can replace” skeleton stubs with explicit behavior:

```markdown
`--line-lexer` emits `generated_lex_<mode>` helpers and wires untouched generated
`lex_<mode>` skeleton stubs to those helpers automatically. You may replace a
`lex_<mode>` delegate with handwritten code to override that mode; later line-lexer
regeneration preserves that non-generated function body.
```

State that `--force-lexer` is the explicit full-skeleton overwrite path.

- [x] **Step 2: Write the ADR**

Create `docs/decisions/2026-07-13-line-lexer-skeleton-integration.md` with the required ADR shape. Link the implementation plan, identify the original duplicate-name failure, record layered delegation and exact-stub migration, and list the public helper/override consequences.

- [x] **Step 3: Mark plan evidence and archive it after all checks pass**

After Task 4 verification, mark the plan **Status: Complete**, add the issue link and verification evidence, add the PR link when one exists, add a `Decision record:` section linking the ADR, move it to `docs/archive/completed-phases/2026-07-13-line-lexer-skeleton-integration.md`, and update `docs/README.md` links in the same edit.

- [x] **Step 4: Commit public contract documentation**

```bash
git add loomgen/README.md docs/decisions docs/README.md docs/superpowers/specs docs/archive/completed-phases
git commit -m "docs(loomgen): document line lexer skeleton integration"
```

### Task 4: Run final verification and prepare the issue closure

**Files:**
- Verify: `loomgen/`
- Verify: `fixtures/line_lexer_regression/`
- Verify: `docs/`

**Interfaces:**
- Consumes: complete Tasks 1–3.
- Produces: direct evidence that generated line helpers and skeleton delegates compile together, migration preserves overrides, fixtures are deterministic, and documentation/ADR are indexed.

- [x] **Step 1: Run formatting and focused package checks**

```bash
moon fmt --check
moon check loomgen --target native
moon test loomgen --target native
moon test fixtures/line_lexer_regression --target native
```

Expected: each command succeeds; loomgen tests include helper/delegate and migration coverage; the fixture executes LF and CRLF behavior through generated dispatch.

- [x] **Step 2: Run whole-workspace native tests**

```bash
moon test --target native
```

Expected: workspace suite succeeds without new failures.

- [x] **Step 3: Inspect generated artifact ownership**

Verify the generated fixture files directly:

```bash
grep -n "generated_lex_line_start\|pub fn lex\|fn lex_inline" fixtures/line_lexer_regression/line_lexer.g.mbt fixtures/line_lexer_regression/lexer_skeleton.g.mbt
```

Expected: the helper appears only in `line_lexer.g.mbt`; public dispatch, the line-mode delegate, and the handwritten inline override appear in `lexer_skeleton.g.mbt`.

- [x] **Step 4: Review current diff and commit boundaries**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; source, fixture, and documentation changes are represented by the three task commits.
