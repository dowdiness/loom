# ADR: Derive Line/Column Source Locations From Canonical Offsets

**Date:** 2026-05-11
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-05-11-line-index-source-locations.md](../archive/completed-phases/2026-05-11-line-index-source-locations.md)

## Context

Loom's parser, token buffer, CST, diagnostics, and edit machinery use UTF-16
code-unit offsets and lengths. This matches MoonBit string offsets and the
existing `Edit`, `TokenInfo.len`, token-start, and CST-width contracts.

Editor and diagnostic consumers still need line/column positions for display.
The question is whether to store line/column coordinates in parser data
structures or derive them from source text when presenting diagnostics.

## Decision

Keep offsets and lengths as the canonical coordinate system. Add a derived
`LineIndex` helper that maps source offsets to 0-based line/column positions at
presentation boundaries.

Coordinate semantics:

- lines are 0-based
- columns are UTF-16 code-unit offsets within a line
- offsets clamp to `[0, source.length()]`
- `\n`, `\r\n`, and lone `\r` each count as one line break
- non-BMP characters advance columns by 2 code units

Expose:

- `LineCol`
- `LineRange`
- `LineIndex::new(source)`
- `LineIndex::line_col(offset)`
- `LineIndex::line_range(start, end)`
- diagnostic formatting helpers that accept a `LineIndex`

Do not store line/column data on tokens, diagnostics, CST nodes, or syntax
nodes.

## Rationale

Storing line/column coordinates in core parser structures would duplicate data
that is derivable from source text and would complicate incremental updates.
Offsets are already the parser's correctness boundary. Keeping one canonical
coordinate system avoids mismatches between token spans, edit ranges, CST
widths, and diagnostics.

Line/column positions are a display concern. A small derived index gives editor
and diagnostic consumers the presentation coordinates they need without
changing parser internals or reuse decisions.

## Consequences

Parser internals remain offset-based. Consumers that need line/column
formatting build a `LineIndex` from the current source and format diagnostics at
the boundary.

At ADR acceptance time, `Parser::diagnostics()` and
`ImperativeParser::diagnostics()` still exposed `Array[String]`, so structured
parser-level diagnostic APIs were left as follow-up design work. As of
2026-05-14, that follow-up is implemented through `ParseSnapshot[Ast]` and
`DiagnosticSet`. Do not add parser convenience methods that store line/column
coordinates; derive presentation positions from `LineIndex`.

Incremental `LineIndex` maintenance is deferred. Rebuild from source text unless
profiling shows line-index construction is a real editor-loop cost.

## Related Work

PR #112 also introduced `error_token_from_message` plumbing for recoverable
step-lexer errors. That is an API contract follow-up: public docs should state
that message-preserving recovery requires both an `error_token` fallback and an
`error_token_from_message` callback.
