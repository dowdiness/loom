# Markdown Container Fact Plan Design

**Date:** 2026-07-23
**Status:** Proposed
**Related:** [ADR: defer Markdown delimiter frontier integration](../../decisions/2026-07-20-markdown-delimiter-frontier.md); [delimiter frontier transport investigation](2026-07-20-markdown-delimiter-frontier-design.md); [implemented continuation decision seam](2026-07-20-markdown-continuation-decision-refactor-design.md); PR [#719](https://github.com/dowdiness/loom/pull/719)

## Context

Markdown currently builds `CodeSpanDelimiterIndex` by parsing an entire inline
container inside `ParserContext::lookahead`. That speculative pass emits every
inline and continuation token, constructs temporary parser events, then rolls
all of them back before the authoritative parse consumes the same container.
The accepted delimiter-frontier ADR deferred replacing this path until a
separate design established a continuation boundary, invalidation, and
performance contract.

PR #737 completed the first prerequisite. It separates each Markdown
continuation owner’s typed `ContinuationDecision[T]` from its effectful
consumer. The decision is observational on a `ParserContext`, but it is not
yet an offset-driven, reusable boundary rule.

`ParserContext::token_at(offset, goal=0)` can read baseline token facts without
changing parser position only while `goal_source` is absent. Markdown does not
configure `goal_source`; repository uses are confined to core goal-token-source
tests. `token_at` has no public baseline-only variant and no public
`has_goal_source` predicate, so this design must make no-goal-source a
Markdown-local grammar invariant rather than add a core API.

## Decision

Investigate a Markdown-local **container fact plan** that replaces the
speculative CST-emitting delimiter prepass only when its isolated benchmark and
calibrated production evidence pass.

A plan is created for exactly one actively parsed inline container. It is
neither stored in `ParserContext` nor retained after the container returns.
Unchanged inline CST subtrees reused by incremental parsing do not create a
plan; a newly parsed container always creates a fresh one. This gives the first
integration revision-local invalidation without a cache identity API.

The plan uses a caller-owned source offset and `token_at(offset, goal=0)` to
walk baseline token facts. It contains:

- the container’s exact exclusive end offset;
- the typed continuation action for each continuing newline, keyed by that
  newline’s source offset; and
- equal-length backtick-run successor facts that never cross the container end.

The planner does not emit tokens, start or finish nodes, add diagnostics, or
change parser position. The authoritative inline parser alone calls the
existing typed continuation consumer and emits the CST.

No generic parser cursor, parser-session callback change, `LanguageSpec`
change, baseline-only core token accessor, goal-source detection API, or
cross-revision cache is in scope.

## Responsibilities and data flow

### Continuation owners

The block parser remains the authority for continuation semantics. Every
current owner—root paragraph, block-quote paragraph, block-quote setext, root
setext, list item, and list-item setext—provides three aligned Markdown-local
operations:

1. observe a typed continuation decision from read-only token facts;
2. advance a read-only fact cursor past the token sequence represented by a
   `Continue(action)`; and
3. consume that same action on the authoritative `ParserContext`.

The first two operations must not emit parser events. The third is the existing
CST operation. An action’s fact-cursor advance and its consumer must end at the
same token offset; tests make this correspondence observable.

### Fact planner

Starting at the inline container’s current source offset, the planner advances
only its own offset. At every fact offset it first applies the same
policy-specific inline-boundary classification as the driver. A block boundary
or EOF establishes the exclusive end at the current offset and is not recorded
as inline or delimiter content. EOF is terminal and is the sole case that does
not require an advancing next offset.

A newline is handled as the driver handles it: the owning policy observes the
continuation decision before the planner can continue. `Stop` establishes the
exclusive end at that newline offset. `Continue(action)` records the action
under that newline offset, then advances with that action’s pure fact-cursor
rule. All other inline tokens advance to their token end. As it walks, the
planner records backtick runs and their left-to-right, equal-length successors.

Every nonterminal fact must advance the caller-owned offset and remain
source-aligned. Violation is an internal parser-contract failure: there is no
goal-source compatibility path or partial plan fallback. This is safe only
because Markdown owns its grammar and has the explicit no-goal-source
invariant. A future goal-directed Markdown parser must obtain a new transport
decision before it can use this planner.

### Authoritative inline parse

The inline driver receives a completed plan alongside its existing parse
policy and typed handler. At each newline, it reads the action recorded for the
current source offset and passes that action to the existing consumer. At a
backtick, it resolves the closer from the plan’s container-local successor
facts. No branch recomputes a continuation decision during the actual pass.

The parser must reject a plan/action offset mismatch as an internal invariant
failure rather than infer an alternative action. This preserves one source of
truth for block continuation policy and prevents a stale plan from silently
changing CST ownership.

## Invariants

1. A plan is local to one active inline container and is discarded immediately
   after that container’s authoritative parse.
2. Planning never advances `ParserContext`, emits a CST event, changes its
   open-node state, changes lex mode, or adds a diagnostic.
3. Every planned continuation action equals the owning policy’s direct
   read-only decision at the same newline facts.
4. The action’s pure advance and its effectful consumer reach the same next
   source offset.
5. The plan end is the current offset of a policy block boundary, EOF, or a
   newline whose decision is `Stop`; no terminal token, successor, or backtick
   run beyond that offset is visible to the container.
6. Equal-length closer ownership is left-to-right; unmatched or escaped runs
   retain the current literal fallback and subsequent emphasis/link parsing.
7. Markdown production parsing never configures `goal_source` while this
   transport is in use.
8. One-shot parsing, incremental parsing, and isolated block reparsing produce
   the same CST, diagnostics, source fidelity, and Markdown IR as before.

## Validation order

This is a performance investigation. The first implementation task writes and
runs a benchmark that isolates the current speculative delimiter prepass with
realistic multi-line containers. It must report the prepass cost separately
from tokenization, AST lowering, and whole-document parsing. If the isolated
cost is not measurable at a scale that can justify the calibrated adoption
gate, the investigation stops without production parser integration.

Only after the isolated benchmark confirms the claimed cost may implementation
add the plan and its tests. Required behavioral evidence is:

- action-plan parity for every named continuation action and `Stop` case;
- consumer/advance offset parity for every action;
- no-event planning on an ordinary parser context;
- source fidelity for matched, unmatched, escaped, and boundary-adjacent
  backtick runs;
- differential equality of one-shot, incremental-edit, and block-reparse CSTs,
  diagnostics, and Markdown IR; and
- existing inline, continuation, incremental, source-fidelity, and Markdown
  fixture suites.

## Performance evidence gate

The repository’s scheduled 15% regression detector remains an alerting system,
not the adoption gate for this change. A preliminary A/A control ran five
counterbalanced pairs on the same `871c5bb` commit in two worktrees, using the
existing wasm-gc Markdown benchmarks. Its maximum absolute paired deltas were
4.975% for realistic CST, 5.602% for realistic CST+AST, 2.039% for tokenize
only, and 2.043% for the incremental paragraph edit.

Those five pairs are a diagnostic, not a statistical bound: they include a
large single AST outlier and no warm-up phase. They establish that an
unwarmed, five-pair maximum must not be converted into an adoption threshold.

Before a candidate implementation is evaluated:

1. Run three unrecorded warm-up invocations for every metric in each of two
   same-commit worktrees.
2. Run at least fifteen counterbalanced A/A pairs with the exact candidate
   command, target, submodule revisions, benchmark indices, and host setup.
3. Bootstrap the median paired delta with 10,000 resamples and a two-sided
   95% percentile interval. The A/A interval for every metric must contain
   zero; otherwise increase the sample or stabilize the environment before
   comparing a candidate.
4. Run at least fifteen counterbalanced candidate-versus-baseline pairs under
   the calibrated protocol.

The candidate is eligible only when the **upper endpoint** of the 95% bootstrap
interval for its median paired delta is at most -3.0% for both realistic CST
and realistic CST+AST. This proves a practical minimum improvement even at the
least favorable endpoint. For tokenize-only and incremental controls, the
upper endpoint must be at most +2.0%; that prevents the planner from moving
cost into controls.

The raw invocation means, warm-up count, pair ordering, bootstrap seed and
algorithm, computed intervals, commands, target, host details, and commit IDs
must accompany the candidate PR. Passing this evidence does not update
`docs/performance/bench-baseline.tsv`; a baseline change remains a separate
review decision.

## Alternatives rejected

### Retain the current speculative full scan

It preserves behavior but continues to allocate speculative parser events and
cannot prove that the continuation boundary is usable independently of CST
consumption.

### Add a generic baseline-token cursor or goal-source query

A generic core API would make the transport dynamically enforceable, but it
would extend `ParserContext`’s public contract before a second grammar proves
that abstraction necessary.

### Add a cross-revision frontier cache

The current incremental system exposes reuse through a per-parse `ReuseCursor`,
not a stable public source revision/container identity. A cache would require a
new invalidation contract and is not needed to test whether removing speculative
CST work is valuable.

## Consequences

This specification does not authorize a production optimization merely because
the planner is structurally cleaner. It turns the ADR’s deferred gates into an
executable investigation order: isolate the claimed prepass cost, then require
behavioral parity and an A/A-calibrated production improvement before adopting
the plan.

No ADR is created or changed by this proposed design. The accepted deferral ADR
remains authoritative until an implementation plan closes with the required
evidence.
