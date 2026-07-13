# Line-lexer skeleton migration property-test design

**Date:** 2026-07-13  
**Status:** Approved

## Context

PR #708 added a seeded regression matrix for `integrate_line_lexer_skeleton`. It checks exact canonical migration, preservation of two noncanonical bodies, idempotence, selected subsets, duplicates, empty selection, and reordered mode inputs.

The suite is not structurally property-based. `@quickcheck.samples(96)` changes numeric mode-name suffixes, while ownership cases remain fixed and selection varies by the loop index. Its expected output also uses `mode_to_fn_name` and `generated_line_lexer_fn_name`, so a naming defect can affect the implementation and oracle consistently.

This follow-up strengthens migration coverage only. Runtime line-lexer behavior, filesystem failure injection, production behavior, and public APIs are out of scope.

## Test boundary

Move the structural property suite into `loomgen/line_lexer_migration_properties_wbtest.mbt`. Keep the focused example tests in `loomgen/regression_wbtest.mbt`, and remove the misleading seeded property loop from that file.

The new suite calls only the production boundary under test:

```text
integrate_line_lexer_skeleton(existing, selected_modes, "Token", "@core")
```

It does not call production skeleton emitters or naming helpers when constructing inputs or expected output.

## Case model

`MigrationOwnership` describes the existing state of one mode:

- `Canonical`: the exact historical abort stub.
- `AlreadyDelegated`: the exact generated-helper delegate.
- `Handwritten`: a user-owned implementation.
- `MutatedAbortMessage`: the canonical abort text with a changed message.
- `MutatedWhitespace`: the canonical function with changed whitespace.
- `MutatedSignature`: the canonical function with a changed signature.
- `CommentInserted`: the canonical function with a user comment.
- `Absent`: the dispatcher contains the mode, but its function block is missing.

`MigrationMode` stores a mode name, an independently derived function name, its helper name, its identifier component count, and its ownership state.

`MigrationCase` stores one to seven unique modes and an ordered selected-mode list. Selection may be empty, contain one or several modes, appear in a different order from declaration, or contain duplicates. An absent selected mode is valid and must be a no-op.

## Structural generator

Implement `@quickcheck.Arbitrary` for `MigrationCase`. Bound the generated structure so failed cases remain readable.

Generate identifiers from one to three predeclared word components. Each component carries separate CamelCase and snake_case spellings, for example `{ camel: "Block", snake: "block" }`. The generator composes the mode name from CamelCase fields and the function name from snake_case fields. It never runs the production uppercase-scanning transformation.

Generate independently:

- mode count;
- component count and component choices for each unique mode;
- ownership state for each mode;
- selected subset;
- selected order;
- duplicate selections.

Use QuickCheck's `RandomState` directly through the custom `Arbitrary` implementation. Collect 96 generated cases with `@quickcheck.samples(96)`.

## Independent exact oracle

A test-only renderer builds the complete existing skeleton directly from `MigrationCase` data. It renders the dispatch and each present function block according to its ownership state. `Absent` modes remain in dispatch but omit their function block.

A second rendering pass builds the expected skeleton from the same case data with one rule:

```text
selected Canonical -> AlreadyDelegated
all other states   -> unchanged
```

This expected-state transition is data-derived. It does not perform textual replacement and does not use production naming helpers. Exact equality of the complete strings proves that migration changes only recognized canonical blocks and preserves every other byte.

## Properties

For every deterministic basis case and generated case:

1. Production migration equals the independently rendered expected skeleton exactly.
2. Reapplying migration to the result is byte-identical, proving idempotence.
3. Reversing the selected list produces the same exact expected skeleton, proving order independence.
4. Duplicate selections do not alter the expected result.
5. Selected noncanonical and absent modes remain unchanged.
6. Unselected canonical modes remain unchanged.

Use exact string assertions rather than substring checks. Derive `Debug` for case types so a failure identifies the generated structure.

## Deterministic basis and coverage

Basis cases guarantee every ownership state is exercised while selected, including `Absent`. Additional basis cases guarantee an unselected canonical mode and these selection shapes:

- empty;
- singleton;
- multiple modes;
- declaration-order permutation;
- duplicate selection.

The basis also guarantees one-, two-, and three-component identifiers and minimum and maximum mode counts.

Coverage counters over all cases assert that every required ownership, selection, identifier-depth, and mode-count class ran. Separate counters over generated cases prove that the custom generator itself produces multiple ownership states, all identifier depths, and multiple selection shapes; deterministic basis coverage cannot conceal a collapsed generator.

## Verification

Run focused checks first:

```text
rtk moon check loomgen --target native
rtk moon test loomgen --target native
```

Then run repository-wide native verification:

```text
rtk moon fmt --check
rtk moon check --deny-warn --target native
rtk moon test --target native
```

Before creating a pull request, obtain an independent exact-head review of generator independence, oracle independence, ownership coverage, and full-string assertions.

## Decision record

No ADR needed: this test-only follow-up strengthens regression evidence for the existing line-lexer skeleton integration decision without changing behavior or public contracts.
