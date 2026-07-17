# ADR: Fail-Closed Pattern Allowlist Parser

**Date:** 2026-07-17
**Status:** Accepted
**Implementation plan:** [completed pattern allowlist tokenizer plan](../archive/completed-phases/2026-07-17-pattern-allowlist-tokenizer.md)

## Context

Loom's `#loom.pattern` and `#loom.line_pattern` validators previously used overlapping string scanners. Unsupported regex syntax could pass validation and later fail when emitted as a MoonBit `re` literal. Nullability and annotation diagnostics also had separate parsing paths.

## Decision

Use one package-private cursor parser with a private pattern IR for both annotations. The parser owns allowlisted atoms, escapes, classes, POSIX names, delimiters, quantifiers, and error precedence. Quantifiers are represented as `Pattern::Quantified(Pattern, Quantifier)`, where `Quantifier` stores the quantifier kind and counted bounds use validated `Count`/`CountRange` values limited to the native `re` bound of 256. Lazy suffix syntax is consumed by the parser and rejected as unsupported; it is not retained as an IR field because no downstream behavior can use greediness. Validation consumes the IR for nullability and rejects unsupported or malformed syntax before lexer generation.

## Rationale

A single fail-closed parser prevents scanner drift at class and delimiter boundaries, preserves deterministic diagnostics, and keeps the emitter's raw-pattern output unchanged. Parser-level tests and generated/runtime fixtures provide evidence for the accepted subset and rejected constructs.

## Consequences

New regex constructs require an explicit parser and test change. Existing generated lexer goldens remain byte-identical, while invalid constructs fail during annotation processing instead of in generated consumer code.
