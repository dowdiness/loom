# ADR: Explicit Benchmark Detector Eligibility Policy

**Date:** 2026-07-13  
**Status:** Accepted  
**Implementation plan:** [2026-07-13 benchmark detector policy](../archive/completed-phases/2026-07-13-benchmark-detector-policy.md)

## Context

The scheduled benchmark detector compared every baseline row with one fixed
15% relative threshold. #644 showed that some lifecycle and tiny fold rows have
high measurement variance or no stable material-regression signal. The detector
also conflated benchmark inventory drift and verifier failures with performance
regressions. That combination produced noisy alerts and could misclassify an
empty or partially parsed benchmark run as hundreds of missing benchmarks.

Markdown lowering later needed a change-local guard as well. Its purpose is
different from the scheduled detector: compare a pull request's base and head
on the same runner, without treating a moving absolute baseline as a merge
gate. #781 extends that same guard to delimiter-heavy end-to-end parsing and
incremental delimiter edits; it does not move those rows into the scheduled
absolute-baseline detector.

## Decision

`bench-check.sh` remains the single scheduled absolute-baseline detector and
reads a versioned `docs/performance/bench-detector-policy.tsv` file. Rows are
gated by default; reviewed high-variance rows may be marked `informational`. A
gated row above 15% emits `REGRESSION` and fails. An informational row above 15%
emits `INFO` and remains visible without alerting.

`MISSING` is always a hard inventory failure. `NEW` is warning-only. Empty or
malformed output, unknown units, command failure, malformed or duplicate TSV
keys, missing/invalid policy versions, and stale policy keys fail closed before
writing a comparison report. `--update` validates the prospective baseline and
policy before atomically replacing the existing baseline. `--validate` checks
the committed baseline and policy without running benchmarks, and PR CI runs it
alongside the fixture-driven self-test.

Pull-request CI also runs `scripts/markdown-ir-perf-guard.sh` as a narrow
base/head comparison guard on wasm-gc and JS. It alternates base/head order
across three trial pairs on one runner. The original realistic and 50x direct
and MarkdownIR lowering pairs remain required. Direct raw slowdowns over 50%
fail when present in all three trials. A MarkdownIR trial is bad when both its
raw and direct-normalized slowdowns exceed 50%, or when its raw slowdown
reaches the inclusive 100% hard ceiling; the case fails when all three trials
are bad.

The guard also requires delimiter-heavy and length-matched plain-control rows
at 64x and 256x for both full CST parsing and one incremental edit-and-restore
cycle. A delimiter trial is bad when both its raw and plain-control-normalized
slowdowns exceed 50%, or when its raw slowdown reaches the inclusive 100% hard
ceiling. A plain-control slowdown over 50% is tracked independently. As with
lowering, a case blocks only when the same signal is bad in all three trials.
Missing or duplicate required rows, malformed measurements, and unknown units
remain infrastructure failures in normal and calibration modes.

To bootstrap a newly required benchmark without exempting the base revision,
CI snapshots the tracked head benchmark harness, records its SHA-256, and
overlays that exact file on both base and head before each trial. Parser API
cutovers are isolated behind private white-box adapters so the shared harness,
workloads, timed boundary, and benchmark rows remain identical. Each revision
supplies its own tracked adapter; CI snapshots and verifies the base and head
adapters independently instead of classifying old APIs or installing
compatibility adapters. A manual calibration mode checks out the same commit on
both sides and disables only the delimiter performance verdict; all other
verdicts and input validation stay active. These PR-guard thresholds are
separate from the scheduled detector's 15% threshold and eligibility policy.

## Rationale

Eligibility is a benchmark-level maintenance decision, not a property that can
be inferred reliably from a single relative delta. Keeping the default gated
preserves coverage for future regressions; explicit informational metadata makes
an exemption reviewable and reasoned. Separating inventory and infrastructure
routing prevents detector health failures from being mistaken for product
performance evidence.

The PR guard deliberately trades sensitivity for a low-noise merge signal.
Same-run alternation reduces host variance, while the scheduled detector keeps
the more sensitive long-lived baseline. Passing the PR guard therefore means
that no configured coarse regression persisted; it does not mean that base and
head have identical performance.

The delimiter thresholds are supported by the exact same-SHA, three-pair
wasm-gc and JS calibration recorded in
[`benchmark_history.md`](../performance/benchmark_history.md#2026-07-30-markdown-delimiter-pr-guard-aa-calibration).
The largest positive subject and normalized drifts were 4.3% and 5.0%. The
largest positive plain-control drift was a single JS observation of 31.3%; its
other two trials were -2.3% and -10.2%. The 50% relative/control thresholds
therefore remain above observed A/A noise, while three-of-three persistence
prevents a single control outlier from blocking. The 100% hard ceiling remains
an independent catastrophic-slowdown backstop.

No universal absolute nanosecond floor was added because #644 did not establish
one safe across all benchmark scales. The policy can evolve through reviewed
metadata changes backed by self-test cases.

## Consequences

The scheduled workflow no longer alerts on the classified noisy rows, while
benchmark removal and detector/parser breakage remain visible and blocking.
The policy file, baseline, and self-test must be updated together when benchmark
names change. Contributors can validate the checked-in detector contract with
`bash bench-check.sh --validate` without installing or running MoonBit.

The PR guard catches catastrophic or persistent change-local regressions before
merge but may allow smaller slowdowns that the scheduled detector later flags.
Changes to either detector's scope or thresholds must update its self-test and
this decision record so that a green PR check is not mistaken for proof of zero
regression. Delimiter-heavy rows use the shared head harness for base/head
comparability; the API adapter may vary only to bridge an otherwise
uncompilable parser API cutover. Changing the harness or its timed adapter
boundary changes the measured contract and requires fresh A/A evidence before
threshold policy is revised.
