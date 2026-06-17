# ADR: MarkdownIR Recovery Adapter Contract

**Date:** 2026-06-17
**Status:** Accepted
**Issue:** #334 — remaining MarkdownIR HTML/editor adapter behavior for `Recovered` / `Raw` nodes.
**Implementation plan:** N/A — this slice locks existing adapter behavior with documentation and tests.

## Context

MarkdownIR represents malformed or unsupported source explicitly as `Recovered` or `Raw` nodes rather than encoding recovery as absent semantic fields. Earlier #334 slices covered raw/recovered diagnostics at the MarkdownIR and mdast surfaces. The remaining ambiguity was target-adapter behavior: editor adapters, export adapters, formatters, rewrite modes, and future HTML adapters need explicit handling so malformed input is never silently discarded or mistaken for valid Markdown.

The existing implementation already had concrete behavior for current targets:

- block/editor conversion maps recovered block content to errors and treats block-position raw as defensive errors;
- inline/editor conversion degrades raw inline content to text and recovered content to inline errors;
- mdast JSON preserves raw/recovered nodes with origin and diagnostics;
- canonical formatting passes raw text through and emits recovered comments;
- preserve/local rewrite modes retain source slices or splice explicit replacement text.

The decision needed for this slice was whether to introduce a broader HTML renderer or new public diagnostic APIs. Current evidence does not require either. The safest step is to document the adapter contract and pin existing behavior with tests.

## Decision

MarkdownIR target adapters must handle `Recovered` and `Raw` explicitly. They must not drop these nodes silently, reinterpret malformed source as valid semantic MarkdownIR, or infer recovery from missing required fields.

Current target policy is:

- block/editor: block-position raw is an error; recovered content is an error;
- inline/editor: raw inline content becomes text; recovered content is an error;
- mdast JSON: raw/recovered nodes preserve origin and diagnostics;
- canonical formatter: raw content is emitted literally; recovered content is represented as an HTML comment;
- preserve/local rewrite: preserve mode keeps source slices; local transform splices replacement text into recovered/raw ranges.

Future HTML adapters must define their own `Recovered` / `Raw` behavior explicitly. Recovery-node content should default to escaped/sanitized presentation, comments, or styled error spans. Unescaped passthrough is opt-in only and is distinct from the separate CommonMark raw HTML policy.

## Rationale

Explicit adapter handling keeps recovery presentation at the target boundary, where each consumer can make an appropriate UX/security choice. It also preserves MarkdownIR's invariant that diagnostics and recovery are explicit nodes, not hidden in missing fields or parser-side conventions.

Avoiding a broad HTML renderer keeps this #334 slice focused and does not preempt M5 HTML harness/CommonMark block work. Avoiding new Loom-core diagnostic helpers preserves the language-local diagnostic attachment boundary established by the diagnostic range-filter decision.

## Consequences

- #334's remaining adapter behavior is specified for current targets and future HTML adapters.
- Current behavior is locked by example tests without changing parser signatures or public Loom-core APIs.
- Future adapters must add visible `Recovered` / `Raw` match arms and tests before claiming the M4 adapter exit criterion.
- Raw CommonMark HTML policy remains separate from malformed recovery-node `Raw` handling.
