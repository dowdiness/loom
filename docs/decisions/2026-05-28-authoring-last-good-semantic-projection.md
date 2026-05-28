# ADR: Authoring Diagnostics and Last-good Semantic Projection

**Date:** 2026-05-28
**Status:** Accepted
**Issue:** [#163](https://github.com/dowdiness/loom/issues/163)
**Guide:** [Last-good Semantic Document Attachment](../api/last-good-semantic-attachment.md)

## Context

Stateful editor integrations need two timelines. Parser diagnostics should
reflect the current source as soon as the parser advances. Semantic documents,
stable-ID tables, and projection reuse caches should not be overwritten by a
malformed recovered CST or by a semantic projection error.

Downstream authoring paths have already used this split: current diagnostics are
shown for malformed input, while the previous successful semantic document and
its source baseline remain available so the next successful projection can reuse
stable IDs and caches.

## Decision

Document a canonical state policy for Loom-backed authoring attachments:

- The `Parser` views remain current-state views. `source`, `syntax_tree`, `ast`,
  and `diagnostics` advance on every parser update.
- A language-owned semantic attachment may retain the last successful semantic
  document, reuse artifacts, and source baseline separately from the parser's
  current snapshot.
- Parser diagnostics gate semantic projection. When parser diagnostics are
  present, the attachment exposes those current diagnostics, skips projection for
  the current text, and keeps last-good semantic state unchanged.
- Projection failures are distinct from parser diagnostics. When projection or
  lowering fails despite an error-free parse, the attachment exposes projection
  diagnostics and keeps last-good semantic state unchanged.
- Only a successful parse plus successful semantic projection replaces the
  last-good semantic document and clears the pending semantic change.
- The next successful projection may reuse the retained last-good document and a
  pending change spanning from the last-good source baseline to the recovered
  current source.
- Compatibility `Result[..., String]` facades are allowed, but they should map a
  blocked current source to `Err` rather than silently returning stale last-good
  semantics as current success.

The canonical implementation shape is an attachment rooted on
`parser.runtime()`: construct the parser with `@loom.new_parser`, derive
semantic state from parser diagnostics and syntax views, hold a persistent
`Watch`, and drive parser edits through the same language-owned facade that
tracks the pending semantic baseline. Do not construct a raw imperative parser
inside a derived computation.

## Rationale

Parser diagnostics and semantic document reuse serve different consumers. The
UI needs current errors immediately. Semantic reuse needs a trusted previous
baseline; replacing it with malformed semantics destroys the information needed
for stable IDs and downstream cache reuse.

Keeping projection diagnostics separate avoids overloading parser diagnostics
with language-owned semantic failures such as mode-incompatible atoms, invalid
cross-reference shapes, or other CST-valid but semantically rejected states.

A language-owned attachment keeps Loom's parser API simple. Loom publishes
current parse snapshots; downstream projects decide which semantic documents are
safe to publish and how to compose or degrade pending edits for reuse.

## Consequences

Loom documentation now names the last-good semantic attachment pattern and links
it from the authoring-only, projection, and pipeline docs.

Parser APIs do not change. Existing users that want current recovered ASTs can
continue reading `parser.ast()`. Users that need last-good semantic retention
should attach downstream state to `parser.runtime()` instead of expecting the
parser to retain semantic documents.

Downstream regression tests for stateful authoring integrations should cover
valid → malformed → recovered transitions and parser-valid projection failures,
including whether stable IDs are reused from the retained last-good baseline.
