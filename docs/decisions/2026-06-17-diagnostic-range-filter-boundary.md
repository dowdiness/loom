# ADR: Diagnostic Range Filter Boundary

**Date:** 2026-06-17
**Status:** Accepted
**Issue:** N/A — investigation/design slice from `project-loom-diagnosticset-span-filter-opportunity`.
**Implementation plan:** N/A — no Loom-core public API change.

## Context

MarkdownIR recovery work exposed a possible Loom-core ergonomics gap: downstream semantic layers sometimes need to attach parser or lexer diagnostics to semantic nodes by source span. The immediate MarkdownIR implementation filters `DiagnosticSet::items()` against a node origin and attaches matching diagnostics to `Raw` / `Recovered` nodes.

Before standardizing that as a core helper, the existing API surface was checked:

- `DiagnosticSet::items()` and `DiagnosticSet::map()` already expose diagnostic iteration for language-local predicates.
- `Diagnostic.primary` is already a public readable field in the generated interface; adding `Diagnostic::primary()` would be additive but redundant today.
- `TextRange::{start,end,length,offset_by}` expose validated UTF-16 code-unit spans, but no public containment/overlap predicates.
- `Range::{contains,overlaps}` already provide half-open `Int` span predicates and are re-exported by `@loom`.
- `ParserContext::replay_reused_diagnostics` contains private parser-reuse policy: primary ranges must be contained in a reused node span, with special zero-width right-boundary and EOF ownership rules.

Current downstream evidence is narrow. The only production semantic attachment call site found is MarkdownIR's range filter. Parser-internal replay is not precedent for a general downstream attachment contract because it answers a different ownership question.

## Decision

Do not add Loom-core public `DiagnosticSet` range filters, `Diagnostic::primary()`, or `TextRange` overlap/containment helpers yet.

Downstream semantic-node diagnostic attachment remains language-local for now. Callers should use `DiagnosticSet::items()` (or `map`) with an explicit local predicate that documents the ownership semantics they need.

MarkdownIR keeps its local policy: a diagnostic with a primary range attaches to an origin when the two half-open ranges have positive overlap. This excludes zero-width diagnostics exactly at the origin start or end, but includes zero-width diagnostics strictly inside a non-empty origin.

## Rationale

A core `DiagnosticSet::filter_by_range` would freeze semantics before Loom has enough consumers to know which policy is reusable. The likely variants are not interchangeable:

- parser replay wants containment plus right-boundary/EOF ownership exceptions;
- MarkdownIR recovered/raw attachment wants simple positive overlap;
- future editor integrations may need label/token evidence, secondary spans, or different zero-width boundary ownership.

The lowest-risk reusable layer, if repeated need appears, is `TextRange` predicates with explicit zero-width documentation and tests. Higher-level `DiagnosticSet` filters should wait until at least two downstream consumers repeat the same semantics.

## Consequences

- Parser signatures and generated Loom-core `.mbti` public API remain unchanged.
- MarkdownIR documents its local range policy in code and tests rather than relying on parser-internal replay behavior.
- Future public API proposals must re-run Existing API First against `DiagnosticSet::items`, `DiagnosticSet::map`, `Diagnostic.primary`, `TextRange` accessors, and `Range::{contains,overlaps}`.
- If future evidence justifies core helpers, prefer tiny `TextRange` predicates first; add `DiagnosticSet` filters only after a shared attachment semantic is proven.
