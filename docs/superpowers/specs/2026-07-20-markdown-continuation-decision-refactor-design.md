# Markdown Continuation Decision Refactor

**Date:** 2026-07-20
**Status:** Proposed
**Related:** [Markdown delimiter frontier design](2026-07-20-markdown-delimiter-frontier-design.md); [completed #719 investigation](../../archive/completed-phases/2026-07-20-markdown-delimiter-frontier.md); [ADR 2026-07-20](../../decisions/2026-07-20-markdown-delimiter-frontier.md)

## Context

The Markdown inline parser currently receives a `() -> Bool` continuation callback. The
callback both decides whether the next physical line belongs to the current inline
container and emits the continuation tokens when it succeeds. Root paragraphs and block
quote paragraphs implement this pattern in `examples/markdown/cst_parser.mbt`.

This coupling blocks a safe delimiter-frontier design. A future planner cannot obtain a
closed container plan before it has an authoritative continuation decision, but the
current decision also advances the parser through CST emission. Adding a generic
read-only parser capability or an eager whole-container plan before resolving this seam
would enlarge the scope and introduce unproven `goal_source` and invalidation contracts.

The first change therefore remains a Markdown-local, behavior-preserving refactor. It
separates a typed continuation decision from the effectful operation that applies that
decision. It does not attempt to make the decision statically pure, and it does not add a
core parser API.

## Decision

Replace the untyped continuation callback with a generic typed handler:

```moonbit
enum ContinuationDecision[T] {
  Continue(T)
  Stop
}

struct ContinuationHandler[T] {
  decide : () -> ContinuationDecision[T]
  consume : (T) -> Unit
}
```

`ContinuationDecision[T]` is a generic shape, not a shared Markdown domain enum. Each
continuation owner supplies its own `T`, so a root-paragraph action cannot be passed to a
block-quote consumer.

The inline driver becomes conceptually:

```moonbit
fn parse_indexed_inline_container[T](
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  handler : ContinuationHandler[T],
) -> Unit
```

At a newline, the driver obtains one decision. A `Continue(action)` is passed to the same
handler's `consume`; a `Stop` closes the current inline run. No cross-policy
variant match or `abort("wrong continuation policy")` is required.

## Ownership

The block parser continues to own continuation semantics:

- root paragraph policy owns root paragraph continuation decisions;
- block quote paragraph policy owns block quote continuation decisions;
- setext and list-item policies retain their own continuation decisions; and
- the inline driver only sequences `decide`, `consume`, and inline token parsing.

The inline parser does not infer a final container boundary and does not create an eager
whole-container plan.

## Typed decisions

Root paragraphs use a root-specific action type:

```moonbit
enum RootContinuationKind {
  NoPrefix
  ThematicBreakPrefix
  ListMarkerPrefix
}

fn decide_root_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ContinuationDecision[RootContinuationKind]

fn consume_root_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : RootContinuationKind,
) -> Unit
```

Block quote paragraphs use a distinct action type:

```moonbit
enum ContinuationPrefixKind {
  NoPrefix
  ThematicBreakPrefix
  ListMarkerPrefix
}

enum BlockQuoteContinuationKind {
  MarkerAndPrefix(ContinuationPrefixKind)
  PrefixOnly(ContinuationPrefixKind)
}

fn decide_block_quote_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ContinuationDecision[BlockQuoteContinuationKind]

fn consume_block_quote_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : BlockQuoteContinuationKind,
) -> Unit
```

The other continuation owners also have named action types:

```moonbit
enum BlockQuoteHeadingContinuationKind {
  MarkerAndPrefix(ContinuationPrefixKind)
}

enum SetextContinuationKind {
  NoPrefix
  OrderedMarkerAsText
}

enum ListItemContinuationKind {
  NoPrefix
  IndentationPrefix
  OrderedMarkerAsText
}

enum ListItemSetextContinuationKind {
  NoPrefix
  IndentationPrefix
  OrderedMarkerAsText
}
```

`try_parse_block_quote_setext_heading` uses
`ContinuationDecision[BlockQuoteHeadingContinuationKind]`. The root setext, list-item,
and list-item-setext call sites use their corresponding action types. A policy that never
continues uses a stop-only handler rather than a fake cross-policy action type.


## Observation and consumption

The decision functions preserve the current observation mechanisms:

- `ctx.peek_nth` for non-consuming token inspection;
- existing Markdown boundary helpers; and
- `ctx.lookahead` where the current setext/list-marker rule relies on speculative
  parsing.

A decision function must not directly call `emit_token`, `start_node`, `finish_node`, or
`bump_error`. The effectful operation is explicit in the handler's `consume` function.

This is an observational contract, not a static purity guarantee. A decision may use
`ParserContext::lookahead`, whose implementation can perform temporary parser-owned work
and then restore its own checkpoint. Each `decide_*` function must nevertheless be called
directly on an ordinary parser context in its dedicated purity test, without an outer
`lookahead`. The test snapshots parser position, event count, diagnostics, and reuse state
before and after the call and requires all four to be unchanged. This catches a decision
that commits an effect itself; an outer rollback would otherwise hide that defect.

The driver also retains a separate test for the complete speculative pass wrapped in the
existing outer `lookahead`, verifying that the driver's temporary events and parser state
are rolled back. These are distinct contracts: direct decision observation detects
decision-owned effects, while the driver test verifies speculative integration.

The first refactor does not claim that a closure or a function signature prevents all
side effects. It only makes the intended boundary explicit and keeps all committed CST
effects behind `consume`.

## Representative flow

For a root paragraph:

```text
parse_indexed_inline_container[RootContinuationKind]
  -> scan inline tokens until Newline
  -> handler.decide()
       -> Continue(NoPrefix)
       -> Continue(ThematicBreakPrefix)
       -> Continue(ListMarkerPrefix)
       -> Stop
  -> on Continue(action): handler.consume(action)
  -> on Stop: close the inline run
```

For a block quote paragraph, the same driver is instantiated with
`BlockQuoteContinuationKind`. The type of the handler determines which actions can reach
its consumer.

During speculative delimiter analysis, the existing `lookahead` rollback may execute the
consumer temporarily. Those events are rolled back by the existing parser contract. The
actual parse pass applies the same typed action through the effectful consumer.

## Scope

The refactor changes only the Markdown continuation seam and its driver wiring:

- introduce the generic typed decision and handler shape;
- update `parse_indexed_inline_container` to use the typed handler;
- split root paragraph decision from root paragraph consumption;
- split block quote paragraph decision from block quote consumption;
- migrate setext and list-item continuation call sites to typed handlers; and
- preserve all existing parser behavior.

The refactor does not change:

- `ParserContext`, `token_at`, or `goal_source`;
- parser-session callback contracts or generated grammar interfaces;
- delimiter frontier data structures or production integration;
- container/revision invalidation;
- token-facts copying or read-only cursor capabilities; or
- benchmark baselines.

A future whole-container planner must first identify an independent boundary source or a
core-owned read-only capability. That is a separate design gate, not an implicit result of
this refactor.

## Tests

The refactor must add or update tests for the following observable contracts:

1. Root paragraph decisions distinguish `NoPrefix`, `ThematicBreakPrefix`, and
   `ListMarkerPrefix`, plus block boundaries, blank lines, and EOF.
2. Block quote paragraph decisions distinguish `MarkerAndPrefix` and `PrefixOnly` with
   each `ContinuationPrefixKind`.
3. Block quote setext, root setext, list-item, and list-item-setext decisions each emit
   every named action variant, including no-prefix, ordered-marker-as-text, and indentation
   cases.
4. Setext and list-item continuation behavior remains unchanged.
5. Calling each `decide_*` directly on an ordinary parser context leaves parser position,
   event count, diagnostics, and reuse state unchanged. This call is not wrapped in an
   outer `lookahead`.
6. Running the complete inline driver's speculative pass through the existing outer
   `lookahead` rolls back its temporary parser state and events.
7. Each typed action is consumed only by its matching handler.
8. Existing inline, incremental, source-fidelity, and Markdown block tests continue to
   pass.

No benchmark result is used to claim a performance improvement at this stage.

## Consequences

The inline driver now receives structured continuation facts instead of a boolean, and the
operation that commits CST events is explicit. This creates the smallest boundary needed
to investigate a future incremental frontier without assuming that the final container
boundary is already known.

The design deliberately leaves two limitations visible:

- decision functions still depend on the current `ParserContext` observation APIs; and
- `lookahead` rollback, rather than the type system, enforces the absence of committed
  effects during speculative decisions.

If later measurements show that a read-only offset scan is required, a separate design must
choose between an authoritative block-parser slice and a core-owned read-only capability.
Neither choice is smuggled into this behavior-preserving refactor.
