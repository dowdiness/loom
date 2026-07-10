# Plan: Remove `emit_grammar.mbt` and realign loomgen

**Date:** 2026-07-10
**Status:** Complete
**Decision record:** [ADR 2026-07-10](../../docs/decisions/2026-07-10-remove-emit-grammar-code-generator.md)
**Issue:** [#671](https://github.com/dowdiness/loom/issues/671)
**ADR:** [2026-07-10-remove-emit-grammar-code-generator.md](../../decisions/2026-07-10-remove-emit-grammar-code-generator.md)
**Supersedes:** [2026-06-28-grammar-ir-emitter.md](../../superpowers/plans/2026-06-28-grammar-ir-emitter.md)

## Motivation

The `@grammar.interpret` tree-walking interpreter is at full incremental throughput
parity with hand-written parsers. The code emitter (`emit_grammar.mbt`, 766 lines)
was the named fix for a deep-subtree reuse gap that no longer exists. The emitter
is dead code with a maintenance cost and no provable correctness guarantee.

Removing it realigns loomgen as exclusively a **MoonBit boilerplate generator**
(syntax_kind, token_impls, views, lexer, spec, lexmode, GrammarIr data) —
not a parser generator.

## Tasks

### Task 1: ADR Creation

Create `docs/decisions/2026-07-10-remove-emit-grammar-code-generator.md` containing:

- Supersedes: 2026-06-22 ADR (deferred the emitter)
- Benchmark data: Flat incremental B/A=0.95×, Deep incremental B/A=0.91×
- Decision: delete emit_grammar.mbt, keep interpret as the only parser backend
- Consequences: positive (shrink loomgen, remove untestable codegen), neutral (archive superseded ADRs)

**Acceptance:** ADR file exists and is referenced by the plan and issue.

---

### Task 2: Delete `emit_grammar.mbt` + test

**Delete files:**
- `loomgen/emit_grammar.mbt` (766 lines) — parser code generator
- `loomgen/emit_grammar_wbtest.mbt` (~620 lines) — tests

**Clean references:**
- `loomgen/main.mbt` — remove `emit_grammar` import and `parse_grammar` / `--grammar-ir` path? No, those are for `emit_grammar_ir.mbt`, not `emit_grammar.mbt`. Verify.
- `loomgen/regenerate_fixtures.mbt` — it calls `emit_grammar()` for grammar_parity fixtures. Those calls must be removed (Task 3 handles the full fixture scope; this task just confirms the file reference is gone).

**Verify:**
- `rtk moon check loomgen --target native` — compiles clean (no `emit_grammar` symbol referenced anywhere)

**Acceptance:** `emit_grammar` does not appear in `moon check` errors; both files are gone.

---

### Task 3: Delete fixture parity packages + update regenerate_fixtures

**Delete packages** (3 directories, ~15 files total):
- `loomgen/fixtures/grammar_parity/`
- `loomgen/fixtures/grammar_parity_reuse/`
- `loomgen/fixtures/grammar_parity_native/`

**Update `loomgen/regenerate_fixtures.mbt`:**
- Remove the three `emit_grammar()` call blocks (each compiles a GrammarIr, calls emit, writes to file)
- Keep the rest of the file if it has other fixture regeneration logic; delete the file entirely if grammar_parity was its only purpose

**Update `loomgen/main.mbt`:**
- Remove the `--regenerate-fixtures` flag if grammar_parity was its only consumer. If other fixtures use this flag, remove only the grammar_parity case from the dispatch.

**Acceptance:**
- `rtk moon check loomgen --target native` passes
- No `grammar_parity` references remain in the tree outside archive docs

---

### Task 4: Trim `mbt_ast.mbt` — remove emit_grammar-only types

**Remove from `loomgen/mbt_ast.mbt`:**
- `MbtModule` struct (used only by emit_grammar)
- `MbtFnDecl` struct (used only by emit_grammar)
- `MbtStmt` enum (used only by emit_grammar)
- `MbtBlock` struct (used only by emit_grammar)
- `MbtElseBranch` enum (used only by emit_grammar)
- `@pretty.Pretty for MbtModule` impl (used only by emit_grammar)
- Helper functions: `kw`, `ident`, `punc`, `op`, `binop_prec` (used only by the MbtModule Pretty impl)

**Keep:**
- `MbtExpr` enum (used by `emit_grammar_ir.mbt` for constructing GrammarIr data values)
- `MbtPat` enum (used by `emit_grammar_ir.mbt`)
- `MbtMatchArm` struct (used by `emit_grammar_ir.mbt`)
- `MbtParam` struct (used by `emit_grammar_ir.mbt`)

**Verify:**
- `rtk moon check loomgen --target native` passes
- All remaining tests pass: `rtk moon test loomgen --target native`

**Acceptance:** `mbt_ast.mbt` compiles with only the kept types. No orphan references.

---

### Task 5: Update README and HANDOFF

**Update `loomgen/README.md`:**
- Remove "Grammar IR Emitter (`emit_grammar.mbt`)" section (lines 12–22)
- Rewrite the opening paragraph to state loomgen's purpose as:
  > "Code generator for loom MoonBit plumbing files. Generates `syntax_kind.g.mbt`,
  > `token_impls.g.mbt`, `lexer.g.mbt`, `views.g.mbt`, `lexmode.g.mbt`,
  > `spec.g.mbt`, and `grammar_ir.g.mbt` from `#loom.*` annotated enums.
  > Parser execution is delegated to `@grammar.interpret` at runtime."
- Remove fixture parity references from the Fixtures section
- Add a link to the ADR

**Update `loomgen/HANDOFF.md`:**
- Add a section recording this removal: what was removed, why, and the superseded ADRs
- Update the file listing if present

**Update `docs/README.md`:**
- Add new ADR entry at the top of the decision list
- Add the plan to the "Analysis" section
- Archive or mark as superseded: `docs/decisions/2026-07-03-structural-ast-testing-grammar-emitter.md`
- Mark plan `docs/superpowers/plans/2026-06-28-grammar-ir-emitter.md` as superseded

**Acceptance:** All three README files are consistent. No references to the deleted emitter.

---

### Task 6: Final verification

Run in order:

1. `rtk moon check loomgen --target native` — must pass
2. `rtk moon test loomgen --target native` — all remaining tests pass
3. `rtk moon bench --release -p dowdiness/lambda/benchmarks -f grammar_incremental_benchmark.mbt` — still passes (interpret-based)
4. `rtk moon test` (repo root) — no workspace-wide regressions
5. Grep check: `rtk rg "emit_grammar\b" loomgen/` — returns no source matches (only plan/ADR docs remain)
6. Grep check: `rtk rg "grammar_parity\b" loomgen/` — returns no source matches
7. Grep check: `rtk rg "MbtModule|MbtFnDecl|MbtStmt|MbtBlock|MbtElseBranch" loomgen/` — returns no matches outside mbt_ast.mbt

**Acceptance:** All checks green. No orphan references.

## Risk

- **Runtime**: None. The emitter output was never consumed by production code.
  All examples use `@grammar.interpret` or hand-written parsers.
- **Regeneration**: `--regenerate-fixtures` for grammar_parity is removed. Other
  fixtures (lexer, lexmode, view) are regenerated through separate loomgen passes
  and are unaffected.
- **Documentation drift**: The archived plans cite `emit_grammar.mbt` extensively.
  The archive header should redirect readers to `@grammar.interpret` as the active
  component.
