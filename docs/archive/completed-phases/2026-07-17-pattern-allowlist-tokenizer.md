# `#loom.pattern` Allowlist Tokenizer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Run the independent design review gate before implementation.

**Status:** Complete
**Completed:** 2026-07-17; issue #529 implementation is present on branch `feat/529-allowlist-tokenizer`.
**Evidence:** `moon check --target native loomgen`; parser 19/19 focused tests; full loomgen suite 205/205. `loomgen/moon.pkg` supports native only, so the all-target check is inapplicable.
**Decision record:** [ADR: Fail-Closed Pattern Allowlist Parser](../../decisions/2026-07-17-pattern-allowlist-tokenizer.md)
**Issue:** [dowdiness/loom#529](https://github.com/dowdiness/loom/issues/529)
**Design basis:** preserve the intended safe regex subset and all currently valid fixtures; deliberately reject constructs that the current fail-open scanners accept but the MoonBit `re` consumer rejects.

## Goal

Replace the independent `malformed_re`, `unsupported_re_construct`, `class_end`, and nullability scanners with one package-private allowlist parser whose result is consumed by both `#loom.pattern` and `#loom.line_pattern` validation, while preserving accepted syntax, diagnostics, and generated lexer output.

## Architecture
Add a focused `loomgen/parse_pattern.mbt` module that parses a raw pattern into a nested private IR: sequences contain atoms; atoms represent literals, supported escapes, character classes, plain groups, anchors, and attached quantifier kinds. The parser owns all delimiter, escape, quantifier, class-item, and POSIX-item recognition; unknown constructs fail closed. Lazy suffixes are consumed and rejected as unsupported rather than retained in the IR.

`parse_annotations.mbt` consumes the parsed IR for validation and nullability. `emit_lexer.mbt` and `emit_line_lexer.mbt` continue emitting the original raw pattern, so this change does not introduce a serializer or golden-output churn. No public API or `.mbti` surface should change.

## Global Constraints

- Preserve the intended safe subset documented in `loomgen/README.md` and all currently valid fixtures. A syntax that was previously accepted only because validation failed open may be narrowed to rejection when the real MoonBit `re` consumer rejects it.
- Reject unknown or unsupported constructs at generation time; never pass them to generated `re"..."` literals.
- POSIX class names are an explicit allowlist derived from native compile probes: `alnum`, `alpha`, `ascii`, `blank`, `digit`, `lower`, `space`, `upper`, `word`, and `xdigit`.
- POSIX names `cntrl`, `graph`, `print`, and `punct` are rejected because the current MoonBit `re` dialect reports them as unsupported. Empty names, unknown names such as `not_a_real_class`, names containing non-ASCII/alphanumeric characters, and malformed attempts that begin a POSIX item are rejected; a bare `[:` that does not form a POSIX item remains ordinary class content.
- Use the same parser and validation path for `#loom.pattern` and `#loom.line_pattern`.
- Preserve existing diagnostic categories and stable message substrings used by tests.
- Keep `is_nullable_pattern` conservative: parse errors return `true` when called directly, but annotation validation reports the parse error first.
- Keep generated lexer output based on the raw source pattern.
- Run `rtk moon check` immediately after every line-count-changing edit during implementation.
- Add tests before implementation changes; do not update snapshots without reviewing the resulting diff.

## Mandatory Design Review Gate

Before implementation, an independent reviewer using a different model must inspect the current `parse_annotations.mbt`, `nullable_pattern_wbtest.mbt`, `emit_lexer_wbtest.mbt`, and this plan with tools. The review must specifically challenge class grammar, escaped delimiters, quantifier attachment, malformed-input recovery, nullable groups, and preservation of existing diagnostics. Record the review verdict and any accepted corrections before starting Task 1.

**Review result (2026-07-17):** FAIL initially; independent reviewer `openai-codex/gpt-5.5` used tool-backed reads and identified three specification gaps: preserve false-POSIX `[:` class content, reject nested alternation at every depth, and reject orphan/stacked quantifiers. All three corrections are incorporated in Tasks 1, 2, and 5 before implementation.

## File Map

- Create: `loomgen/parse_pattern.mbt` — private pattern IR, allowlist parser, class parser, quantifier parser, and IR nullability evaluator.
- Create: `loomgen/parse_pattern_wbtest.mbt` — focused parser/IR tests and class/quantifier boundary regressions.
- Modify: `loomgen/parse_annotations.mbt` — call the shared parser for both annotation kinds; remove the four superseded scanner implementations.
- Modify: `loomgen/nullable_pattern_wbtest.mbt` — keep the existing nullable/non-nullable wrapper cases, including malformed/unsupported inputs as conservative `true` results; place all token-boundary and class-grammar assertions in `parse_pattern_wbtest.mbt`.
- Modify: `loomgen/emit_lexer_wbtest.mbt` — preserve annotation-level diagnostic tests and add shared validation coverage for line patterns and bare-dash classes.
- Modify: `loomgen/README.md` — document that the supported subset is allowlisted and that unrecognized syntax fails closed; retain the existing user-facing subset list.
- Modify: `docs/README.md` — add the active plan index entry.
- Do not modify: generated lexer goldens unless regeneration proves an existing emitter drift unrelated to this change.

## Tasks

### Task 1: Freeze the grammar contract with failing tests
1. Add parser-level tests for accepted atoms: literals, literal-meta escapes, hex escapes, anchors, plain groups, greedy `*`, `+`, `?`, counted quantifiers, ranges, escaped `]`, escaped `-`, and class `|` as a literal.
2. Add one positive control for every allowed POSIX name: `[[:alnum:]]`, `[[:alpha:]]`, `[[:ascii:]]`, `[[:blank:]]`, `[[:digit:]]`, `[[:lower:]]`, `[[:space:]]`, `[[:upper:]]`, `[[:word:]]`, and `[[:xdigit:]]`.
3. Add parser-level rejection tests for unsupported POSIX names `[[:cntrl:]]`, `[[:graph:]]`, `[[:print:]]`, `[[:punct:]]`, unknown `[[:not_a_real_class:]]`, empty `[[:]]`, malformed `[[:digit]`, and invalid-name `[[:alpha_1:]]`, alongside `(?...)`, assertion/Perl escapes, lazy quantifiers, top-level and nested alternation, stray `)`, unclosed `(`, unterminated classes, trailing `\\`, unterminated `{`, and class-leading/class-trailing bare `-`.
4. Add class-boundary tests for `[]`, `[^a]`, `[]a]`, `[a--z]`, `[a-z]`, `[a\\-z]`, `[a|b]`, and the existing false-POSIX control `[a[:z]X`. Native probes show `[^a]` is accepted, while `[]a]` and `[a--z]` are rejected; encode those results as rejection/acceptance tests. A false-POSIX `[:` must remain class content, while an actual POSIX attempt with an unknown/invalid name must fail closed.
5. Add mixed-error precedence tests matching the current ordering: `(?:a` and `(?a{2` must report a malformed reason rather than the unsupported `(?...)` reason; an otherwise well-formed `(?:a)` must report unsupported.
6. Add nested alternation tests for `(foo|bar)` and `(foo|foobar)` and assert rejection through both annotation paths (`#loom.pattern` and `#loom.line_pattern`).
7. Add orphan and stacked quantifier tests: reject `*a`, `+a`, `?a`, `{2}a`, `a**`, `a++`, and `a{2}{3}`.
8. Add boundary tests proving each allowlisted `[:name:]` is parsed as one POSIX item, that `[a[:z]X` closes at its real `]`, and that a later `(?:...)` after a false-POSIX sequence is still rejected.
9. Add nullable IR expectations for empty sequence, anchors, optional atoms, zero-lower-bound quantifiers, required atoms, and nested groups.
10. Run `rtk moon test loomgen/parse_pattern_wbtest.mbt --target native`; expected failure because the parser types/functions do not yet exist.

### Task 2: Implement the private IR and allowlist parser

1. Define private types for parsed sequences, atoms, quantifiers, class items, and structured parser errors. Keep constructors package-private and derive only the traits required by whitebox tests.
2. Implement a cursor-based parser that consumes the complete pattern. Every successful branch must advance the cursor by at least one position; recovery must never revisit the same position. Track delimiter state inside the parser rather than delegating it to a second scanner. Record `first_malformed` and `first_unsupported` independently, continue structural recovery after unsupported constructs, and return malformed before unsupported at the end. If multiple errors have the same category, retain the one with the lowest source position.
3. Parse plain groups recursively and require their closing `)`; reject `(?` before treating `?` as group content.
4. Parse escapes in one place. Accept only the current literal-meta and hex forms; classify assertion and Perl class escapes as unsupported; reject a terminal backslash as malformed.
5. Parse character classes item-by-item. Recognize escaped items, literals, ranges, and only the ten explicit POSIX names listed in Global Constraints. Reject unknown, empty, malformed, or invalid-character POSIX names only when the sequence is an actual POSIX-item attempt; preserve a non-POSIX `[:` as an ordinary class member sequence. Use the class-boundary controls from Task 1 to define negation, leading `]`, and ambiguous double-dash behavior. Validate the MoonBit `re` dialect's bare-dash placement using the known controls (`[a-z-]`, `[-abc]`, `[abc-]` reject; `[a-z]`, `[a\\-z]` accept).
6. Parse quantifiers only as suffixes of an already parsed atom. Native probes show `a{2}`, `a{2,4}`, `a{2,}`, `a{0,3}`, and `a{0}` compile, while `a{,3}` is rejected as incomplete. Allow exactly `{m}`, `{m,n}`, `{m,}` with numeric lower bounds; reject `{,n}`, orphan quantifiers, and stacked quantifiers. Record lower/upper bounds and greediness, and make any accepted lower bound of zero nullable. Encode these probe-confirmed forms in the parser tests.
7. Reject alternation explicitly at every nesting depth because generated matching is longest-match at the lexer level while `re` alternation is leftmost-match. Record it as unsupported and continue scanning so a later malformed delimiter still wins.
8. Run `rtk moon check loomgen` and the focused parser tests after the implementation.

### Task 3: Move nullability onto the shared IR

1. Implement `Pattern::is_nullable` over the parsed structure: an empty sequence and anchors are nullable; consuming atoms are not; a group inherits its child sequence; a quantifier with lower bound zero is nullable; a required quantifier inherits its atom's nullability.
2. Replace the recursive string scanners in `is_nullable_pattern` with a wrapper that calls the parser and returns `true` on parser errors, preserving the conservative direct-call contract.
3. Update `nullable_pattern_wbtest.mbt` so existing nullable/non-nullable cases remain covered and parser errors cannot become false negatives.
4. Run `rtk moon test loomgen/nullable_pattern_wbtest.mbt --target native` and the new parser tests.

### Task 4: Integrate one validation path into annotations

1. Add a small internal validation helper in `parse_annotations.mbt` that maps parser errors to the existing malformed/unsupported diagnostic wording, including the annotation kind (`#loom.pattern` or `#loom.line_pattern`).
2. Replace the current `malformed_re` → `unsupported_re_construct` → `is_nullable_pattern` calls for both annotation kinds with one parse call followed by IR nullability.
3. Preserve validation ordering: role restrictions first, syntax errors next, unsupported constructs next, nullable-pattern rejection after successful parsing.
4. Delete `malformed_re`, `unsupported_re_construct`, `class_end`, `posix_element_end`, and the old string-based nullability helpers once no references remain.
5. Run `rtk moon check loomgen` immediately, then focused annotation tests. Confirm no generated public interface changed with `rtk moon info loomgen`.

### Task 5: Preserve integration and add downstream evidence

1. Extend `emit_lexer_wbtest.mbt` to exercise the shared validator through both `#loom.pattern` and `#loom.line_pattern`, including bare-dash class rejection, allowed escaped dash, nested alternation rejection, and the false-POSIX `[a[:z]X` positive control.
2. Run the pattern lexer golden test and line lexer golden test. Generated output must remain byte-identical; if it changes, stop and determine whether the change is an existing fixture drift or an unintended emitter change before updating anything.
3. Run the compiled/runtime pattern lexer consumer introduced by #526 and verify tokenization, not only source-string equality.
4. Verify that a valid line-pattern fixture still generates and that its payload-bearing `#loom.custom_lex` behavior is unchanged.

### Task 6: Documentation and final verification

1. Update `loomgen/README.md` to state that the listed regex subset is allowlisted and unknown constructs fail closed; document bare-dash class behavior if it is part of the supported dialect boundary.
2. Run `rtk moon fmt loomgen/parse_pattern.mbt loomgen/parse_pattern_wbtest.mbt loomgen/parse_annotations.mbt loomgen/nullable_pattern_wbtest.mbt loomgen/emit_lexer_wbtest.mbt` and inspect all formatting changes.
3. Run focused tests in this order: parser tests, nullable tests, annotation/emitter tests, compiled/runtime fixture tests, then the full `loomgen` package test.
4. Run `rtk moon check --target all`, `rtk moon info loomgen`, and the repository's loomgen generation/parity checks from `loomgen/README.md`.
5. Before PR creation, run `/simplify` review followed by an independent tool-backed review using a different model. Reviewers must cite exact file/line evidence and check that no denylist scanner or duplicate class parser remains.
6. If the implementation closes #529, create/update the relevant ADR because this establishes a reusable generator validation policy; archive this plan only after acceptance criteria and CI evidence are complete.

## Execution Split After Design Review

Keep the tokenizer/parser algorithm and all TDD decisions in the main context. After the mandatory design review passes, use the delegation checkpoint only for mechanically separable work:

- Main context: `parse_pattern.mbt`, parser tests, nullability semantics, error-precedence recovery, and annotation integration.
- Delegated mechanical slice, if useful: fixture regeneration/golden comparison and the README wording/index update. The delegate must not change parser behavior or decide the POSIX grammar.
- Main context reviews every delegated diff and runs the complete verification sequence; subagent success reports are not evidence by themselves.

## Acceptance Criteria

- The safe allowlist is explicit for POSIX names, class boundaries, and counted quantifier forms; every unlisted form fails closed.
- All current valid fixtures and supported pattern forms continue to parse.
- All known fail-open examples, including POSIX boundary mistakes and bare-dash classes, fail during generation with actionable diagnostics.
- Unknown regex constructs fail closed without being emitted into generated source.
- `#loom.pattern` and `#loom.line_pattern` use the same parser and nullability semantics.
- Existing golden output is unchanged unless a separately justified fixture drift is identified.
- The compiled/runtime lexer fixture passes, proving the generated regex and `@core` integration compile and execute.
- No public API change is introduced.
- Native loomgen checks/tests pass. All-target checks are inapplicable because `loomgen/moon.pkg` declares `supported_targets = "+native"`; the attempted all-target command failed before compilation when requesting unsupported Wasm.

## Decision record

- [ADR: Fail-Closed Pattern Allowlist Parser](../../decisions/2026-07-17-pattern-allowlist-tokenizer.md)
