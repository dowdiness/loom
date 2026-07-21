# ADR: Benchmark Inventory Reconciliation

**Date:** 2026-07-13
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-07-13-benchmark-inventory-reconciliation-improvements.md](../archive/completed-phases/2026-07-13-benchmark-inventory-reconciliation-improvements.md)

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
| `ui-static-probe: tree 1023 static Derived + 512 eager leaves` | 537480, 537590, 547100 | 526550, 531600, 535480 | 1.011268–1.021700 | non-reproduced / measurement variance |
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
The candidate evidence set for this reconciliation is fixed to these six
initial candidates plus the two additional candidates selected from the Task 2
final sweep. Subsequent real detector runs remain useful for checking
`NEW`/`MISSING` inventory and infrastructure state, but newly surfaced gated
rows that appear in later sweeps do not expand this evidence set retroactively.


## Issue #732 Markdown classification

The initial comparison below used grouped current and `#718` trials rather than
temporally paired runs. It is descriptive revision evidence only; its ratios
cannot establish causality because execution-order and later-revision effects
remain confounded:

| Benchmark | Current trials (grouped, ns) | #718 trials (grouped, ns) | Descriptive ratios |
| --- | --- | --- | --- |
| `markdown: realistic doc - full parse (CST)` | 170970, 175240, 187130 | 124330, 125100, 143850 | 1.375, 1.401, 1.301 |
| `markdown: realistic doc - full parse (CST+AST)` | 265220, 262730, 263980 | 199380, 199580, 207880 | 1.330, 1.316, 1.270 |

The required causal control compares the direct #719 parent `0bf67c1` with
the #719 commit `907d5dd`; submodules were synchronized in both worktrees.
Each benchmark used the counterbalanced schedule `718→719`, `719→718`,
`718→719`:

| Benchmark | #718 parent (ns) | #719 commit (ns) | Paired ratios |
| --- | ---: | ---: | ---: |
| `markdown: realistic doc - full parse (CST)` | 123940, 135940, 126660 | 173410, 163390, 164500 | 1.399, 1.202, 1.299 |
| `markdown: realistic doc - full parse (CST+AST)` | 200180, 194250, 196040 | 248910, 249370, 255510 | 1.243, 1.284, 1.303 |

All six causal-control ratios exceed `1.15`. This supports a measurable
performance cost caused by #719 itself for both realistic full-parse paths.
It does not establish that every `e4c7148` versus `#718` difference is caused
only by #719; later revisions remain a separate possible source of change.

The causal control establishes a measurable cost for the two realistic full-parse
paths. #719 introduces normalized-code-span handling and delimiter-index data
structures; those are plausible mechanisms [INFERENCE], but this evidence set
does not isolate their individual costs and does not include clean Markdown
tokenize-only trials. Earlier disposable experiments did not yield a safe
optimization and are not used as quantitative evidence. The measured #719
contribution is therefore accepted as a design cost rather than treated as an
accidental code regression.

The actual current revision `e4c7148` was then measured in a clean worktree with
the stable control `zero-copy: tokenize - long identifiers`. The interleaved
schedule was `control→CST→CST+AST` repeated three times:

| Benchmark | Clean current trials (ns) | Median (ns) |
| --- | ---: | ---: |
| Stable control | 49980, 50190, 50350 | 50190 |
| `markdown: realistic doc - full parse (CST)` | 172460, 169300, 174600 | 172460 |
| `markdown: realistic doc - full parse (CST+AST)` | 259040, 251610, 251400 | 251610 |

The control spread was `0.74%`, so these runs provide a stable local
calibration. The checked-in baseline rows use these clean current medians:
`172460.00 ns` for CST and `251610.00 ns` for CST+AST. Other Markdown rows
remain unchanged because their evidence did not meet the shared `1.15` rule.

## Post-update detector status

The final whole-workspace detector invocation completed with `298` gated
regressions, `35` `NEW` rows, and `0` `MISSING` rows. This run is not evidence
for 298 code regressions: unrelated e-graph, incr, lambda, seam, and Markdown
families all inflated simultaneously, including the already-isolated parser
rows. The result is a contaminated local benchmark run, not a green detector
result, so no broad baseline update is justified.

Independent package-level controls taken outside that run were near or below
their checked-in baselines:

| Control | Current (ns) | Baseline (ns) | Ratio |
| --- | ---: | ---: | ---: |
| `ui: tree 1023 memos + 512 leaf reactives` | 754210 | 688820 | 1.095 |
| `dsl authoring: coarse staged pipeline 20 nodes` | 3070 | 3690 | 0.832 |
| `runtime: new (full, all modes)` | 189.96 | 243.54 | 0.780 |
| `gc: sweep 1k all-live` | 129580 | 162900 | 0.795 |
| `zero-copy: tokenize - long identifiers` | 53650 | 64590 | 0.831 |
| `zero-copy: full parse - integers` | 34600 | 37250 | 0.929 |

The previously recorded three-pair seam measurements likewise remain below
the `1.15` rule. These controls support classifying the broad detector failure
as local measurement contamination, but do not replace a clean CI measurement.
The causal control above, rather than the grouped current/#718 comparison, is
the evidence for the two confirmed #719 design costs.

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
