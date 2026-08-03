# ADR: MarkdownIR exposes one exhaustive typed read view

**Date:** 2026-08-04
**Status:** Accepted
**Issue:** [#862](https://github.com/dowdiness/loom/issues/862)
**Related:** [#861](https://github.com/dowdiness/loom/issues/861),
[MarkdownIR target contract](2026-06-15-markdown-ir-target-contract.md),
[MarkdownIR recovery adapter contract](2026-06-17-markdown-ir-recovery-adapter-contract.md)
**Implementation plan:** N/A — issue-scoped public read-interface change.

## Context

MarkdownIR is an opaque semantic tree. Its private node representation contains
the complete CommonMark distinctions needed by target adapters, but its public
inspection surface grew incrementally as a string kind tag plus unrelated
optional accessors. An external adapter could traverse children and origins,
but could not exhaustively recover link and image titles/reference forms,
ordered-list markers, autolink kinds, hard-break surface forms, or opaque-node
messages without private package access.

Exposing the private storage enum would make representation changes public.
Adding more optional accessors would preserve invalid combinations and leave
new variants invisible to the compiler. A visitor or fold interface would add
another abstraction before multiple concrete traversal strategies require it.

## Decision

MarkdownIR exposes one experimental exhaustive `MarkdownIRView` through
`MarkdownIR::view()`. The closed sum type covers every semantic node and carries
only meaning-bearing scalar and surface metadata. Typed companion values expose
link reference form and origins, autolink kind, and hard-break source form.

Common tree and source-attachment facts remain on the existing uniform
operations:

- `children()` returns a defensive child-array copy;
- `origin()` returns the whole-node half-open UTF-16 source origin;
- `content_origin()` returns the established optional content origin; and
- `diagnostics()` returns a defensive diagnostic-array copy.

The view does not repeat children, common origins, or diagnostics in each
variant. MarkdownIR construction and storage remain private. `view()` maps the
private representation into detached read data; the public view is not adopted
as the internal storage representation merely to avoid this conversion.

Existing kind tags, optional field accessors, and opaque-node predicates remain
source-compatible during the experimental migration. New external adapters
should prefer the exhaustive typed view.

## Rationale

A closed typed view makes adapter completeness a compiler-checked property.
When MarkdownIR gains a semantic variant, exhaustive consumers must make an
explicit policy decision instead of silently treating the node as an unknown
kind string or an empty set of optional fields.

Keeping children and common attachment facts outside the variant payloads
avoids repeating the tree shape and preserves one defensive-copy policy.
Keeping private storage separate retains implementation locality: lowering and
memoization can change without changing the adapter seam, while intentional
semantic schema changes remain visible in the generated interface.

The typed surface expresses necessary CommonMark complexity. It does not expose
CST tokens, arbitrary trivia, reactive cells, editor identity, or target policy.

## Consequences

- External MarkdownIR adapters can be implemented and tested using public
  operations only.
- Link, image, autolink, line-break, list, raw, recovered, and unsupported
  semantics are exhaustively observable without private representation access.
- Adding or changing a MarkdownIR semantic variant is a public experimental
  interface change and requires generated-interface review plus exhaustive
  adapter updates.
- Existing target adapters and compatibility accessors continue to work.
- This decision does not add a reactive attachment, semantic delta, visitor,
  fold, `TreeNode`, `Renderable`, or adapter registry.
