# Markdown Continuation Decision Refactor

**Date:** 2026-07-20
**Status:** Implemented
**Related:** [Markdown delimiter frontier design](2026-07-20-markdown-delimiter-frontier-design.md); [completed #719 investigation](../../archive/completed-phases/2026-07-20-markdown-delimiter-frontier.md); [ADR 2026-07-20](../../decisions/2026-07-20-markdown-delimiter-frontier.md)

## Context

Before this refactor, the Markdown inline parser received a `() -> Bool`
continuation callback. The callback both decided whether the next physical line
belonged to the current inline container and emitted continuation tokens when it
succeeded.

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

Replace the untyped continuation callback with a generic decision plus a
Markdown-private action capability:

```moonbit
enum ContinuationDecision[T] {
  Continue(T)
  Stop
}

priv trait InlineContinuationAction {
  fn apply(Self, @core.ParserContext[Token, SyntaxKind]) -> Unit
}
```

The continuing driver accepts only the owner-local decision closure:

```moonbit
fn[T : InlineContinuationAction] parse_indexed_inline_container(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  decide : () -> ContinuationDecision[T],
) -> Unit
```

At a newline, the driver obtains one `ContinuationDecision[T]`.
`Continue(action)` dispatches through `T::apply`; `Stop` closes the current
inline run. The previous arbitrary `consume` closure no longer crosses the
driver boundary.

Policies that are always line-bound continue to use the separate non-generic
`parse_indexed_inline_container_without_continuation` entry point. That path has
no type parameter or fake continuation action.

## Ownership

The block parser continues to own continuation semantics:

- block-container transitions produce `BlockContinuationAction`;
- `cst_parser.mbt` owns the action's `InlineContinuationAction` implementation;
- repeated nested block quotes own
  `RepeatedNestedBlockQuoteContinuation` and its implementation; and
- the inline driver only sequences decision, action application, and inline
  token parsing.

The inline parser does not infer a final container boundary and does not create
an eager whole-container plan.

## Typed decisions

Root paragraphs, setext headings, block quotes, and list items derive
`BlockContinuationAction` from their existing block-container transition
functions. That private enum carries only the effects already required by those
transitions:

```moonbit
enum BlockContinuationAction {
  ContinueNoPrefix
  ContinueIndentedStructuralPrefix
  ContinueListMarkerPrefix
  ContinueIndentationPrefix
  ContinueOrderedMarkerAsText
  ContinueQuoteMarker(ContinuationPrefixKind)
  ContinueQuoteLazy(ContinuationPrefixKind)
}
```

Repeated nested block quotes require an owner-local wrapper because they can
either consume another nested marker run or delegate to an existing block quote
action:

```moonbit
enum RepeatedNestedBlockQuoteContinuation {
  ContinueNestedMarkers(BlockQuotePrefixOwnership, Int)
  ContinueExistingQuote(BlockContinuationAction)
}
```

Each action type implements the private capability beside the code that owns its
CST effects. The generic driver therefore cannot pair a decision with an
unrelated consumer closure.

## Observation and application

Decision functions preserve the current observation mechanisms:

- `ctx.peek_nth` for non-consuming token inspection;
- existing Markdown boundary helpers; and
- `ctx.lookahead` where setext or list-marker rules require speculative parsing.

A decision function must not leave committed parser effects. Direct decision
tests compare the observable `ParserContext` cursor, node, lex mode, and event
length before and after each call.

This remains a reviewed contract, not a static purity guarantee. The decision
closure captures the full `ParserContext`, and `InlineContinuationAction::apply`
also receives it. Both decision and application may run speculatively and more
than once. They may mutate only `ParserContext` state covered by its checkpoint;
external state, I/O, and non-checkpointed configuration are outside the
contract. Invocation count is not observable behavior.

The action trait removes an arbitrary closure pairing and keeps application
code owner-local. It does not make effects pure or restrict the
`ParserContext` capability.

## Representative flow

```text
parse_indexed_inline_container[BlockContinuationAction]
  -> scan inline tokens until Newline
  -> decide()
       -> Continue(action)
       -> Stop
  -> on Continue(action): BlockContinuationAction::apply(action, ctx)
  -> on Stop: close the inline run
```

During speculative delimiter analysis, the existing `lookahead` rollback may
apply an action temporarily. Those parser events are rolled back by the existing
checkpoint contract. The actual parse pass re-evaluates the decision and applies
the resulting typed action. The number of evaluations or applications is not a
contract.

## Scope

The refactor changes only the Markdown continuation seam and driver wiring:

- retain the generic typed continuation decision;
- replace `ContinuationHandler[T]` with the private
  `InlineContinuationAction` capability;
- keep decisions at existing block-parser call sites;
- keep action application beside each owner-local action type;
- preserve the non-generic line-bound entry point; and
- preserve parser behavior.

The refactor does not change:

- `ParserContext`, `token_at`, or `goal_source`;
- parser-session callback contracts or generated grammar interfaces;
- delimiter frontier data structures or production integration;
- container or revision invalidation;
- checkpoint coverage; or
- public Loom APIs.

A future whole-container planner must first identify an independent boundary
source or a core-owned read-only capability. That remains a separate design
gate.

## Tests

Direct decision tests remain limited to observations available through the
existing `ParserContext` API. They verify that decisions preserve the current
token range, current node kind, lex mode, and event length. Diagnostics and
incremental reuse behavior remain covered by complete driver and package tests.

The observable contracts are:

1. Root, setext, block-quote, and list-item decisions preserve all existing
   continuation cases.
2. Calling each `decide_*` directly leaves observable parser state unchanged.
3. Applying a continuation action inside `ParserContext::lookahead` restores
   both the token cursor and parser event length.
4. Re-evaluating from restored parser state produces the same typed action and
   payload.
5. Each action is applied only through its matching private trait
   implementation.
6. Line-bound parsing uses the non-generic entry point.
7. Existing inline, incremental, source-fidelity, and Markdown block tests pass
   on JavaScript and wasm-gc.

The former test that asserted two callback invocations was removed because it
tested a two-pass implementation detail. Its replacement applies one action
inside `ParserContext::lookahead` and checks the two state classes that action
mutates: token position and parser events.

## Follow-up performance decision

On 2026-09-11, a bounded prototype allowed the speculative analysis pass to
commit directly when every token was known to emit as plain inline text. Five
alternating refactor-only baseline/candidate pairs were measured in separate
worktrees with release builds:

| Row | JavaScript | wasm-gc |
|---|---:|---:|
| representative CST | -0.61 ± 4.16% | +1.31 ± 6.12% |
| representative CST + MarkdownIR | -0.12 ± 5.04% | +3.78 ± 13.25% |
| matched plain CST | -20.31 ± 3.25% | -10.11 ± 8.81% |
| mixed Markdown CST | -10.42 ± 2.76% | -12.96 ± 5.65% |
| HTML control CST | +2.85 ± 4.61% | +2.76 ± 2.84% |
| fenced-code control CST | +0.93 ± 2.20% | -0.53 ± 1.47% |
| tokenize only | +1.02 ± 2.20% | +2.05 ± 3.16% |
| incremental edit + restore | +0.23 ± 1.00% | +0.50 ± 5.99% |

Negative percentages are improvements. The plain and mixed Markdown rows show
large improvements on both targets. Representative parsing remains effectively
neutral. HTML controls nominally exceed the two-percent budget, but the absolute
changes are small, their pair-to-pair dispersion overlaps zero, and the
tokenize-only movement confirms measurement noise outside the changed parser
path. The maintainer accepted that bounded risk and adopted the optimization.
Claims remain limited to the measured plain and mixed workloads.

## Consequences

The inline driver receives structured continuation facts rather than a boolean,
and CST application is selected by an owner-local private trait implementation.
This is a smaller and less forgeable seam than the previous paired closures
without claiming effect purity.

Two limitations remain explicit:

- decision functions and action implementations still receive the full
  `ParserContext`; and
- `lookahead` rollback, not the type system, prevents committed effects during
  speculative passes.

When analysis sees only tokens whose final CST kind is `TextToken`, its existing
checkpoint becomes the committed parse. Any delimiter, code, link, angle, or
other syntax candidate restores the checkpoint and follows the unchanged full
inline parser. Future fast paths still require their own correctness proof and
representative control measurements.
