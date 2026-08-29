# ADR: MarkdownIR Recovery Adapter Contract

**Date:** 2026-06-17
**Status:** Accepted; amended 2026-08-28
**Issue:** #334 — remaining MarkdownIR HTML/editor adapter behavior for `Recovered` / `Raw` nodes.
**Implementation plan:** N/A — adapter behavior is pinned by package tests.

## Context

MarkdownIR represents genuinely malformed or unsupported parser output explicitly
instead of encoding recovery as missing semantic fields. The original decision
allowed `Recovered` to carry a parser-facing message such as `"parse error"` and
allowed target adapters to present that message as comments or styled error
content.

That contract conflated two different facts:

- the author-owned source fragment covered by the recovery origin; and
- the parser-owned explanation recorded by diagnostics.

It also classified an unmatched `[` as `ErrorNode` / `Recovered("[")` so later
reference-link resolution could remember that the bracket was a candidate.
CommonMark treats a candidate that does not resolve as ordinary literal text,
not malformed Markdown. Product adapters could therefore expose parser recovery
chrome for valid author text.

## Decision

`Recovered` is reserved for genuine parser recovery.

- Its public String payload is the exact author source slice covered by its
  `MarkdownIROrigin`.
- Its diagnostics carry the parser explanation. A synthesized fallback
  diagnostic uses the generic message `recovered malformed Markdown`; it does
  not embed or replace the source payload.
- A possible reference-link opener is parser structure, not recovery. The CST
  records it as `ReferenceLinkOpenerNode`; MarkdownIR keeps private candidate
  provenance through reference resolution and exposes an unresolved candidate
  as ordinary `Text("[")` with no recovery diagnostics.
- Candidate provenance is finalized only after complete direct or deferred
  reference resolution. It must not be discarded inside a nested emphasis or
  local keyed-lowering step.

MarkdownIR target adapters must still handle `Recovered` and `Raw` explicitly.
They must not drop the author source or infer recovery from absent semantic
fields.

Current target policy is:

- block/editor: block-position raw is a defensive error; recovered content keeps
  the compatibility model's generic parse-error classification;
- inline/editor: raw inline content becomes text; recovered content keeps the
  compatibility model's generic parse-error classification;
- mdast JSON: raw/recovered nodes preserve exact value, origin, and diagnostics;
- CommonMark HTML: raw/recovered values are escaped author text unless the
  distinct valid-raw-HTML policy applies;
- compatibility canonical formatter: raw and recovered source values are emitted
  literally; unsupported content uses an unsupported HTML comment;
- checked canonical formatter: the first preorder raw, recovered, or unsupported
  node is rejected as a structured `OpaqueNode` failure before candidate search;
- preserve/local rewrite: preserve mode keeps source slices and local transform
  splices replacement text into recovered/raw ranges.

Product-facing adapters must render escaped author source without parser terms,
diagnostic lists, or recovery labels in the document body. Diagnostics remain
available as a separate channel. Tooling-oriented adapters may expose recovery
metadata when their interface explicitly promises it.

## Rationale

Separating source payload from diagnostic explanation keeps document text as the
presentation authority while retaining full parser evidence. Distinguishing a
reference candidate from recovery aligns the semantic result with CommonMark and
removes synthetic diagnostics from ordinary unmatched brackets.

The contract remains adapter-neutral: MarkdownIR does not store HTML, Rabbita
nodes, editor widgets, or a product-specific presentation tree. Exact source is
captured only for genuine recovered regions; the complete document remains owned
by the parser snapshot or source-bound document seam.

## Consequences

- `MarkdownIRView::Recovered(value~)` means exact recovered source, not a parser
  message.
- Existing consumers that need a reason read diagnostics or retain a generic
  compatibility error classification.
- Unresolved reference candidates participate in canonical formatting, rewrite,
  mdast, HTML, and editor projection as ordinary text.
- Private candidate state must not appear as `Raw`, `Recovered`, `Unsupported`,
  or a public MarkdownIR view variant.
- A successful checked canonical result still never contains opaque
  compatibility passthrough.
- Future product adapters require tests proving escaped source presentation and
  absence of parser-facing recovery chrome.
