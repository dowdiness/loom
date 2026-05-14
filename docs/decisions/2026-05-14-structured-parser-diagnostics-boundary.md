# ADR: Structured Parser Diagnostics Boundary

**Date:** 2026-05-14
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-05-12-parser-structured-diagnostics.md](../archive/completed-phases/2026-05-12-parser-structured-diagnostics.md)

## Context

Loom had already adopted UTF-16 code-unit offsets as its canonical coordinate
system and added `LineIndex` for presentation-time line/column formatting. The
remaining parser boundary still mixed that model with formatted string
diagnostics and failure-oriented parsing paths:

- high-level parser diagnostics exposed formatted `Array[String]` values
- lexer failures could surface as side-channel parse outcomes
- reactive parsing kept separate source, syntax, AST, and diagnostic state
- example strict parse errors reconstructed language-specific token payloads

This made editor and LSP consumers depend on formatted text or repeat
tokenization work to recover ranges and token evidence.

## Decision

Make the public parser boundary structured and total:

- `Diagnostic`, `DiagnosticSet`, `TextOffset`, `TextRange`, labels, severities,
  codes, and token-erased `TokenEvidence` are the parser-facing diagnostic data
  model.
- Lexing for grammar/factory use returns `LexResult[T]` with diagnostics
  instead of raising for recoverable malformed user input.
- High-level parser updates publish `ParseSnapshot[Ast]`, containing source,
  syntax tree, AST, diagnostics, and reuse count together.
- `Parser` stores one snapshot signal and exposes derived views. Its
  `syntax_tree()` view is total and its `diagnostics()` view returns
  `DiagnosticSet`.
- `ImperativeParser::{parse,edit,reset}` return `ParseSnapshot[Ast]`, and
  `current()` exposes the latest snapshot when available.
- `ParserContext` keeps `DiagnosticSet` internally and exposes structured
  reporting helpers: `report`, `report_error`, `report_at_current`, and
  `report_expected`. The existing `error(String)` helper remains as a
  compatibility wrapper.
- Parser-facing diagnostics may expose token-erased `RawKind` evidence, but not
  language-specific token payloads.
- Example fail-fast `ParseError` types carry formatted messages only; structured
  consumers should use parser snapshots or `parse_*` functions that return
  `DiagnosticSet`.

## Rationale

Diagnostics are data, and formatting is a rendering step. Keeping ranges,
severity, codes, notes, labels, and token evidence structured lets editor
clients, incremental reparsing, and tests consume one diagnostic model without
parsing strings or re-tokenizing source.

Snapshots keep parser updates coherent. Source, tree, AST, diagnostics, and
reuse stats change together, which prevents reactive consumers from observing
mixed epochs.

High-level parsing should be total for malformed user input. Recoverable lexer
and parser errors should produce trees with error or incomplete nodes plus
diagnostics, not missing syntax trees.

Token evidence must be erased at public parser boundaries. Grammar internals can
use language-specific token types, while public diagnostics remain reusable
across language examples and editor integrations.

## Consequences

Consumers that previously read formatted parser diagnostics now receive
`DiagnosticSet` and can call `format()` or `format_with_line_col(LineIndex)` at
presentation boundaries.

Consumers that need atomic parse state should use `Parser::snapshot()` or the
snapshot returned by `ImperativeParser`. Convenience views remain available but
are derived from the snapshot.

Malformed high-level input should no longer be modeled as absent syntax.
Language grammars must provide recoverable lexer boundaries for editor-facing
parser factories.

Example `parse(String)` helpers are intentionally less expressive than parser
snapshots. They are fail-fast convenience APIs; callers that need ranges,
codes, labels, notes, token evidence, or multiple diagnostics should use APIs
that return `DiagnosticSet`.

Line/column coordinates remain presentation-only, following
[ADR: Derive Line/Column Source Locations From Canonical Offsets](2026-05-11-derived-source-locations.md).
