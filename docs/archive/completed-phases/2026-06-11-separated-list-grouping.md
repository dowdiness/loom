# Separated-list parsing and delimiter-aware child grouping (#279)

**Status:** Complete (2026-06-11 — PR #285 squash 40235fd, PR #286 squash e7b5efe)
Decision record: [ADR 2026-06-11 separated-list boundary model](../../decisions/2026-06-11-separated-list-boundary-model.md)
**Issue:** [#279](https://github.com/dowdiness/loom/issues/279)
**Related:** #196 (argument projection helpers), #251 (ParserContext author-API boundary)
**Downstream evidence:** moondsp `loom_mini_collect_stack_expr` (dowdiness/moondsp#192),
`docs/loom-upstream-requirements.md` §6

## Problem

Separator-delimited lists (`stack(a, b, c)`, method argument lists) are awkward
to project because argument boundaries are not recoverable from
`SyntaxNode::children()`: separators are tokens, elements may be flat sibling
nodes or tokens, and downstream projections fall back to counting separator
`start()` offsets — fragile arithmetic repeated per construct.

Two complementary pieces close this, and they are designed together because
they must agree on one boundary model:

1. a **projection helper** (seam) that recovers per-element groups from
   existing flat trees, and
2. a **parse-time combinator** (loom core) that records element boundaries in
   the CST so future grammars never need recovery.

**Shared boundary model:** N separators delimit N+1 element slots, and a slot
is never silently dropped — an absent element adjacent to a separator is still
represented (as an empty group at projection time, as an error element at parse
time). A grammar can migrate from flat siblings (piece 1) to wrapped elements
(piece 2) without its projection changing arity behavior.

## Piece 1 — Projection grouping helper (seam)

```text
SyntaxNode::direct_elements_grouped_by(
  separator : RawKind,
  trivia_kind? : RawKind?,
) -> Array[Array[SyntaxElement]]
```

- **Split semantics, N separators → N+1 groups, always.** Leading, trailing,
  and doubled separators produce empty groups. A node with no separator tokens
  yields exactly one group. This matches moondsp's current
  `comma_count + 1` grouping (its consumer skips empty groups itself, so
  value-level parity is preserved — the acceptance evidence in
  `loom-upstream-requirements.md` §6).
- Groups hold **nodes and non-separator tokens in source order**, so the
  helper serves both node-element lists (stack arguments) and token-element
  lists (`.every(2, rev)` — numbers and identifiers are tokens, the #196
  case). Callers filter delimiter tokens (`(`, `)`) out of edge groups.
- `trivia_kind?` filters trivia tokens out of groups when supplied — same
  convention as `nodes_and_tokens(trivia_kind?)`.
- Implemented as a fold over the existing `direct_elements_iter()`; no new
  traversal machinery.

## Piece 2 — Parse-time separated-list combinator (loom core)

```text
ParserContext::separated_list(
  element_kind : K,
  separator : T,
  parse_element : () -> Bool,
) -> Int   // count of element nodes emitted
```

### `parse_element` contract

`parse_element` returns `true` iff it consumed or emitted an element body.
`false` means **"no element starts here"** — it is not a fatal-parse-failure
signal, and `parse_element` must not consume tokens when returning `false`.
Error recovery *inside* a malformed element (partial consumption, error
tokens) is `parse_element`'s own responsibility and still returns `true`.
The combinator owns exactly one conversion: separator-adjacent absence
becomes an empty error element (below).

### Element wrapping — no combinator-owned rollback

The combinator wraps elements **retroactively** via the existing
`mark()` / `start_at(mark, element_kind)` pair (rust-analyzer Marker style):

```text
let m = ctx.mark()
if parse_element() {
  ctx.start_at(m, element_kind)   // retroactive StartNode
  ctx.finish_node()
}
```

Because nothing is emitted before the element body materializes, an empty
list emits no events and there is nothing to undo. The combinator does
**not** use `checkpoint`/`restore`; any checkpoint/restore around
optional-list parsing remains the caller's responsibility, so the combinator
cannot interfere with caller-owned recovery.

### Boundary semantics

Principle: **an empty element slot exists iff it is adjacent to a separator.**

| Input shape | Result |
|---|---|
| `a, b, c` | 3 element nodes, 2 separator tokens |
| `a, b,` (trailing) | 3rd element node containing `emit_error_placeholder()` + diagnostic |
| `, a` (leading) | empty error element in slot 0 |
| `a,,b` (doubled) | empty error element in the middle slot |
| empty input | nothing emitted, returns 0 |

Loop shape: parse one slot (element via marker wrap, or empty error element
if `at(separator)`/absence-after-separator); then if `at(separator)`, emit it
and continue, else stop.

### Scope limits

- **Separator-list scoped only.** No open/close delimiter handling — grammars
  keep owning delimiters and post-list recovery. Delimiter awareness can be a
  later API once the grammar-author boundary (#251) is more settled.
- Built entirely on the public grammar-author method surface (`mark`,
  `start_at`, `finish_node`, `at`, `emit_current_token`,
  `emit_error_placeholder`, `report_expected`) — no new event machinery, no
  new field exposure.
- Defensive guard: if `parse_element` returns `true` without progress, the
  combinator stops (same spirit as `skip_until_progress`) to prevent
  non-termination.

## Delivery

Two **independent PRs, both based on main** (different modules, no code
dependency between the pieces; avoids the stacked-PR CI gap):

- **PR A (seam):** `direct_elements_grouped_by` + whitebox tests. Carries this
  design doc.
- **PR B (loom core):** `ParserContext::separated_list` + whitebox tests.

### Tests

- **seam:** no-separator, leading/trailing/doubled separators, trivia
  filtering, mixed node+token groups, empty node.
- **loom core:** the boundary-semantics table above, empty-input no-emission,
  no-progress guard, and a reuse-safety smoke for the zero-width error
  placeholder at an element boundary (prior art:
  `parser_zero_width_boundary_properties_wbtest.mbt`).

### Follow-ups (not bundled)

- `examples/json` array/object parsing as an in-repo adopter of the
  combinator (changes the JSON example's CST shape — separate PR).
- moondsp migration of `loom_mini_collect_stack_expr` to the grouping helper
  (downstream repo; must keep value-level event parity with its oracle).
