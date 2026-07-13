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
3. Keep `bench-check.sh` launched from `examples/lambda`; Moon resolves the
   enclosing root `moon.work` workspace and discovers the active benchmark
   packages across e-graph, incr, loom, seam, and the lambda example.
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

The six initial candidates below came from the first reconciled run; the two
additional candidates came from the final benchmark sweep in Task 2.

### Initial 6 candidates (first reconciled run)

| Benchmark | Current trials | Baseline-origin trials | Ratio range | Classification |
| --- | --- | --- | --- | --- |
| `runtime: new (full, all modes)` | 197.74, 211.76, 213.65 | 268.50, 288.26, 293.42 | 0.728–0.736 | non-reproduced / measurement variance |
| `baseline: memo creation cost (monotonic SoA growth)` | 1440, 1430, 1450 | 1490, 1320, 1520 | 0.954–1.083 | non-reproduced / measurement variance |
| `bench: text_len hand-written` | 487640, 529510, 508800 | 764630, 499710, 481150 | 0.638–1.060 | non-reproduced / measurement variance |
| `bench: text_len via accept_fold[TextLen]` | 445600, 449840, 519920 | 476570, 428550, 467320 | 0.935–1.113 | non-reproduced / measurement variance |
| `bench: node_count via accept_transform_fold[NodeCount]` | 326710, 339400, 324020 | 342880, 339610, 328330 | 0.953–0.999 | non-reproduced / measurement variance |
| `bench: token_count (trivia filter) via CstElement::token_count` | 540880, 472440, 569590 | 493230, 550340, 513190 | 0.858–1.110 | non-reproduced / measurement variance |

### Additional 2 candidates (Task 2 final run)

| Benchmark | Current trials | Baseline-origin trials | Ratio range | Classification |
| --- | --- | --- | --- | --- |
| `ui static probe: tree 1023 static Derived + 512 eager leaves` | 537480, 537590, 547100 | 526550, 531600, 535480 | 1.011268–1.021700 | non-reproduced / measurement variance |
| `realistic: 160 defs - incremental (edit tail)` | 2670000, 2770000, 2710000 | 2770000, 2730000, 3450000 | 0.785507–1.014652 | non-reproduced / measurement variance |

### Shared classification rule

Classify a candidate as a confirmed regression only when all three paired
current/baseline ratios exceed `1.15`.

Across both the initial six and final two candidates, none exceeds `1.15`, so no
baseline value, detector policy, or implementation change is justified by these
measurements.

All three paired current/baseline ratios (`0.963899`, `1.014652`,
`0.785507`) are below `1.15`, confirming non-reproduction on every
pairing. The lowest ratio (`0.785507`) pairs current trial `2710000` ns
with the baseline outlier `3450000` ns; the other two baseline trials
(`2770000`, `2730000` ns) produce ratios `0.964` and `1.015`, both far
below `1.15`. Non-reproduction is robust.


## Consequences

The baseline is now comparable to the benchmark command used by the detector:
316 expected names, with no inventory-only `MISSING` rows. The active scope is
the enclosing root `moon.work` workspace discovered from the
`examples/lambda` launch directory. The retired CRDT/event-graph-walker suite
is no longer silently represented as parser benchmark coverage. Reintroducing
those measurements requires deliberately restoring event-graph-walker as a
`moon.work` member (or adding a separate explicit command), then reviewing the
resulting inventory and baseline; it is not implicitly restored by a future
baseline update.
