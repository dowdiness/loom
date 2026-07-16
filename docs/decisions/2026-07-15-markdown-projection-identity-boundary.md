# ADR: Markdown projection identity remains semantic and view-local

**Date:** 2026-07-15
**Status:** Accepted
**Implementation plan:** [Markdown projection identity implementation plan](../archive/completed-phases/2026-07-15-markdown-projection-identity.md)
**Related:** [#341](https://github.com/dowdiness/loom/issues/341), [#332](https://github.com/dowdiness/loom/issues/332)

## Context

MarkdownIR surface syntax can change without changing the author's semantic unit:
heading form, list marker spelling, code-fence spelling, and link-label
formatting are examples. Generic projection realignment alone cannot recognize
all such rewrites when their edit windows cover unchanged content.

The Markdown package has no `ProjNode` or `SourceMap` constructor. The current
editor attachment is owned by Canopy's `SyncEditor[@markdown.Block]`
compatibility path. Adding a Loom-local parallel path mapping would invent an
unusable public contract and would duplicate that owner's responsibility.

## Decision

Markdown owns a private adapter that extracts content-attached typed semantic
leaves from MarkdownIR, previews the complete sequence through
`ProjectionIdentityTracker`, applies collision-safe Markdown-local continuity
only for unique unchanged semantic payloads, then commits one complete
last-good baseline.

`MarkdownNodeId` is not a `Block`/`Inline` field, source offset, projection
path, `ProjNode` allocation, or `SourceMap` identifier. Raw, recovered, and
unsupported nodes receive no durable ID. Failed input retains the last-good
baseline until a later successful projection.

Concrete `MarkdownNodeId` to current `Block`/`Inline` and `ProjNode` path
attachments are deferred to the Canopy compatibility owner. That integration
must construct the association from each current projection and discard it on
rebuild; it must not persist view-local data in the Markdown baseline.

## Rationale

The Markdown adapter can correctly decide semantic continuity because it owns
MarkdownIR origins, typed keys, and surface-normalized link-label comparison.
The editor host alone owns concrete view nodes and paths. Keeping these
responsibilities separate prevents a renderer allocation or tree shape change
from becoming an authoring-identity change.

## Consequences

- Surface-only Markdown rewrites retain IDs only when their semantic payload is
  unchanged and correspondence is unique.
- Semantic payload and typed-key changes receive fresh IDs.
- A future Canopy integration must add its own behavior test proving a stable
  Markdown ID can point to a rebuilt, differently pathed current view node.
- Loom's existing `Block` / `Inline` and parser APIs remain unchanged.
