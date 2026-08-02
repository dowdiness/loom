# Markdown Full-Parse Performance Contract

**Status:** Active

This contract keeps Markdown cold/full parsing measurable without treating a
single wall-clock number as architecture. It separates stage attribution from
representative end-to-end acceptance and preserves correctness as a
non-negotiable boundary.

## User-facing objectives

The deployment target is JavaScript. Release builds should eventually satisfy
both objectives on the benchmark runner used to record a result:

| Corpus | Product operation | Objective | Current 2026-08-03 observation |
|---|---|---:|---:|
| `paragraph-v1`: 500 paragraphs, 51,410 bytes | source to `Block` | <= 10 ms | 12.94-19.38 ms across clean and noisy local runs |
| `mixed-v1`: 2,005 lines, 34,884 bytes | source to `Block` | <= 50 ms | 117.77 ms |

These are optimization objectives, not PR wall-clock gates. Shared runners are
too noisy for absolute JavaScript latency to block a change. A performance PR
must record same-runner base/head JavaScript and wasm-gc results instead of
claiming success from one absolute run.

## Stage attribution

`examples/markdown/performance_envelope_benchmark_test.mbt` and its white-box
companion divide `paragraph-v1` into these operations:

1. `tokenize`: source to flat `TokenInfo` values.
2. `token buffer build`: production-equivalent mode-lexer session, tokenization,
   owned token/start/end storage, and lexer diagnostics.
3. `pretokenized CST`: grammar execution, event construction, CST construction,
   and parser diagnostics with a stable token buffer prepared outside timing.
4. `CST`: the production `parse_cst` path, including token-buffer construction
   and merged diagnostics.
5. `isolated AST fold`: a prebuilt `SyntaxNode` to `Block` through `CstFold`.
6. `CST plus AST`: the public tolerant `parse` path from source to `Block`.

Independent benchmark means are not additive. Use them to identify the dominant
stage and then write a smaller causal benchmark; do not subtract them to invent
allocation or GC attribution.

The normal tests lock the corpus byte sizes and verify that the pretokenized CST
and isolated fold produce the same CST/AST as the production path.

## Regression detection

The 500-paragraph rows, the mixed 2,005-line full parse, and the mixed 9,999-line
CST parse are explicit `gated` entries in
`bench-detector-policy.tsv`. Their wasm-gc observations are stored in
`bench-baseline.tsv`. The scheduled detector reports a regression only when a
greater-than-15% slowdown persists in all three runs; it opens or updates an
issue rather than making noisy shared-runner timing a PR gate.

Run the stage matrix on the deployment and secondary targets with:

```bash
moon bench --release --target js -p dowdiness/markdown \
  -f performance_envelope_benchmark_test.mbt
moon bench --release --target js -p dowdiness/markdown \
  -f performance_envelope_benchmark_wbtest.mbt
moon bench --release --target wasm-gc -p dowdiness/markdown \
  -f performance_envelope_benchmark_test.mbt
moon bench --release --target wasm-gc -p dowdiness/markdown \
  -f performance_envelope_benchmark_wbtest.mbt
```

Use `performance_residual_benchmark_test.mbt` for the mixed-corpus acceptance
rows. Record commands, revisions, toolchain, corpus, mean and dispersion in
`benchmark_history.md` whenever a performance change is accepted.

## Correctness boundary

An optimization does not satisfy this contract if it weakens any of:

- CST source fidelity;
- AST and structured-diagnostic behavior;
- direct/incremental CST, AST, and diagnostic parity;
- the pinned CommonMark conformance contract.

If an optimization changes the returned product, compare it as a different
operation and update the architectural decision before changing these rows.
