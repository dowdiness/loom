# ADR: Loom defines the Markdown projection attachment; Canopy owns its lifecycle

**Date:** 2026-08-03
**Status:** Accepted
**Issue:** [#332](https://github.com/dowdiness/loom/issues/332)
**Related:** [MarkdownIR performance policy](2026-06-16-markdown-ir-performance-policy.md),
[Markdown projection identity boundary](2026-07-15-markdown-projection-identity-boundary.md),
[Incr post-GC maintenance](https://github.com/dowdiness/incr/issues/444)
**Implementation plan:** N/A — issue-scoped Loom and Canopy integration.

## Context

Loom owns Markdown parsing, semantic lowering, and retained keyed work. Canopy
owns the editor projection, source map, editable roles, and view-node identity.
Loomark owns the mounted application and ends the editor lifetime on unmount.

The keyed MarkdownIR shell is private to `dowdiness/markdown` and attaches to a
live `SyntaxParser`. Returning its watches or maps would make every editor
consumer coordinate graph garbage collection and keyed-cache retirement.
Duplicating the shell in Canopy would split the authoritative lowering path.

Incr 0.15.0 resolved the former cross-package maintenance sequence: after a
terminal read, `Scope::collect()` now owns runtime GC and retirement of every
scope-owned `DerivedMap`. Loom therefore does not need a Markdown-specific
`settle()` operation.

## Decision

Loom exposes one opaque `MarkdownProjectionAttachment`:

```text
attach_markdown_projection(parser) -> MarkdownProjectionAttachment

MarkdownProjectionAttachment
  projection() -> Block
  collect()
  dispose()
```

`projection()` reads a scope-rooted keyed projection and returns a detached
`Block`. Non-recovery blocks are adapted from their resolved local MarkdownIR
through `experimental_markdown_ir_to_block`, the single authoritative adapter.
The terminal document reuses those block-local results and copies the returned
tree so public mutable arrays cannot mutate retained reactive state. Recovery
branches retain the existing live contextual lowering behavior.

`collect()` first reads the terminal Block watch, then delegates graph GC and
all scope-owned keyed-map retirement to `Scope::collect()`. It is called only
at an editor-selected safe point after a successful atomic projection commit.
`dispose()` releases the attachment scope and is idempotent. The attachment
does not own or dispose its parser.

Canopy's typed Markdown editor adapter is the direct owner of the attachment.
Loomark owns that editor and transitively disposes it; Loomark never receives
the Loom attachment. The separate Canopy integration must add the matching
commit-time collection and teardown hooks before this path is enabled there.

Direct one-shot MarkdownIR lowering remains stateless. `Parser[Block]`,
`Block` / `Inline`, parser snapshots, semantic identity tracking, source-map
construction, editable CST roles, and view identity remain separate contracts.
The attachment exposes none of its IR, keys, counters, watches, or semantic IDs.

## Rationale

This is the smallest interface that crosses the repository boundary while
keeping lifecycle invariants enforceable. Loom alone knows which derived maps
form one Markdown projection; Incr alone knows how scope maintenance is
performed; Canopy alone knows when an editor commit is complete.

Returning a detached `Block` keeps the existing editor model and prevents an
adapter from retaining or mutating Loom's cached arrays. Keeping semantic
identity and exact editable roles out of the attachment preserves their
different authorities: MarkdownIR origins describe semantic source attachment,
while CST token spans and Canopy source maps describe exact current editing.

## Consequences

- The Markdown package gains one intentional public attachment and generated
  interface change; keyed implementation types remain private.
- Projection consumers call one maintenance operation and never call runtime
  GC or individual map sweeps.
- One-shot export, audit, render, and formatting paths allocate no keyed cache.
- The direct `Parser[Block]` compatibility path remains until the separate
  Canopy PR proves projection, source-map, edit, diagnostic, and identity parity.
- The 2,500-block production benchmark includes Block conversion and defensive
  copying. On the recorded machine, the keyed attachment is materially faster
  than direct whole-document IR-to-Block lowering on JavaScript and wasm-gc.
- The existing compatibility `Parser[Block]` is still much faster on the same
  local-edit corpus. Enabling the attachment in Canopy therefore requires an
  explicit product-level performance decision or further optimization; this
  Loom change does not silently switch editor consumers.
