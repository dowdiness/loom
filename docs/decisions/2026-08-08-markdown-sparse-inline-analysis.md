# ADR: Retain source-backed sparse Markdown inline analysis as a gated experiment

**Date:** 2026-08-08
**Status:** Accepted — default adoption deferred
**Implementation plan:** [prototype note](../../examples/markdown/PROTOTYPE-inline-event-index.md)

## Context

Markdown inline analysis currently materializes owned token text while building
code-span, link, and delimiter facts. A cmark-informed experiment replaces
ordinary text payloads with syntax-bearing source ranges and recovers ordinary
text facts from a bounded `StringView`.

The experiment preserves a lossless CST by reusing the existing parser emitter
and delimiter resolver. It also adds a bounded `ParserContext::source_view`
capability and a guarded full-token fallback.

The isolated parser-shell benchmark improved on a 250-line delimiter-heavy
paragraph, but a real 250-block browser Raw-input probe did not show a reliable
end-to-end improvement. In paired runs, sparse `input_to_render_ms` was
`129.1/174.3 ms` and `137.8/220.5 ms` (p50/p95), versus baseline
`130.8/171.6 ms` and `131.4/174.0 ms`.

## Decision

1. Retain the source-backed sparse representation, source-view boundary, and
   differential/benchmark fixtures as a reusable experiment.
2. Keep the guarded path usable in the isolated Loom worktree for standalone
   parser and parser-stage measurement, but do **not** treat it as a default
   Canopy editor optimization yet.
3. Require every sparse-only invariant failure to return the full-token
   fallback; the guard must remain linear in source order rather than using
   all-pairs candidate validation.
4. Reconsider default adoption only after a future editor profile shows that
   inline parsing is a material part of p95 input latency and the browser seam
   improves without semantic or incremental-parity regressions.
5. Do not broaden `ParserContext::source_view` or the sparse link subset until
   a concrete second source-backed consumer or an adoption decision justifies
   the API and its maintenance cost.

## Rationale

The representation has a sound semantic boundary: source remains spelling
authority, sparse facts are partial, existing CST emission remains authoritative,
and unsupported syntax falls back. The browser result is a deferral signal, not
a rejection of the algorithm; its value can increase if commit/projection/DOM
costs are reduced or standalone parsing becomes the dominant workload.

The explicit gate prevents a local parser benchmark from being mistaken for a
user-visible latency win. The branch and commit remain discoverable through the
prototype note and this ADR, so the experiment can be reactivated from evidence
rather than recreated from memory.

## Consequences

- The prototype benchmark and parity tests are maintained as the re-entry point.
- The current browser measurement is a negative adoption result and should not
  be replaced by the isolated parser numbers.
- A future adopter must update this ADR, run the full parser targets, and repeat
  the 250-block browser p50/p95 probe against the then-current baseline.
- If no consumer reaches the adoption gate, the provisional source-view API and
  sparse production experiment should be removed rather than silently retained.
