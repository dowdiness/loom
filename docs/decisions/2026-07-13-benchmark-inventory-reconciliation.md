# ADR: Benchmark Inventory Reconciliation

**Date:** 2026-07-13
**Status:** Accepted
**Implementation plan:** [Issue #712](https://github.com/dowdiness/loom/issues/712)

## Context

`bench-check.sh` runs `cd examples/lambda && moon bench --release`. The
checked-in baseline contained 421 rows, while the current command emitted 316
rows and reported 105 baseline-only `MISSING` rows. Comparing performance
classifications before resolving that inventory mismatch would compare
non-equivalent benchmark sets.

The baseline's origin is commit `6e17167` (`perf(#620): calibrate bench
baseline to the CI runner`, 2026-07-05). Its first 105 rows after the e-graph
entries are the event-graph-walker suite: merge, branch, walker,
version-vector, document/cache, jump, oplog, and text benchmarks. Those rows
were collected while `event-graph-walker` was a `moon.work` member.

Commit `f56e497` intentionally removed the event-graph-walker workspace member,
its submodule, and its CI matrix entries. The current repository has no
tracked `event-graph-walker/` module; `examples/lambda` consumes the registry
package only.

## Decision

1. Treat all 105 missing rows as retired inventory, not performance findings.
2. Remove exactly those 105 rows from `docs/performance/bench-baseline.tsv`.
   Keep all remaining benchmark names and measurements unchanged.
3. Keep `bench-check.sh` scoped to the existing `examples/lambda` benchmark
   command and its active local workspace dependencies.
4. Make `bench-check.sh --update` fail closed when any existing baseline name
   is absent from the current run. A legitimate retirement must remove the
   reviewed baseline row first; new names remain allowed.

## Evidence and self-tests

- The real pre-reconciliation run emitted 316 rows and reported exactly 105
  missing rows; every missing name was in baseline lines 5–109.
- Historical source and benchmark documentation identify those 105 names as
  event-graph-walker benchmarks, with package commands under its internal
  branch, causal-graph, document, fugue, oplog, and text packages.
- `scripts/bench-check-selftest.sh` now rejects an equal-count update that
  replaces a baseline name with a `NEW` name, and verifies the baseline is not
  modified on rejection.
- `bench-check.sh --validate` passes after the inventory cleanup.

## Candidate classification after reconciliation

Three interleaved targeted trials were run for each gated candidate on the
current checkout and on baseline-origin `6e17167`, using Moon
`0.1.20260703 (6fbf8c3)`. Values are nanoseconds; the ratio range is computed
from each paired current/baseline trial.

| Benchmark | Current trials | Baseline-origin trials | Ratio range |
| --- | --- | --- | ---: |
| `runtime: new (full, all modes)` | 197.74, 211.76, 213.65 | 268.50, 288.26, 293.42 | 0.728–0.736 |
| `baseline: memo creation cost (monotonic SoA growth)` | 1440, 1430, 1450 | 1490, 1320, 1520 | 0.954–1.083 |
| `bench: text_len hand-written` | 487640, 529510, 508800 | 764630, 499710, 481150 | 0.638–1.060 |
| `bench: text_len via accept_fold[TextLen]` | 445600, 449840, 519920 | 476570, 428550, 467320 | 0.935–1.113 |
| `bench: node_count via accept_transform_fold[NodeCount]` | 326710, 339400, 324020 | 342880, 339610, 328330 | 0.953–0.999 |
| `bench: token_count (trivia filter) via CstElement::token_count` | 540880, 472440, 569590 | 493230, 550340, 513190 | 0.858–1.110 |

None reproduces a >15% current-over-baseline slowdown. No implementation,
baseline-value, or detector-policy change is justified by these measurements.


## Consequences

The baseline is now comparable to the benchmark command used by the detector:
316 expected names, with no inventory-only `MISSING` rows. The retired
CRDT/event-graph-walker suite is no longer silently represented as parser
benchmark coverage. Reintroducing those measurements requires an explicit
multi-module runner and a separately documented baseline scope; it is not
implicitly restored by a future baseline update.
