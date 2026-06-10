# ADR: Separated-List Boundary Model (Parse-Time Combinator + Projection Grouping)

**Date:** 2026-06-11
**Status:** Accepted
**Issue:** [#279](https://github.com/dowdiness/loom/issues/279)
**Related:** [#196](https://github.com/dowdiness/loom/issues/196), [#251](https://github.com/dowdiness/loom/issues/251)
**Implementation plan:** [archived design](../archive/completed-phases/2026-06-11-separated-list-grouping.md), [archived plan](../archive/completed-phases/2026-06-11-separated-list-grouping-plan.md)
**Shipped:** PR [#285](https://github.com/dowdiness/loom/pull/285) (seam, squash 40235fd), PR [#286](https://github.com/dowdiness/loom/pull/286) (loom core, squash e7b5efe)

## Context

Separator-delimited lists (`stack(a, b, c)`, method argument lists) were
awkward to project: separators are tokens, elements may be flat sibling nodes
or tokens, and downstream projections (moondsp) reconstructed argument
boundaries by counting separator `start()` offsets — fragile arithmetic
repeated per construct.

## Decision

One boundary model, applied at two layers:

**N separators delimit N+1 element slots, and a slot is never silently
dropped.** An absent element adjacent to a separator is still represented —
as an empty group at projection time, as an error element at parse time.

- `SyntaxNode::direct_elements_grouped_by(separator, trivia_kind?)` (seam)
  splits direct children into N+1 element groups, preserving empty groups for
  leading/trailing/doubled separators. Groups hold nodes and non-separator
  tokens in source order; only *tokens* of the separator kind split.
- `ParserContext::separated_list(element_kind, separator, parse_element)`
  (loom core) wraps each element in its own node so new grammars record
  boundaries in the CST. `parse_element` returns `true` iff it consumed or
  emitted an element body; `false` means "no element starts here" and must
  not consume. Empty slots adjacent to a separator become `element_kind`
  nodes holding a zero-width error placeholder plus an `expected element`
  diagnostic; empty input emits nothing and returns 0.
- Elements are wrapped retroactively (`mark`/`start_at`) — the combinator
  owns no `checkpoint`/`restore`, so caller-owned recovery is unaffected.
  Each slot first tries incremental subtree reuse, mirroring `node()`.

Because both layers agree on the slot model, a grammar can migrate from flat
siblings (projection grouping) to wrapped elements (combinator) without its
projection changing arity behavior.

## Alternatives Considered

- **Node-only projection groups** — rejected: token-argument grammars
  (`.every(2, rev)`; #196) would still need offset math.
- **Strict trailing-separator error (diagnostic only, no error element)** —
  rejected: projections lose the position of the missing argument.
- **Full open/close delimited-list combinator** — deferred: delimiter
  awareness expands the grammar-author surface while the #251 API boundary is
  unsettled; grammars keep owning delimiters and post-list recovery.

## Consequences

- moondsp's comma-offset grouping (`loom_mini_collect_stack_expr`) can migrate
  to `direct_elements_grouped_by`; value-level oracle parity must be
  preserved (empty groups are skipped by the consumer, matching prior
  behavior).
- `examples/json` array/object parsing is a candidate in-repo adopter of the
  combinator (changes that example's CST shape; separate effort).
- A future delimiter-aware combinator builds on this one after #251 settles.
