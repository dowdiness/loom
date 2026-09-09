# Markdown Adversarial Complexity Sentinel Design

**Date:** 2026-09-09  
**Status:** Implemented in calibration mode

## Goal

Detect a return of input-driven superlinear Markdown parsing without adding
production instrumentation, a generic benchmark framework, or parser caches
before a failing workload exists.

The sentinel covers two distinct failure classes:

1. unsuccessful scans whose cost grows quadratically with source length; and
2. repeated nested parsing whose cost grows exponentially with nesting depth.

It reuses the existing Markdown benchmark harness and performance guard. The
only new detector behavior is pairwise comparison of rows from the same
revision and trial.

## Evidence and Current Gap

Two ox-content regressions establish the failure shapes.

- An ox-content unmatched-opener regression
  found that each unmatched `[` or `![` scanned the remaining input. Four times
  the source length cost about sixteen times as much. Its regression test
  compares 32 KiB with 128 KiB and requires less than eight-times growth.
- An ox-content nested-link regression
  found that nested link text was parsed repeatedly at every nesting level.
  Four tests require dangerous fixed-depth inputs to finish within a generous
  budget. A fifth compares depths 32 and 48 and requires less than 100-times
  growth; the old doubling behavior predicts 65,536 times for sixteen added
  levels.

- [cmark's pathological suite](https://github.com/commonmark/cmark/blob/master/test/pathological_tests.py)
  checks complete parser output for fixed adversarial sources under an outer
  process timeout. Its unmatched-opener case uses repeated `[a`; this supports
  a direct source fixture and correctness oracle, but not a Loom-specific
  numeric threshold.

Loom does not share those parser structures. Its inline path collects facts,
builds code-span and link indexes, builds one delimiter plan, and then performs
the authoritative parse. Existing tests also pin linear `opener_checks` for
emphasis and prefix-linear `inspected` work for reference definitions. No
corresponding superlinear failure has been reproduced on Loom HEAD.

Coverage remains incomplete at the source boundary. Existing link-index
benchmarks begin with an `InlineAnalysisToken` bank, while deep link-reference
benchmarks begin with constructed `MarkdownIR` atoms. Neither protects the
complete source-to-CST path against repeated work across stages.

## Prototype Evidence

The first throwaway source-to-CST benchmark used 8,192- and 32,768-byte
unmatched-bracket inputs, equal-length plain controls, and nested-link depths
32 and 48. Fixture tests passed before measurement.

| Target | Bracket growth | Control growth | Normalized growth | Depth growth |
|--------|---------------:|---------------:|------------------:|-------------:|
| JavaScript | 6.13x | 3.63x | 1.69x | 1.53x |
| wasm-gc | 5.52x | 3.93x | 1.41x | 1.61x |

A second throwaway survey compared `[`, `[a`, `![`, `[[`, and `[^` at the
same sizes. JavaScript growth was 5.66x-6.16x and wasm-gc growth was
5.16x-5.99x. Source inspection explains the narrow band: the lexer emits the
same `LeftBracket` token, and an unmatched opener does not reach the
image/reference candidate branches in `index_inline_links`. Those ox-content
shapes are not distinct Loom workloads.

The survey also rejected `]a` as a token-cardinality control. It invokes its
own unmatched-closer semantics and reached 7.68x in one wasm-gc run, leaving
little diagnostic margin. The established plain control remains less
confounded even though it intentionally does not preserve token count.

A third prototype compared 4/16 KiB with 8/32 KiB for dense `[` and the plain
control. Subject growth was 5.36x versus 5.79x on JavaScript and 5.85x versus
5.80x on wasm-gc; the smaller pair did not create a wider healthy-growth gap.
The 8/32 KiB pair is retained because larger inputs amplify a newly introduced
quadratic term, while Moon Bench's adaptive repetition already bounds ordinary
row duration.

These exploratory runs do not approve a threshold. They show that the tested
Loom revision does not reproduce either target regression and that one dense
opener fixture is sufficient. They also disprove a `raw AND normalized`
verdict: if a shared source-to-CST stage regresses, subject and control growth
of 16x normalizes to 1x. Subject and control raw growth must therefore alarm
independently; normalization is classification evidence only.

## Decision

Add two narrow source-to-CST sentinel families to the existing Markdown
performance guard:

- a source-length family for unsuccessful bracket searches; and
- a nesting-depth family for repeated nested-link parsing.

Keep the contracts separate because source length and nesting depth are
different independent variables. Do not change production Markdown code unless
a sentinel first reproduces a violation and isolates its owner.

## Scope

Included:

- deterministic Markdown source fixtures;
- ordinary tests that pin fixture dimensions and parser output;
- source-to-CST benchmark rows on JavaScript and wasm-gc;
- same-revision scale and depth comparisons;
- the existing three-trial persistence and calibration workflow;
- fail-closed row validation and checker self-tests.

Excluded:

- a generic complexity framework, registry, or metadata format;
- a new baseline format;
- public or production parser statistics;
- new parser counters before a violation is reproduced;
- initial tokenize, MarkdownIR, HTML, incremental, or 16x-scale rows;
- parser caches or semantic changes;
- changes to the user-owned inline-container fact-plan work in
  [#739](https://github.com/dowdiness/loom/issues/739).

## Existing Infrastructure

Reuse:

- `@bench.T` and `moon bench --release`;
- `examples/markdown/delimiter_performance_wbtest.mbt` as the reference for
  deterministic sources, length-matched controls, and fresh full parsing;
- `scripts/markdown-ir-perf-guard.sh` for benchmark parsing, required rows,
  three alternating base/head trial pairs, persistence, and calibration;
- `scripts/markdown-ir-perf-guard-selftest.sh` for detector behavior;
- `.github/workflows/ci.yml` for an identical head-snapshotted harness on base
  and head and separate JavaScript/wasm-gc jobs.

The scheduled absolute-baseline detector remains unchanged. It answers whether
a row became slower than a stored revision. The new checks answer whether one
revision's work grows too quickly as an input dimension grows.

## Contract A: Unmatched-Opener Growth

### Fixture

Use a dense unmatched-opener source:

```text
small = "[".repeat(8192)
large = "[".repeat(32768)
small_control = "x".repeat(8192)
large_control = "x".repeat(32768)
```

The fixture test must prove:

```text
large.length == small.length * 4
small_control.length == small.length
large_control.length == large.length
large_control.length == small_control.length * 4
```

The control preserves source length and line structure while replacing bracket
syntax with inert characters. Tests, not benchmark names, are the authority
for these equalities.

The dense `[` form maximizes opener pressure per byte and reaches Loom's one
unmatched-opener path. It refines cmark's checked-in `[a` pathological case
without importing ox-content-only branch distinctions. Do not add more shapes
unless Loom code gains a distinct reachable path or a regression demonstrates
one.

### Timed boundary

Construct sources outside the timed closure. Measure only fresh source-to-CST
parsing and keep the result alive through `b.keep`.

The family has four rows:

```text
markdown adversarial unmatched opener small full parse
markdown adversarial unmatched opener small plain control
markdown adversarial unmatched opener large full parse
markdown adversarial unmatched opener large plain control
```

Append these rows to the existing delimiter performance harness. Do not add a
fourth benchmark process to each base/head trial.

### Candidate verdict

For each revision and trial:

```text
subject_growth = large_subject / small_subject
control_growth = large_control / small_control
normalized_growth = subject_growth / control_growth
```

A trial is suspicious when either raw invariant reaches its candidate ceiling:

```text
subject_growth >= 8
control_growth >= 8
```

A verified 4x source turns quadratic work into a 16x signature. The independent
control ceiling preserves detection of a shared source-to-CST regression;
normalized growth only classifies subject-specific versus shared excess and
never suppresses either raw alarm. The value remains non-gating until A/A
calibration supports a stable gap between healthy measurements and 16x on both
targets.


## Contract B: Nested-Link Growth

### Fixture

Use direct Markdown source:

```text
"[".repeat(depth) + "a" + "](/u)".repeat(depth)
```

Compare depths 32 and 48. Pin both depths and resulting source lengths in
ordinary tests, but do not normalize this contract by source length. Nesting
depth is the independent variable.

Before adding new correctness tests, reuse existing CommonMark or integration
coverage when it already fails for the plausible regression. The required
behaviors are:

- prohibited nested links retain only the allowed innermost link;
- nested reference links remain correct;
- one missing closing suffix takes literal fallback;
- an image remains allowed inside link text;
- block-quote and list-item parsing preserve the same rule.

### Timed boundary

Measure fresh source-to-CST parsing:

```text
markdown adversarial nested-link depth 32 full parse
markdown adversarial nested-link depth 48 full parse
```

### Candidate verdict

For each revision and trial:

```text
depth_growth = time_at_48 / time_at_32
```

The trial is suspicious when `depth_growth >= 100`. The bound is deliberately
coarse. It rejects per-level doubling, which predicts 65,536-times growth,
without claiming strict linearity in depth. It remains non-gating until
calibrated.

Do not introduce a MoonBit thread/channel timeout solely to mirror ox-content.
The focused CI job is the initial outer safety boundary. Add a smaller
process-level timeout only if a reproduced regression shows that this boundary
is operationally inadequate.

## Correctness and Work Oracles

Ordinary tests prove:

1. fixture generation is deterministic;
2. Contract A's source and control dimensions are exact;
3. parsing consumes and preserves the complete source;
4. diagnostics and accepted/literal link behavior are unchanged;
5. nested-link semantics match CommonMark.

Existing work counters remain useful only when they directly own the loop under
test. None is a complete oracle for these contracts:

- delimiter `opener_checks` observes emphasis resolution, not every link-index
  operation;
- reference-definition cursor `inspected` observes a different subsystem;
- parser token/start/end callbacks observe `TokenBuffer` access, but
  `collect_inline_analysis_tokens` first materializes an array and
  `index_inline_links` then scans that array without invoking those callbacks;
- the `checks` variable in `inline_angle_performance_wbtest.mbt` is incremented
  by the test's fixed loop and does not observe production index work.

Therefore wall-clock source-to-CST scaling is the primary whole-boundary oracle.
Do not add a duplicated test-only parser, production counter, or counter-based
acceptance path before a violation identifies a specific owner.

## Alternatives Rejected

- **Callback-read counts as the primary gate:** deterministic but blind to the
  materialized inline-analysis arrays where the target repeated work can occur.
- **Three or more sizes with a fitted exponent:** for a fixed 4x scale,
  exponent and ratio encode the same decision; extra rows add CI time and
  another noisy estimate without covering another mechanism.
- **Absolute timeout only:** bounds a hang but is runner-sensitive and cannot
  distinguish a complexity change from a constant-factor slowdown.
- **All ox-content bracket shapes:** Loom collapses the unmatched cases before
  the ox-specific branches; the prototype found no separate growth signature.
- **A 4/16 KiB source pair:** it produced more inner repetitions but no better
  separation from healthy growth than 8/32 KiB, while reducing sensitivity to
  a quadratic term that becomes dominant only at larger inputs.
- **A new benchmark command or framework:** the existing harness, alternating
  trials, parser, and fail-closed row checks already provide the required
  boundary.

The selected design is the smallest complete oracle: six added rows in one
already-invoked benchmark file, three raw invariants across two families, and
no production instrumentation.

## CI Cost and Noise Policy

The workflow already invokes `delimiter_performance_wbtest.mbt` for every
base/head trial on both targets. Appending six rows avoids another compile and
process launch. For scale, the local eight-row size prototype completed in
12.34 seconds on JavaScript and 12.95 seconds on wasm-gc; the permanent set is
smaller and must still be measured by A/A before gating.

Noise is contained by requiring the same inclusive raw violation in all three
head trials. Base ratios classify a pre-existing condition, controls classify
shared-path growth, and neither changes the head invariant. This costs more
than an ordinary deterministic test but avoids the false-negative boundary of
available counters and the runner sensitivity of one-shot absolute timeouts.

## Guard Integration

Add explicit row names and pair calculations to the existing Markdown guard;
do not introduce a registry or general schema.

A performance verdict requires the same raw invariant to be suspicious in all
three head trials and reports subject, control, normalized, and corresponding
base ratios. If base already violates the same contract, report an existing
condition rather than attributing it to the PR. Missing, duplicate, malformed,
or non-positive required rows remain immediate infrastructure failures.

Checker self-tests cover:

- healthy ratios;
- a persistent violation;
- a non-persistent observation;
- exact-threshold behavior;
- an existing base violation;
- an independent control violation;
- a shared-path `subject_growth = 16`, `control_growth = 16` violation in which
  normalization is 1x but both raw invariants remain alarms;
- calibration mode;
- missing, duplicate, malformed, and non-positive rows.

## Calibration and Adoption

1. Add fixtures, correctness tests, benchmark rows, pair calculations, and
   checker self-tests with performance verdicts disabled.
2. Run same-SHA A/A trials on JavaScript and wasm-gc.
3. Record subject, control, normalized, and depth growth for every trial.
4. Confirm fixture construction is outside the timed closure and every required
   row occurs exactly once.
5. Gate a family only when its threshold is above observed A/A noise on both
   targets.

The design does not pre-approve `8` or `100` when calibration contradicts
them. An accepted threshold changes benchmark policy and therefore updates the
existing benchmark detector ADR and guard self-test.

### Implementation calibration

The six rows and the fail-closed three-trial guard are implemented. Local
same-SHA calibration on 2026-09-09 produced:

| Target | Trial | Subject growth | Control growth | Normalized growth | Depth growth |
|--------|------:|---------------:|---------------:|------------------:|-------------:|
| JavaScript | 1 | 5.804x | 2.935x | 1.977x | 1.536x |
| JavaScript | 2 | 5.303x | 3.436x | 1.543x | 1.632x |
| JavaScript | 3 | 6.088x | 2.912x | 2.090x | 1.525x |
| wasm-gc | 1 | 4.236x | 3.729x | 1.136x | 1.549x |
| wasm-gc | 2 | 4.893x | 3.779x | 1.295x | 1.597x |
| wasm-gc | 3 | 5.612x | 3.959x | 1.418x | 1.320x |

These measurements support the candidate ceilings, but local measurements do
not establish GitHub runner noise. `MARKDOWN_COMPLEXITY_PERF_CALIBRATION`
therefore defaults to `1`: CI requires and reports the rows but does not yet
attribute a complexity verdict to a pull request. Set it to `0` only after
same-SHA CI evidence confirms the gap on both targets.

No ADR needed: this change implements the proposed calibration mechanism
without adopting a new gating policy. Enabling the verdict remains the policy
change that updates the benchmark detector ADR.

## Violation Diagnosis

A sentinel is an alarm, not a prescribed optimization. For a persistent
violation:

1. reproduce the checked-in source fixture;
2. isolate tokenization, inline fact collection, code-span indexing, link
   indexing, delimiter planning, or CST emission;
3. add a local work counter only if wall time cannot isolate repeated work;
4. fix the owner with the narrowest monotonic scan, stack, interval proof, or
   parse-local memo;
5. rerun the sentinel and representative Markdown performance rows;
6. preserve CST source fidelity, diagnostics, CommonMark behavior, and affected
   direct/incremental parity.

A cache is not the default repair. Any cache must have one semantic authority,
a container- and revision-local lifetime, and an explicit validity argument.

## Expected Change Boundary

Implementation should normally touch only:

- one existing Markdown white-box performance harness;
- `scripts/markdown-ir-perf-guard.sh`;
- `scripts/markdown-ir-perf-guard-selftest.sh`;
- no `.github/workflows/ci.yml` change is expected because the focused command
  already invokes that harness;
- the existing benchmark detector ADR only when calibration adopts gating
  policy.

Do not create a package, generic library, metadata registry, or production API.

## Acceptance Criteria

- Fixture tests prove all source-length and control equalities.
- Source-to-CST behavior is unchanged for the unmatched-opener and nested-link
  fixtures.
- JavaScript and wasm-gc emit all six required rows.
- The guard distinguishes source-length and nesting-depth contracts.
- Invalid evidence fails closed.
- A/A evidence supports every adopted threshold.
- No production parser code, public API, or user-owned #739 worktree changes.

## Consequences

Loom gains protection against the two concrete complexity failures demonstrated
by ox-content while keeping the mechanism local to Markdown performance tests.
The sentinel does not claim a global parser complexity proof. Add another
family only after a real failure or source-backed audit identifies a distinct
repeated-work mechanism.
