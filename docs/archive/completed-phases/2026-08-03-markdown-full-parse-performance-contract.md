# Markdown Full-Parse Performance Contract Implementation

**Status:** Complete

## Goal

Decompose Markdown source-to-AST cold parsing into stable measurable stages and
place its regression and product objectives under repository-owned policy.

## Completed work

- Added token-buffer construction and pretokenized grammar+CST benchmarks at
  10, 100, and 500 paragraphs.
- Completed the isolated AST-fold scale matrix with a 10-paragraph row.
- Locked paragraph corpus byte sizes and stage-result parity in normal tests.
- Added a mixed 2,005-line end-to-end full-parse benchmark.
- Added the 500-paragraph stage rows and mixed-corpus acceptance rows to the
  machine-readable baseline and explicit gated detector policy.
- Documented deployment objectives, commands, interpretation limits, and
  correctness boundaries.

## Exit evidence

- Dependency health: `moon check --frozen` passed before implementation.
- Post-change `moon check --frozen --deny-warn` and the 3,833-test release
  workspace suite pass.
- New stage parity tests compare complete CST, diagnostic, and AST values.
- Release JS and wasm-gc stage benchmarks execute and expose separate
  token-buffer and pretokenized-CST costs.
- The scheduled detector's eight new rows use the baseline artifact from
  GitHub Actions run 30759285784 rather than local WSL2 timings.
- `bench-check.sh --validate` accepts the baseline/policy relationship.

Decision record:

- [ADR: Markdown Full-Parse Performance Contract](../../decisions/2026-08-03-markdown-full-parse-performance-contract.md)
