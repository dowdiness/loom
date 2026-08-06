# ADR: Reject online Markdown delimiter resolution

**Date:** 2026-08-06

**Status:** Accepted

**Investigation:** [Markdown delimiter-plan cost-reduction prototype](../performance/2026-08-06-markdown-delimiter-plan-prototype.md)

**Issue:** [#883](https://github.com/dowdiness/loom/issues/883)

## Context

The Markdown event-attribution investigation measured delimiter planning as the
largest isolated inline-analysis stage on adversarial input. Issue #883 required
a bounded prototype before any production optimization: reproduce the cost,
attribute the current plan, test one measured seam, and adopt it only if both
wasm-gc and JavaScript representative parsing improved by at least three percent
without control regressions.

Temporary attribution identified resolver-event construction as the largest
observable seam. Splitting the function also perturbed wasm-gc code shape, so
the candidate was measured in alternating pairs against an untouched worktree
rather than by summing isolated stage times.

## Decision

Do not adopt the online-resolver candidate. Keep the existing private
`Array[DelimiterResolverEvent]` assembly followed by `resolve_delimiter_events`.
Do not retain the prototype's online façade, duplicated scanner,
instrumentation, counters, or temporary APIs.

Retain the representative benchmark and oracle matrix as an informational
adoption gate. This decision rejects one implementation, not all future
Markdown delimiter-plan optimization. Any later candidate needs new measured
evidence and must preserve the ownership boundary of #739.

## Rationale

Streaming delimiter facts and link-scope boundaries directly into the resolver
removed one temporary event array and traversal. It nevertheless made the
isolated 2,048-motif delimiter plan slower on both targets: paired means were
+7.2 percent on wasm-gc and +15.5 percent on JavaScript.

Representative results did not satisfy the two-target gate. CST parsing changed
by +2.37 percent on wasm-gc and -3.84 percent on JavaScript; CST plus MarkdownIR
changed by +0.18 percent and -6.37 percent respectively. The wasm-gc rows did
not reach the required improvement, and an HTML control exceeded the
two-percent regression budget in the paired mean. Resolver operation counts
remained linear, so the candidate did not improve algorithmic complexity.

Plan flattening and conversion to `ReadOnlyArray` were small fractions of the
measured work. Changing plan ownership or adding another representation would
therefore add complexity without evidence of representative value.

## Consequences

- Production delimiter planning, CommonMark odd-match semantics, link-label
  scopes, CST emission, and public APIs remain unchanged.
- No generated `.mbti` change is expected.
- The checked-in representative fixture covers ordinary and strong emphasis,
  links, escapes, unmatched runs, intraword underscores, odd-match behavior,
  code spans, HTML, fenced code, MarkdownIR, and incremental edit/restore.
- Synthetic delimiter-heavy input remains useful as a stress control, but a win
  there alone cannot justify production integration.
- #739 continues to own inline-container fact planning, continuation planning,
  and backtick successor planning.
