# ADR: Markdown source-bound semantic reads

**Date:** 2026-08-10
**Status:** Accepted
**Related:** [Issue #913](https://github.com/dowdiness/loom/issues/913), [MarkdownIR architecture and target contract](../architecture/markdown-ir.md), [MarkdownIR performance policy](2026-06-16-markdown-ir-performance-policy.md), [Markdown semantic attachment boundary](2026-08-04-markdown-semantic-attachment-boundary.md), [Markdown block adapter cutover](2026-08-10-markdown-block-adapter-cutover.md)
**Implementation plan:** Issue-scoped; implement with a parity-first, two-commit migration slice.

## Context

The Markdown package has both semantic MarkdownIR targets and source-aware
compatibility projections. The source-aware paths need exact source spelling,
syntax origins, and recovery details in addition to semantic meaning. Passing
those values independently allows a caller to combine a MarkdownIR value with
source text from a different parser snapshot.

MarkdownIR is intentionally a semantic representation with source origins, not
a copy of the complete source. Its lowering is position-dependent and the
accepted performance policy rejects a document-global memo or a position-
independent cache as a general solution. At the same time, several targets may
need to read one parsed document, and lowering once per target would repeat the
same semantic work.

The existing local-transform rewrite validates a supplied target by numeric
origin containment. Equal offsets from two different reads therefore do not
identify the same snapshot. A new source-aware rewrite seam must make target
selection read-bound rather than accepting a freely transferable
`MarkdownIROrigin`.

The existing attachment contract also distinguishes a retained source-aware
read from the parser and attachment lifecycle. A new high-level seam must keep
that ownership explicit instead of adding another adapter that accepts an
unrelated `(MarkdownIR, source)` pair.

## Decision

Introduce a source-bound document seam and an owning, detached `semantic read`
handle for document-aware consumers.

- A source-bound document owns one coherent parser snapshot: source, syntax, and
a diagnostics view that correspond to the same parser revision.
- `MarkdownDocument::semantic_read()` is the explicit semantic-read entry
point. The document remains lazy with respect to MarkdownIR; creating the
handle captures the snapshot and eagerly lowers MarkdownIR exactly once. The
lowering reuses the document-owned source rather than reconstructing it from the
CST.
- `MarkdownSemanticRead::root() -> MarkdownSemanticReadNode` creates the
read-bound semantic tree view. Its nodes expose only read-only navigation and
inspection (`children()`, `view()`, and observational `origin()`).
- `MarkdownSemanticReadNode::selection(kind~ : MarkdownSemanticSelectionKind)
-> MarkdownSemanticSelection?` creates an opaque selection owned by the same
read. `MarkdownSemanticSelectionKind` covers whole-node, content, destination,
title, and autolink-display targets; a missing target returns `None`.
- `MarkdownSemanticRead::ir()` exposes the immutable MarkdownIR value already
owned by the handle for existing IR-only target adapters. Its raw origins are
not valid inputs to the new source-aware rewrite seam.
- The new document-backed free adapters are
`markdown_semantic_read_to_block`,
`markdown_semantic_read_to_mdast_json_with_positions`, and
`markdown_semantic_read_preserve_rewrite`, plus
`markdown_semantic_read_local_transform_rewrite(selection,
replacement_text~ : String)`. The local-transform adapter accepts the
read-bound selection only and no independently supplied source string.
- HTML, position-free mdast, and canonical formatting remain IR-only targets
and may consume the handle's read-only IR view. Existing direct parser and
compatibility entry points remain available while parity evidence and the
separate cutover decision are completed.
- The one-lowering guarantee is a public handle-structure contract. It is not
represented by a runtime counter, read identity, or document-global memo.
- Existing IR-only target contracts are reused rather than replaced by a fixed
target bundle.

The source-aware adapters must consume the source-bound seam and must not
reintroduce independently supplied source/IR pairs or free rewrite origins.

## Rationale

The handle makes the source/IR pairing a property of one public seam rather
than a caller convention. Eager lowering gives the handle a simple immutable
lifecycle: no hidden mutable lazy state, no first-target timing ambiguity, and
no repeated lowering when targets are composed. Detached ownership lets a
consumer retain a read across parser edits and attachment disposal without
borrowing a live parser.

The read-bound node and selection make the rewrite target part of that same
seam. A caller can navigate and inspect the semantic tree, but the rewrite
operation receives only a selection that already owns the source, syntax, IR,
and target range. This prevents equal numeric offsets from crossing reads
without adding snapshot identity to every existing experimental origin value.

A read-only IR view preserves the existing deep target contract for HTML,
mdast, and semantic formatting without forcing every IR-only consumer through
new wrapper methods. Keeping source-aware targets on the handle prevents those
consumers from accidentally pairing semantic data with unrelated source text.

## Consequences

- The public seam gains a real source-bound ownership model and a compositional
  read handle instead of another shallow adapter.
- Creating a handle pays the MarkdownIR lowering cost even when no target is
  subsequently used; the source-bound benchmark suite measures this path. It
  does not pay an additional complete-source reconstruction because the document
  already owns the coherent source.
- A retained handle keeps its source/syntax/diagnostic snapshot and MarkdownIR
  alive for the value lifetime; callers release it through ordinary MoonBit
  ownership when the read is no longer needed.
- Read-bound node and selection types add public surface, but they keep
  source-aware rewrite targets local to one read and leave raw origin access
  observational only.
- Tests can exercise the public seam by reusing one handle across multiple
  targets, checking source-to-document and direct-to-document parity, and
  reading after the originating parser lifecycle ends. They do not depend on
  private helper names, allocation order, or instrumentation counters.
- Existing direct CST-to-Block and source-aware IR-backed compatibility paths
  remain until a parity-first cutover proves that removing or reclassifying one
  of them is safe. Existing experimental `(MarkdownIR, String)` rewrite
  functions retain their compatibility signatures and are not the canonical
  source-bound seam.
