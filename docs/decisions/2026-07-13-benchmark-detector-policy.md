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
gate.

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
base/head comparison guard for the realistic and 50x Markdown direct and
MarkdownIR lowering benchmarks on wasm-gc and JS. It alternates base/head order
across three trial pairs on one runner. Direct raw slowdowns over 50% fail when
present in all three trials. A MarkdownIR trial is bad when both its raw and
direct-normalized slowdowns exceed 50%, or when its raw slowdown reaches the
inclusive 100% hard ceiling; the case fails when all three trials are bad.
These thresholds belong to the PR guard; the 15% threshold and eligibility
policy belong to the scheduled detector.

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
regression.
