# Line-lexer Migration Properties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:executing-plans`; the generator and oracle are coupled and should be implemented inline with a review checkpoint after each task.

**Goal:** Replace #708's renamed deterministic matrix with structural QuickCheck cases and an independent exact-string oracle for `integrate_line_lexer_skeleton`.

**Architecture:** A dedicated wbtest file owns test-only case data, independent skeleton rendering, deterministic basis cases, the custom `Arbitrary` generator, and coverage accounting. Production code remains unchanged; `regression_wbtest.mbt` retains focused examples and drops only the superseded loop.

**Tech Stack:** MoonBit wbtests, `moonbitlang/core/quickcheck`, `moonbitlang/core/quickcheck/splitmix`, native Moon toolchain.

## Global Constraints

- Work only in the isolated `test/line-lexer-structural-properties` checkout; do not touch the dirty canonical checkout; no ADR is needed for this test-only follow-up.
- Never use `mode_to_fn_name`, `generated_line_lexer_fn_name`, or a production skeleton emitter in the test oracle.
- Only selected `Canonical` modes transition to `AlreadyDelegated`; all other bytes remain identical, including a selected `Absent` mode with no function block.
- Run `rtk moon check loomgen --target native` after each MoonBit edit and focused Loomgen tests before repository-wide verification.

---

### Task 1: Independent migration model and deterministic oracle

**Files:** Create `loomgen/line_lexer_migration_properties_wbtest.mbt`.

**Interfaces:** Define private `MigrationOwnership`, `MigrationWord`, `MigrationMode`, and `MigrationCase`; include token type and core qualifier in each case; use byte-exact test-only skeleton templates, independent existing/expected renderers, and one checker for exact migration, idempotence, deduplication, reversal, and rotation equivalence.

- [ ] Add all nine ownership states and exact state renderings, including `Absent`, isolated wrong-token, and isolated wrong-core-qualifier states, without calling production naming or emission helpers.
- [ ] Build identifiers from an equal-width component catalog containing ordinary TitleCase, consecutive-uppercase, and digit-bearing shapes; take distinct first components without replacement and assert unique mode/function/helper names; no retry loop.
- [ ] Pin dispatcher punctuation, indentation, separators, declaration order, and EOF-newline policy; add one basis case with independently written complete input/output literals.
- [ ] Add basis cases covering every selected ownership state, an unselected canonical state, alternate exact token/core parameters, isolated wrong-token/wrong-qualifier near matches, empty/single/multi/reordered/duplicate selection, identifier depths 1–3, and mode counts 1 and 7.
- [ ] Add coverage accounting that fails unless every required basis class ran.
- [ ] Run `rtk moon check loomgen --target native` and `rtk moon test loomgen --target native`; expect both to pass, then commit as `test(loomgen): add independent migration oracle`.

### Task 2: Structural QuickCheck generation

**Files:** Modify `loomgen/line_lexer_migration_properties_wbtest.mbt`; modify `loomgen/moon.pkg` to add `moonbitlang/core/quickcheck/splitmix` for wbtests only.

**Interfaces:** Implement `@quickcheck.Arbitrary for MigrationCase`; generated cases feed the Task 1 checker and fixed-seed generator-coverage counters.

- [ ] Generate 1–7 unique modes by shuffling the component catalog for distinct first components, then choose identifier depth, trailing components, ownership, token type, and core qualifier independently from `RandomState`.
- [ ] Generate selected subsets, permutations, empty selections, and duplicates independently of ownership.
- [ ] For each case, compare original selection, stable deduplication, reverse, and one-position rotation against the same exact expected skeleton.
- [ ] Append `@quickcheck.samples(96)` for ordinary variation; separately invoke `Arbitrary` with documented fixed SplitMix seeds covering all nine ownership states, identifier depths 1–3, all token/core parameter values, and multiple selection shapes.
- [ ] Run `rtk moon fmt`, `rtk moon check loomgen --target native`, and `rtk moon test loomgen --target native`; expect all Loomgen checks and tests to pass, then commit as `test(loomgen): generate structural migration cases`.

### Task 3: Retire the superseded matrix and verify

**Files:** Modify `loomgen/regression_wbtest.mbt`; modify `docs/README.md` to index this plan.

- [ ] Delete only `test "property: line skeleton migration is exact, idempotent, and order-independent"`; preserve the focused migration examples around it.
- [ ] Run focused Loomgen check/tests, then `rtk moon fmt --check`, `rtk moon check --deny-warn --target native`, and `rtk moon test --target native`; require zero failures.
- [ ] Calibrate the detector by temporarily changing the production generated-helper prefix, require the focused property file to fail with an exact mismatch, restore the production byte, and rerun the focused file green.
- [ ] Obtain an independent exact-head review covering generator independence, oracle independence, all nine ownership states, signature-parameter isolation, selection coverage, and exact full-string assertions before PR creation.
- [ ] Commit as `test(loomgen): replace seeded migration matrix` and push the branch.
