# ADR: Markdown document update evidence

**Date:** 2026-08-30
**Status:** Accepted
**Supersedes:** [Parser-Bound Markdown Semantic Publications](2026-08-30-parser-bound-markdown-semantic-publication.md)
**Implementation plan:** N/A — the production boundary follows a measured throwaway prototype and package-local TDD matrix.

## Context

The parser-bound Markdown optimization proved that Loom can reuse unchanged
top-level semantic blocks while retaining only one previous result. Its public
contract nevertheless assigned monotonic revision keys inside the Markdown
parser adapter. Those keys were consumed as Rabbita lazy keys, so a semantic
producer owned renderer cache policy and callers had to preserve key continuity
when replacing a parser.

A canonical `MarkdownDocument` should not become keyed or unkeyed according to
its consumer. Parser replacement, skipped results, renderer configuration, and
mounted-subtree lifetime also cannot be made safe by an integer generated in the
Markdown package. The parser can prove a semantic correspondence; only the view
can decide whether that evidence permits reuse.

The existing `MarkdownNode` compounded this boundary problem by retaining a
`MarkdownSemanticRead`, which retained the complete document and source. A lazy
render closure that captured one top-level node could therefore retain a whole
old source generation.

## Decision

Keep one canonical detached `MarkdownDocument`. Add an advanced parser-bound
`MarkdownDocumentUpdates` producer that returns completed
`MarkdownDocumentUpdate` values. The producer retains exactly one semantic
baseline and uses the existing conservative incremental lowering algorithm.

Each update provides:

- its canonical `MarkdownDocument`;
- a lightweight opaque `MarkdownPreviousUpdate` value;
- current `MarkdownTopLevelBlock` values; and
- an optional previous-block index for each current block.

A consumer supplies its accepted previous-update value when requesting blocks.
Positive matches are visible only when that value belongs to the same producer
and represents the direct previous result. Missing, skipped, or foreign values
hide every match. `None` means that no safe correspondence was proven; it does
not assert that Markdown content changed.

The match relation is partial and injective. Every index must be within the
direct previous document's top-level block range, and no previous index may
appear twice. Any invalid relation is replaced by an all-unmatched result before
it reaches a consumer.

Matches cover position-independent `MarkdownNodeView` semantics. Diagnostics,
changed link-reference definitions, ambiguous structural edits, recovery nodes,
and unsupported origin shifts fail closed. Source ranges, renderer options, and
other view configuration are outside the match guarantee.

`MarkdownNode` retains only a block-local semantic subtree and a private marker
for its document snapshot. Position-independent traversal stays on the node.
Source-aware operations move to `MarkdownDocument`, which rejects a node from
another snapshot even when source text and `SourceId` are equal.

Markdown allocates no renderer identifier. A view validates the match relation,
combines it with its accepted previous state, and owns lazy-subtree identity and
cache lifetime. Replacing a producer therefore requires no parser-side seed.

The common `IncrementalParser::snapshot() -> MarkdownDocument` contract remains
unchanged. `MarkdownDocumentUpdates` is an advanced adapter for consumers that
already own a `SyntaxParser`; it does not expose the parser runtime through a
detached result.

## Rationale

The contract exposes evidence rather than an optimization algorithm. Physical
CST continuity can later be replaced or supplemented by semantic fingerprints,
dependency tracking, move detection, or a different allocation strategy without
changing consumers. Failing closed lets the implementation begin conservatively
and strengthen proof over time.

Gating match access is safer than exposing raw indices plus a separate
`follows` predicate: callers cannot observe an index while accidentally skipping
the generation check. A private producer marker prevents local sequence counters
from colliding across replacement producers.

Separating semantic correspondence from view keys follows the functional-core /
imperative-shell boundary. Markdown decides canonical lowering and safe matching;
the renderer owns DOM state, lazy keys, policy changes, and acceptance lifecycle.

## Consequences

- `MarkdownSemanticSession`, `MarkdownSemanticPublication`, public revision-key
  allocation, and replacement key seeding are removed without compatibility
  wrappers while the package remains pre-1.0.
- Consumers store `MarkdownPreviousUpdate` alongside their own accepted view
  state and pass it back only when renderer-affecting inputs remain compatible.
- Skipped updates and producer replacement rebuild view keys rather than risking
  stale subtree reuse.
- Top-level matching remains the optimization granularity. Finer-grained reuse
  may be added as a separate capability without changing this relation.
- Link-definition invalidation remains deliberately conservative. A private
  dependency index may narrow it later without changing the API.
- `MarkdownNodeView` uses CommonMark's `Strong` and `Emphasis` terminology; the
  legacy `Bold` and `Italic` names remain only on advanced internal-compatible
  IR and AST surfaces.
- `MarkdownSemanticRead` remains temporarily available for advanced conversion
  and rewriting adapters, but ordinary node traversal no longer retains it.
- Production validation must compare every update document with fresh canonical
  lowering and retain exact-edit, fallback, recovery, skipped-update,
  replacement-producer, performance, and explicit-GC coverage.
