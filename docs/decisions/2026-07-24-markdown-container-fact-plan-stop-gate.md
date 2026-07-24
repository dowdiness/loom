# ADR: Do Not Adopt Markdown Container Fact Plan

**Date:** 2026-07-24
**Status:** Accepted
**Issue:** #739
**Related:** [container fact plan design](../superpowers/specs/2026-07-23-markdown-container-fact-plan-design.md); [delimiter frontier deferral](2026-07-20-markdown-delimiter-frontier.md)
**Implementation plan:** [archived container fact plan](../archive/completed-phases/2026-07-23-markdown-container-fact-plan.md)
**Evidence:** [Task 1 isolated prepass gate](../performance/2026-07-24-markdown-prepass-stop-gate-pre-task2.json); [Task 5 calibrated gate](../performance/2026-07-24-markdown-container-fact-plan-task5-gate.json)

## Context

Issue #739 evaluated whether Markdown can replace the speculative,
CST-emitting delimiter prepass with a container-local, token-fact plan. The
investigation first established sufficient isolated headroom, then implemented
Markdown-local token transport, typed continuation fact observation and
advancement, and the private generic plan. The candidate preserved the tested
parser behavior: Task 5's full Markdown suite passed 3,430 tests.

Adoption required a calibrated paired benchmark: after three warm-ups per
worktree and metric, 15 counterbalanced pairs, and 10,000 seeded bootstrap
resamples, both realistic CST metrics needed an upper 95% confidence endpoint
at or below -3.0%, while tokenize-only and incremental controls needed endpoints
at or below +2.0%.

The candidate at `66e46940c74d531b836525d151d2f18d14140a1f` failed three
required thresholds against baseline
`17ebd1b5b7f14f0a45486ee6d4af9b430d0f0fe9`: realistic CST was
[-4.43%, +2.66%], realistic CST+AST was [-5.30%, -0.97%], and tokenize-only
was [+2.22%, +12.16%]. Incremental paragraph edit passed at
[-1.55%, +1.83%].

## Decision

Do not adopt or merge the Task 2–4 Markdown container-fact-plan candidate into
production. Keep the current speculative delimiter prepass as the production
implementation. Retain the candidate branch, archived plan, and benchmark
artifacts as investigation evidence only.

Do not update `docs/performance/bench-baseline.tsv` from this experiment. Any
future attempt to replace the prepass must begin with a new design review and
must independently satisfy the calibrated whole-document performance gate.

## Rationale

The candidate was behaviorally correct but did not meet the explicit adoption
contract. A 95% interval whose upper endpoint is +2.66% cannot establish the
required realistic-CST improvement, the CST+AST interval misses the required
-3.0% threshold, and tokenization regressed beyond its +2.0% control limit.
Merging it would turn a gated performance experiment into an unproven
production change.

## Consequences

- Markdown production parsing and public interfaces remain unchanged by #739.
- The benchmark evidence records the exact commits, host, commands, warm-up
  count, pair ordering, bootstrap seed, and intervals supporting this decision.
- The isolated prepass result remains useful evidence that the original
  speculation was measurable; it is not evidence that this candidate is an
  optimization.
- Future work may inspect the archived implementation, but must not reuse its
  production integration without new evidence and a new adoption decision.
