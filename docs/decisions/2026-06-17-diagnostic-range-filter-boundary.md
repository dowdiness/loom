# ADR: Diagnostic Range Filter Boundary

**Date:** 2026-06-17
**Status:** Accepted
**Issue:** N/A — investigation/design slice from `project-loom-diagnosticset-span-filter-opportunity`.
**Implementation plan:** N/A — no Loom-core public API change.
**Qualified by:** the later source-aware diagnostics model adopted through
Canopy issue [#1035](https://github.com/dowdiness/canopy/issues/1035).

## Context

MarkdownIR recovery work exposed a possible Loom-core ergonomics gap: downstream semantic layers sometimes need to attach parser or lexer diagnostics to semantic nodes by source span. The immediate MarkdownIR implementation filters `DiagnosticSet::items()` against a node origin and attaches matching diagnostics to `Raw` / `Recovered` nodes.

Before standardizing that as a core helper, the existing API surface was checked:

- `DiagnosticSet::items()` and `DiagnosticSet::map()` already expose diagnostic iteration for language-local predicates.
- Diagnostic fields are private. `Diagnostic::labels()` returns a defensive
  copy of styled labels, and each label exposes its `SourceSpan`, style, and
  optional message.
- `TextRange::{start,end,length,offset_by}` expose validated UTF-16 code-unit spans, but no public containment/overlap predicates.
- `Range::{contains,overlaps}` already provide half-open `Int` span predicates and are re-exported by `@loom`.
- `ParserContext::replay_reused_diagnostics` contains private parser-reuse
  policy: only `Primary` labels for the current source participate, and their
  ranges must satisfy reused-node ownership rules including zero-width
  right-boundary and EOF cases.

Current downstream evidence is narrow. The only production semantic attachment call site found is MarkdownIR's range filter. Parser-internal replay is not precedent for a general downstream attachment contract because it answers a different ownership question.

## Decision

Do not add Loom-core public `DiagnosticSet` range filters or `TextRange`
overlap/containment helpers yet.

Downstream semantic-node diagnostic attachment remains language-local for now. Callers should use `DiagnosticSet::items()` (or `map`) with an explicit local predicate that documents the ownership semantics they need.

MarkdownIR keeps its local policy: a diagnostic attaches to an origin when at
least one `Primary` label has the current document's `SourceId` and its
half-open range has positive overlap with the origin. `Secondary`,
foreign-source, and non-overlapping labels do not establish ownership.
Zero-width labels exactly at the origin start or end are excluded; under the
existing `Range::overlaps` predicate, a zero-width label strictly inside a
non-empty origin is included. A match attaches the complete diagnostic,
preserving all labels, styles, messages, and source IDs.

## Rationale

A core `DiagnosticSet::filter_by_range` would freeze semantics before Loom has enough consumers to know which policy is reusable. The likely variants are not interchangeable:

- parser replay wants current-source primary-label containment plus
  right-boundary/EOF ownership exceptions;
- MarkdownIR recovered/raw attachment wants current-source primary-label
  positive overlap;
- future editor integrations may need all labels, token evidence, cross-source
  relationships, or different zero-width boundary ownership.

The lowest-risk reusable layer, if repeated need appears, is `TextRange` predicates with explicit zero-width documentation and tests. Higher-level `DiagnosticSet` filters should wait until at least two downstream consumers repeat the same semantics.

## Consequences

- This decision adds no range-filter helper; the later source-aware diagnostic
  migration changes parser signatures and the generated Loom-core interface
  independently.
- MarkdownIR documents its local range policy in code and tests rather than relying on parser-internal replay behavior.
- Future public API proposals must re-run Existing API First against
  `DiagnosticSet::items`, `DiagnosticSet::map`, `Diagnostic::labels`, label/span
  accessors, `TextRange` accessors, and `Range::{contains,overlaps}`.
- If future evidence justifies core helpers, prefer tiny `TextRange` predicates first; add `DiagnosticSet` filters only after a shared attachment semantic is proven.
