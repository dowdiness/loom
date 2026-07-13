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

## Decision

`bench-check.sh` remains the single detector and reads a versioned
`docs/performance/bench-detector-policy.tsv` file. Rows are gated by default;
reviewed high-variance rows may be marked `informational`. A gated row above 15%
emits `REGRESSION` and fails. An informational row above 15% emits `INFO` and
remains visible without alerting.

`MISSING` is always a hard inventory failure. `NEW` is warning-only. Empty or
malformed output, unknown units, command failure, malformed or duplicate TSV
keys, missing/invalid policy versions, and stale policy keys fail closed before
writing a comparison report. `--update` validates the prospective baseline and
policy before atomically replacing the existing baseline. `--validate` checks
the committed baseline and policy without running benchmarks, and PR CI runs it
alongside the fixture-driven self-test.

## Rationale

Eligibility is a benchmark-level maintenance decision, not a property that can
be inferred reliably from a single relative delta. Keeping the default gated
preserves coverage for future regressions; explicit informational metadata makes
an exemption reviewable and reasoned. Separating inventory and infrastructure
routing prevents detector health failures from being mistaken for product
performance evidence.

No universal absolute nanosecond floor was added because #644 did not establish
one safe across all benchmark scales. The policy can evolve through reviewed
metadata changes backed by self-test cases.

## Consequences

The scheduled workflow no longer alerts on the classified noisy rows, while
benchmark removal and detector/parser breakage remain visible and blocking.
The policy file, baseline, and self-test must be updated together when benchmark
names change. Contributors can validate the checked-in detector contract with
`bash bench-check.sh --validate` without installing or running MoonBit.
