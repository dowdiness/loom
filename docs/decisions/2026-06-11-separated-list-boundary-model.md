# ADR: Separated-List Boundary Model (Parse-Time Combinator + Projection Grouping)

**Date:** 2026-06-11
**Status:** Accepted
**Issue:** [#279](https://github.com/dowdiness/loom/issues/279)
**Related:** [#196](https://github.com/dowdiness/loom/issues/196), [#251](https://github.com/dowdiness/loom/issues/251), [#291](https://github.com/dowdiness/loom/issues/291)
**Implementation plan:** [archived design](../archive/completed-phases/2026-06-11-separated-list-grouping.md), [archived plan](../archive/completed-phases/2026-06-11-separated-list-grouping-plan.md)
**Shipped:** PR [#285](https://github.com/dowdiness/loom/pull/285) (seam, squash 40235fd), PR [#286](https://github.com/dowdiness/loom/pull/286) (loom core, squash e7b5efe)
**Follow-up:** PR [#293](https://github.com/dowdiness/loom/pull/293) extends the parse-time combinator with missing-separator recovery and wrapper-free adoption for existing CST shapes.

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
- `ParserContext::separated_list(element_kind, separator, parse_element,
  element_start?, wrap_element?)` (loom core) wraps each parsed element in its
  own node by default so new grammars record boundaries in the CST.
  `parse_element` returns `true` iff it consumed or emitted an element body;
  `false` means "no element starts here" and must not consume. Empty slots
  adjacent to a separator become `element_kind` nodes holding a zero-width
  error placeholder plus an `expected element` diagnostic; empty input emits
  nothing and returns 0.
- `element_start` is optional non-consuming lookahead for missing-separator
  recovery. If a slot progressed, no separator follows, and `element_start()`
  is true, the combinator emits a zero-width error placeholder plus an
  `expected separator` diagnostic, then continues with the next slot. The
  default predicate is false, preserving separator-only list termination.
- `wrap_element=false` is the migration path for grammars whose element parser
  already owns the desired CST node shape. Parsed element events are left as
  emitted by `parse_element`; empty slots emit the zero-width placeholder
  directly; combinator-level element reuse is disabled, so reuse should live in
  the caller's element parser (usually via `ctx.node`).
- In wrapped mode, elements are wrapped retroactively (`mark`/`start_at`) — the
  combinator owns no `checkpoint`/`restore`, so caller-owned recovery is
  unaffected. Each slot first tries incremental subtree reuse, mirroring
  `node()`.

Because both layers agree on the slot model, a grammar can migrate from flat
siblings (projection grouping) to wrapped elements (combinator), or to
wrapper-free `separated_list` calls for existing CST shapes, without changing
projection arity behavior.

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
- `examples/json` array/object parsing uses wrapper-free `separated_list` so
  the example exercises the shared recovery contract without changing its
  existing value/member CST shape.
- A future delimiter-aware combinator builds on this one after #251 settles.
