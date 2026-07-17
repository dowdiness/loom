# Refactor `loomgen/parse_pattern.mbt`

**Status:** Planned
**Created:** 2026-07-17
**Related:** [#529](https://github.com/dowdiness/loom/issues/529), [fail-closed parser ADR](../decisions/2026-07-17-pattern-allowlist-tokenizer.md)

## Goal

Reduce the maintenance cost of the private pattern parser without changing the accepted/rejected pattern policy, diagnostic precedence, generated lexer output, or nullability semantics established by #529.

## Why

`loomgen/parse_pattern.mbt` now owns the shared cursor parser, private pattern IR, delimiter/class/escape handling, quantifiers, counted-bound validation, and error-position tracking. The design is correct and intentionally fail-closed, but the implementation is large enough that future syntax extensions may become difficult to review safely.

## Scope

- Map the parser into cohesive responsibilities before moving code.
- Identify seams between cursor mechanics, atom parsing, class/POSIX parsing, quantifier parsing, error precedence, and semantic helpers.
- Extract only boundaries that preserve the package-private API and parser cursor invariants.
- Keep `parse_annotations.mbt` and emitter behavior unchanged unless a proven parser boundary requires a mechanical caller update.
- Strengthen focused tests around every extracted boundary and preserve compiled/runtime fixture coverage.

## Non-goals

- Do not broaden the accepted regex subset.
- Do not change diagnostic precedence or error positions.
- Do not add a public parser or IR API.
- Do not optimize before measuring a demonstrated bottleneck.
- Do not redesign the emitter or annotation syntax.

## Acceptance criteria

- `loomgen` production and white-box tests pass before and after the refactor.
- Existing accepted and rejected pattern cases remain byte-for-byte diagnostic compatible where compatibility is part of the #529 contract.
- Generated lexer fixtures remain unchanged for valid patterns.
- Compiled/runtime pattern fixtures continue to pass.
- The resulting file boundaries make parser ownership and invariants easier to identify without duplicating parsing policy.
- The plan is closed only with an implementation result, evidence, and an explicit ADR decision-record note.

## Suggested execution order

1. Establish a responsibility map and record parser invariants.
2. Add or confirm focused regression tests before structural moves.
3. Extract one responsibility at a time, running targeted MoonBit checks after each edit.
4. Run the full `loomgen` validation and fixture checks.
5. Review the final diff for policy drift and unnecessary public surface.
