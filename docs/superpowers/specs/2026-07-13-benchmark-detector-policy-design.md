# Benchmark Detector Policy Design

**Date:** 2026-07-13  
**Issue:** #644  
**Status:** Approved design; implementation pending

## Problem

`bench-check.sh` applies one relative threshold to every benchmark row. The
scheduled workflow therefore alerts on rows whose measurements are known to be
high variance or whose slowdown is not a stable material product signal. The
same comparison also treats benchmark inventory drift and parser failure as
ordinary performance regressions.

The detector needs explicit policy boundaries without weakening deterministic
inventory or infrastructure failure detection.

## Decision

Keep `bench-check.sh` as the single detector and add a versioned, repository-
managed policy file:

- `docs/performance/bench-detector-policy.tsv`
- format: `benchmark name<TAB>mode<TAB>reason`
- `mode` is `gated` or `informational`
- an explicit `policy_version=1` comment identifies the format
- an omitted benchmark is implicitly `gated`

`gated` rows use the existing 15% relative threshold. A gated row above the
threshold emits `REGRESSION` and contributes to exit status 1.

`informational` rows are still compared and reported as `INFO`, but never alert
and never contribute to exit status 1. Only rows classified as high-variance or
otherwise lacking a stable material-regression signal in #644 are initially
informational. Rows that merely failed to reproduce once remain gated so a
future regression cannot be hidden by a permanent exemption. No absolute
materiality floor is introduced because the issue evidence does not establish a
safe universal nanosecond floor.

Inventory and verifier health are separate from performance eligibility:

- `MISSING` always contributes to exit status 1, regardless of policy mode.
- `NEW` is warning-only and does not fail.
- empty parsed output, benchmark command failure, unknown units, malformed TSV,
  duplicate keys, missing policy, invalid policy modes, and stale policy keys
  fail before comparison and write no `BENCH_REPORT_TSV`; the workflow routes
  these cases to `infra`.

## Data flow

1. Run `moon bench --release` in the configured module.
2. Parse benchmark output into nanosecond TSV.
3. Reject parse failure or zero rows before comparison.
4. Validate baseline/current TSV shape and unique keys.
5. Validate policy syntax, unique keys, and baseline membership.
6. Compare each current row against the baseline and policy mode.
7. Emit `OK`, `REGRESSION`, `INFO`, `NEW`, or `MISSING` rows.
8. Write `BENCH_REPORT_TSV` only after all validation succeeds.
9. Fail for gated regressions or missing rows; otherwise pass.

The workflow's persistence filter continues to collect only `REGRESSION` rows;
`INFO` is intentionally excluded while `MISSING` remains deterministic and
fatal.

## Test-driven implementation

Add `scripts/bench-check-selftest.sh`, using a temporary baseline, temporary
module, and fake `moon` executable. It must cover:

1. matching baseline (`OK`, exit 0)
2. gated threshold breach (`REGRESSION`, exit 1)
3. missing baseline row (`MISSING`, exit 1)
4. new current row (`NEW`, exit 0)
5. mixed statuses and report preservation (`REGRESSION` + `MISSING` + `NEW`)
6. empty output (no report, exit 1 / infrastructure signal)
7. unknown unit (no report, exit 1 / infrastructure signal)
8. informational threshold breach (`INFO`, exit 0)
9. stale policy key (no report, exit 1)
10. duplicate current or baseline key (no report, exit 1)
11. `bench-check.sh --validate` validates the checked-in baseline/policy
    without running MoonBit; PR CI runs this alongside the fixture self-test.

Tests assert observable status text, report existence/absence, and exit code.
They must run without MoonBit or the real benchmark suite.
The self-test is wired into the ordinary pull-request CI as a fast shell
check, independently of the weekly benchmark workflow. This keeps detector
policy regressions visible before merge.

## Compatibility and scope

- Default baseline/module paths remain unchanged; environment overrides are
  test seams only (`BENCH_BASELINE`, `BENCH_MODULE_DIR`, and `BENCH_POLICY`).
- `--update` stages parsed output, validates malformed or duplicate current
  rows and policy membership against that prospective baseline, then atomically
  replaces the baseline. Existing zero-row and 75% baseline-size safety guards
  remain.
- `--validate` is the shared production-file validation path used by PR CI; it
  never invokes the benchmark command.
- No benchmark implementation or baseline values are changed by this policy
  work.
- No workflow persistence-count change is required; the existing report format
  remains tab-separated and machine-readable.

## Consequences

The scheduled job stops paging on the classified high-variance rows while
remaining strict about benchmark inventory and verifier integrity. Adding a
new informational exemption requires a versioned policy edit with a reason,
which keeps detector eligibility reviewable in code review. Removing or
renaming a benchmark without updating the policy fails closed instead of
silently dropping coverage.
