# ADR: Two-Parser Design — ImperativeParser and ReactiveParser

**Date:** 2026-03-02
**Status:** Accepted — **Superseded by** [2026-04-17: Unified Parser](2026-04-17-unified-parser-proposal.md) (2026-04-18)

## Context

loom provides two parsers. This ADR records why both exist, what distinguishes them,
and the intended future trajectory.

## Decision

Keep two parsers with distinct update models:

- **`ImperativeParser`** — caller drives with explicit `Edit { start, old_len, new_len }` commands.
  Enables node-level CST reuse via `ReuseCursor`. Stateful session wrapper around a stateless core.
- **`ReactiveParser`** — caller sets source; `Signal`/`Memo` pipeline decides what to recompute.
  Composable with `@incr` reactive graphs. Stateless from the caller's perspective.

## Why both exist

Both are incremental — at different granularities:

| | `ImperativeParser` | `ReactiveParser` |
|---|---|---|
| Reuse granularity | CST node level (requires edit location) | Pipeline stage level (equality check) |
| Update model | `edit(Edit, String)` | `set_source(String)` |
| Reactive composition | Impossible — stateful across calls | Natural — Signal/Memo chain |
| Best for | CRDT text ops, high-frequency edits | Language servers, build tools, reactive UIs |

Node-level reuse is fundamentally impossible without knowing where the edit happened.
This constraint makes a separate imperative API necessary.

## Future trajectory

The Hazel project (tylr 2022, teen tylr 2023, Grove POPL 2025) shows the long-term path:

1. **Typed holes** — enrich error recovery to produce typed holes instead of untyped error
   nodes, enabling type checking and evaluation through incomplete expressions.
2. **Gradual structure editing** — token-level edit freedom with structural obligations
   auto-inserted (teen tylr's approach). `ImperativeParser` is the natural foundation.
3. **CRDT on action logs** (Grove) — CRDT operates on structured edit actions rather than
   text diffs. `ImperativeParser` handles the text-input path; `@incr` handles propagation.

In this trajectory, `ImperativeParser` remains the text-editing input path.
`ReactiveParser`'s `@incr` foundation expands to cover the full pipeline.

## References

- [eg-walker CRDT](https://arxiv.org/abs/2409.14252)
- [rust-analyzer interner design](https://github.com/rust-lang/rust-analyzer/tree/master/crates/intern)
- [Total Type Error Localization and Recovery with Holes (POPL 2024)](https://dl.acm.org/doi/10.1145/3632910)
- [Gradual Structure Editing with Obligations (VL/HCC 2023)](https://hazel.org/papers/teen-tylr-vlhcc2023.pdf)
- [Grove: Collaborative Structure Editor (POPL 2025)](https://hazel.org/papers/grove-popl25.pdf)
