# Quantifier Unification Implementation Plan
**Status:** Complete

Completed 2026-07-17 on `feat/529-allowlist-tokenizer`. Focused parser tests and lazy annotation rejection pass; the full loomgen suite reports 205 passing tests.

Decision record:

- Updated ADR: [Fail-Closed Pattern Allowlist Parser](../../decisions/2026-07-17-pattern-allowlist-tokenizer.md) to record the typed quantifier IR, bounded-count invariant, and rejection of unused lazy state.

> **For agentic workers:** Execute this plan inline with test-first checkpoints.

**Goal:** Replace the parser's ad-hoc quantifier variants with a typed `Pattern::Quantified` representation and verified counted bounds.

**Architecture:** `Pattern` stores one `Quantified(Pattern, Quantifier)` node. `Quantifier` stores the `QuantifierKind`; counted quantifiers use `RepeatBounds`. Bound constructors are private smart constructors that enforce the native `re` limit and ordering before values become semantic `Int`s. Lazy suffixes are consumed and rejected rather than retained in the IR.

**Tech Stack:** MoonBit native target, loomgen white-box tests, existing parser validation and lexer fixture tests.

## Global Constraints

- Preserve the supported regex allowlist and existing malformed/unsupported diagnostic precedence.
- Reject counted bounds above 256 before integer conversion.
- Never construct invalid `Range(min, max)` or out-of-limit counts through a public constructor.
- Keep generated lexer output and existing valid-pattern behavior unchanged.

### Task 1: Define the typed quantifier model

**Files:**
- Modify: `loomgen/parse_pattern.mbt`
- Test: `loomgen/parse_pattern_wbtest.mbt`

- [x] Add failing white-box tests for exact, at-least, range, nullable quantifier semantics, and lazy-suffix rejection using the new internal constructors/accessors.
- [x] Run the focused tests and confirm failure because the new types/functions do not exist.
- [x] Add `QuantifierKind`, `Quantifier`, and `RepeatBounds` with private smart constructors for `Count`, `AtLeast`, and `Range`; make invalid bounds return `None`.
- [x] Replace the four quantifier fields in `Pattern` with `Quantified(Pattern, Quantifier)`.
- [x] Add semantic helpers for minimum count and nullability; consume lazy suffixes as unsupported syntax without retaining unused greediness state.
- [x] Run `moon check --target native loomgen` and the focused white-box tests.

### Task 2: Migrate parser construction

**Files:**
- Modify: `loomgen/parse_pattern.mbt`
- Test: `loomgen/parse_pattern_wbtest.mbt`

- [x] Extend counted-bound tests with `{256}`, `{1,256}`, `{000256}`, `{257}`, `{1,257}`, reversed ranges, and unbounded `{n,}`.
- [x] Run tests before the parser migration and confirm the new semantic expectations fail.
- [x] Parse bounds as decimal slices, validate against 0..256 and `min <= max`, convert only after validation, and construct `Exact`, `AtLeast`, or `Range` through smart constructors.
- [x] Migrate simple quantifiers and lazy suffix handling to `QuantifierKind`; lazy suffixes are consumed and rejected.
- [x] Preserve malformed-input consumption and earliest-error behavior.
- [x] Run focused parser tests and `moon check --target native loomgen`.

### Task 3: Migrate validation and generated-lexer integration

**Files:**
- Inspect and modify only if required: `loomgen/parse_annotations.mbt`, `loomgen/emit_lexer.mbt`, related tests.
- Test: `loomgen/emit_lexer_wbtest.mbt`, `loomgen/parse_annotations_wbtest.mbt`, generated pattern fixture tests.

- [x] Update pattern consumers to use the unified semantic helpers rather than matching old quantifier variants.
- [x] Run parser, annotation, emitter, and compiled/runtime fixture tests.
- [x] Confirm generated output remains byte-equivalent for existing valid fixtures unless a changed diagnostic is explicitly required.

### Task 4: Final verification and documentation

**Files:**
- Modify: `docs/README.md` for the new plan index entry.
- Inspect: `docs/development/agent-docs-protocol.md`.

- [x] Run `moon fmt`, `moon check --target native loomgen`, focused tests, and the full `loomgen` test package.
- [x] Run `moon info loomgen` and verify no unintended public API change.
- [x] Review the diff for invalid constructors, stale old-pattern matches, and diagnostic regressions.
- [x] Record the design decision in an ADR if the unified AST policy is retained; otherwise add the required `No ADR needed` note before archiving this plan.
