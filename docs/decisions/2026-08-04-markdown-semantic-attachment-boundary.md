# ADR: Markdown semantic attachment owns terminal read and collection

**Date:** 2026-08-04
**Status:** Accepted
**Issue:** [#863](https://github.com/dowdiness/loom/issues/863)
**Tracker:** [#861](https://github.com/dowdiness/loom/issues/861)
**Qualifies:** [Markdown projection attachment boundary](2026-08-03-markdown-projection-attachment-boundary.md)
**Related:** [MarkdownIR exhaustive read view](2026-08-04-markdown-ir-exhaustive-read-view.md),
[Incr post-GC maintenance](https://github.com/dowdiness/incr/issues/444)
**Implementation plan:** N/A — issue-scoped public attachment change.

## Context

The private keyed MarkdownIR shell already reuses block-local semantic work,
but its public attachment returned only the smaller legacy `Block` projection.
An external source-aware adapter could lower a one-shot MarkdownIR document,
but a long-lived editor could not obtain that document from its existing
`Parser[Block]` without rebuilding the whole semantic tree on every read or
reaching into private watches, maps, and collection ordering.

The existing projection attachment exposes a caller-selected `collect()`
because Canopy must first commit its detached `Block`. A returned MarkdownIR is
an opaque owning read-only value whose public child and diagnostic collections
are defensive copies. It can therefore be obtained before collection and
safely returned after collection without exposing the maintenance boundary.

## Decision

The Markdown package exposes one experimental opaque attachment:

```moonbit
pub struct MarkdownSemanticAttachment

pub fn MarkdownSemanticAttachment::MarkdownSemanticAttachment(
  parser : @loom.Parser[Block]
) -> MarkdownSemanticAttachment

pub fn MarkdownSemanticAttachment::document(
  self : MarkdownSemanticAttachment
) -> MarkdownIR

pub fn MarkdownSemanticAttachment::dispose(
  self : MarkdownSemanticAttachment
) -> Unit
```

The custom constructor joins the caller-owned parser runtime and observes one
complete `Parser[Block]::snapshot()` through a private normalized snapshot.
Source, syntax, and diagnostics are never read as independently versioned
inputs. The parser remains the only mutation owner.

`document()` performs the terminal Watch read, then calls `Scope::collect()`
before returning the owning MarkdownIR value. This keeps runtime GC and all
scope-owned `DerivedMap` retirement private. `dispose()` is idempotent and does
not dispose the parser. Reading after disposal is a contract violation.

The deterministic CST-and-diagnostic-to-MarkdownIR transformations remain the
functional core. Snapshot observation, terminal reading, collection, disposal,
and disposed-state enforcement form the thin imperative shell.

The existing `MarkdownProjectionAttachment` remains available and unchanged.
Its caller-selected collection boundary is still correct for the legacy
editor-commit workflow; the semantic attachment does not supersede it or make
MarkdownIR the default Canopy/Loomark product path.

## Rationale

One opaque attachment is the smallest interface that gives source-aware
consumers incremental reuse without transferring cache or runtime ownership.
Reading one parser snapshot makes coherence structural rather than a timing
assumption. Returning the owning value before collecting makes maintenance
deterministic while retaining a simple value-oriented consumer interface.

A public revision, delta, acknowledgement, cursor, `collect`, watch, scope, or
cache API would duplicate responsibilities already owned by the parser,
private keyed shell, and downstream reconciliation. A second parser would
create another mutation owner and discard the reuse already present in the
caller's live parser.

## Performance evidence

Release measurements used the existing 2,500-block corpus. A full cycle edits
one middle block, reads the complete result, reverses the edit, and reads again.
Values are mean ± one standard deviation from the final paired run. Repeated
semantic runs are summarized below to expose run-to-run A/A variation.

| Workload | JavaScript | wasm-gc |
|---|---:|---:|
| Fresh MarkdownIR full cycle on `Parser[Block]` | 90.75 ± 3.87 ms | 77.01 ± 4.29 ms |
| Legacy keyed projection full cycle | 29.80 ± 0.99 ms | 21.78 ± 0.83 ms |
| Semantic attachment full cycle | 29.06 ± 1.48 ms | 28.97 ± 3.07 ms |
| Fresh MarkdownIR initial read on `Parser[Block]` | 41.27 ± 1.92 ms | 37.03 ± 1.92 ms |
| Semantic attachment initial read | 78.44 ± 8.51 ms | 69.06 ± 6.10 ms |
| Legacy projection initial read | 108.01 ± 2.93 ms | 126.86 ± 44.70 ms |

The semantic edit cycle is about 3.1× faster than fresh whole-document lowering
on JavaScript and 2.7× faster on wasm-gc. It is in the same measured envelope
as the smaller legacy keyed projection on JavaScript and about 33% slower on
wasm-gc. The remaining cost is private full positioned-IR fan-in plus
deterministic collection after each read. Initial attachment is about 1.9×
slower than direct one-shot lowering and is intended for long-lived consumers,
not batch replacement.

Across repeated runs, semantic edit-cycle means ranged from 27.94 to 37.80 ms
on JavaScript and 28.97 to 32.12 ms on wasm-gc. Semantic initial-read means
ranged from 78.44 to 89.63 ms on JavaScript and 69.06 to 104.40 ms on wasm-gc.
That A/A spread, especially for initial wasm-gc attachment, justifies no
permanent wall-time CI gate. Deterministic invalidation and bounded-cache tests
remain the primary contract.

## Consequences

- Long-lived consumers can read complete source-aware MarkdownIR from their
  existing `Parser[Block]` without a second parser or public cache protocol.
- A retained document remains readable and unchanged after collection, later
  edits, repeated reads, and attachment disposal.
- Every successful public read deterministically bounds stale keyed work; a
  10,000-edit replace/delete test protects this lifetime invariant.
- Direct one-shot MarkdownIR lowering remains non-reactive and unchanged.
- The legacy projection attachment and `Block` / `Inline` compatibility path
  remain available during migration.
- Canopy and Loomark integration requires a separate change that first selects
  a concrete capability unavailable through legacy `Block` / `Inline`.
