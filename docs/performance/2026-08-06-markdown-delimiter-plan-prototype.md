# Markdown delimiter-plan cost-reduction prototype

Issue [#883](https://github.com/dowdiness/loom/issues/883) asked whether the
measured Markdown delimiter-plan cost could be reduced without changing parser
behavior or regressing representative controls. The tested candidate did not
pass the adoption gate. No production parser change remains.

## Decision

**Reject the online-resolver candidate.** Streaming delimiter facts directly
into the existing resolver removed the temporary `Array[DelimiterResolverEvent]`
but did not improve the isolated delimiter plan on either deployment target.
Representative results were also split by target: JavaScript improved in some
rows, while wasm-gc did not. The required three-percent representative win on
both targets was therefore not met.

The production `build_inline_delimiter_plan`, `resolve_delimiter_events`, linked
active-run representation, CommonMark odd-match rule, and link-label scope
handling remain unchanged. The work did not touch the inline-container fact
plan, continuation planning, or backtick successor planning owned by #739.

## Method

Measurements used release builds on wasm-gc and JavaScript. The initial
baseline and stage-attribution rows each ran in five independent benchmark
processes. Candidate comparisons used five alternating baseline/candidate
pairs from separate worktrees at the same base commit. Percentages below are
the mean of paired process-level changes; `±` is the sample standard deviation
across those five pairs.

The checked-in
[`delimiter_plan_prototype_benchmark_wbtest.mbt`](../../examples/markdown/delimiter_plan_prototype_benchmark_wbtest.mbt)
contains the representative README/CommonMark-style excerpt and the CST,
MarkdownIR, matched plain-text, mixed Markdown, HTML, fenced-code, tokenize-only,
and incremental edit/restore rows. Existing delimiter benchmarks remain the
synthetic stress and operation-count controls.

## Baseline

The #872 delimiter cost reproduced on the current base:

| Stage, 2,048 motifs | wasm-gc | JavaScript |
|---|---:|---:|
| code-span index | 0.580 ± 0.024 ms | 0.890 ± 0.047 ms |
| link index | 3.160 ± 0.061 ms | 4.506 ± 0.227 ms |
| delimiter plan | 7.042 ± 0.584 ms | 6.598 ± 0.607 ms |
| complete inline analysis | 11.906 ± 1.094 ms | 11.680 ± 0.743 ms |

The full-parse delimiter-heavy and same-length plain controls also reproduced.
The delimiter-specific cost therefore remained measurable and justified one
bounded prototype.

## Attribution

Temporary private seams separated event construction, resolver scanning and
matching, plan flattening, and the final `ReadOnlyArray` conversion. Five-run
means were:

| Temporary isolated stage, 2,048 motifs | wasm-gc | JavaScript |
|---|---:|---:|
| construct resolver events | 4.224 ms | 4.840 ms |
| resolve event state | 2.808 ms | 2.692 ms |
| flatten plan events | 0.259 ms | 0.243 ms |
| freeze plan events | 0.024 ms | 0.045 ms |

These rows are directional, not additive. Splitting the production function for
observation changed code shape: against the untouched worktree, the disabled
instrumentation increased the wasm-gc delimiter-plan row by 11.1 ± 6.5 percent
and the complete inline pipeline by 14.0 ± 5.8 percent. JavaScript changes were
within the noisier opposite direction. The attribution therefore supports
choosing event transport as the largest seam, but it is not an estimate formed
by summing stage times.

Deterministic resolver counts stayed linear. Plan flattening and immutable
conversion were too small to justify changing ownership or adding another plan
representation.

## Candidate

The single hypothesis was: **feeding run facts, opaque ranges, and link-scope
boundaries directly into the existing resolver would remove event-array
allocation and a second traversal without changing resolver semantics.**

The prototype added a private online façade around the existing resolver state.
The event-array API remained as an adapter for current tests. Parser-local facts,
active-list operations, odd-match checks, flattening, and authoritative plan
emission were otherwise unchanged.

### Isolated result

Compared with the untouched base, the candidate made the isolated 2,048-motif
delimiter plan slower:

| Target | Paired mean | Paired median | Pair-to-pair σ |
|---|---:|---:|---:|
| wasm-gc | +7.2% | +4.3% | 10.6% |
| JavaScript | +15.5% | +12.6% | 17.9% |

The removed array/traversal did not repay the additional online dispatch and
code-shape cost.

### Adoption-gate result

Negative percentages are improvements.

| Row | wasm-gc | JavaScript |
|---|---:|---:|
| representative CST | +2.37 ± 17.24% | -3.84 ± 5.73% |
| representative CST + MarkdownIR | +0.18 ± 5.02% | -6.37 ± 9.67% |
| matched plain CST | -0.51 ± 5.82% | -7.67 ± 5.19% |
| mixed Markdown CST | +0.31 ± 4.74% | -2.47 ± 10.93% |
| HTML control CST | +5.41 ± 8.10% | -3.20 ± 3.70% |
| fenced-code control CST | -0.19 ± 3.61% | -0.19 ± 2.58% |
| tokenize only | +0.87 ± 5.62% | -0.68 ± 4.05% |
| incremental edit + restore | -0.48 ± 7.84% | -2.08 ± 7.13% |

The representative CST and CST+MarkdownIR rows failed the required improvement
on wasm-gc. The HTML control also exceeded the two-percent regression budget in
the paired mean. Synthetic delimiter-heavy full parsing was unstable rather
than a reliable win: paired medians at 64 and 256 repetitions were respectively
-3.18 and +4.07 percent on wasm-gc, and +7.70 and +3.50 percent on JavaScript.
Resolver operation counts remained linear, so this was a constant-factor and
code-shape result rather than a complexity change.

## Correctness and cleanup

At the candidate commit, the Markdown release suite passed 644/644 on both
wasm-gc and JavaScript. Delimiter resolver tests passed 19/19 on both targets,
and the event-attribution oracle passed 3/3 on both targets. The representative
fixture preserved CST, diagnostics, source interpretation, MarkdownIR, and
incremental edit/restore behavior.

Temporary instrumentation, online resolver APIs, duplicated scanner code, and
counters were removed. The final branch retains only the reusable benchmark and
oracle matrix plus this report; generated `.mbti` files are unchanged.

Prototype history:

- `3ef5805e` — stage attribution seams and benchmark
- `2be77cf2` — online-resolver candidate
- `8a843322` — calibrated representative adoption gate

## Reuse check

The investigation reused `build_inline_delimiter_plan`,
`resolve_delimiter_events`, `DelimiterResolverState`,
`build_delimiter_plan_events`, existing delimiter stress fixtures, production
`parse_cst`, MarkdownIR lowering, and the incremental parser shell.

MoonBit core candidates checked included `Array::new`,
`Array::reserve_capacity`, `ArrayView`, `ReadOnlyArray::from_array`, `Option`,
`String`/`StringView`, `Map`, and `Set`. Capacity hints could not remove the
source scan or resolver work; `ReadOnlyArray::from_array` contributed less than
one percent of the measured plan; `Map` and `Set` did not fit the dense ordered
run chain. No core representation was changed.

The candidate's only new responsibility boundary was temporary online transport
of already-defined resolver facts. Remaining mutation was limited to parser
cursor effects, the existing linked active-run state, scope stack, and benchmark
builders. No helper or mutation from the candidate remains in production.

The decision not to adopt the candidate is recorded in
[ADR 2026-08-06](../decisions/2026-08-06-markdown-delimiter-plan-candidate-rejection.md).
