# ADR: Remove `emit_grammar.mbt` — code-generated parser is no longer justified

**Date:** 2026-07-10
**Status:** Accepted
**Issue:** [#671](https://github.com/dowdiness/loom/issues/671)
**Supersedes:** [2026-06-22-grammar-incremental-throughput-gate.md](2026-06-22-grammar-incremental-throughput-gate.md) — the ADR that deferred the emitter
**Benchmark:** `examples/lambda/benchmarks/grammar_incremental_benchmark.mbt`

## Context

The `@grammar.interpret` tree-walking interpreter was graduated in ADR 2026-06-22
with one caveat: a deep-subtree reuse gap caused B (interpreter) to re-parse the
whole deep tree on each edit, costing ~1.15–2.4× vs A (hand parser). The code
emitter (`loomgen/emit_grammar.mbt`, 766 lines + ~1000 lines of fixtures/tests)
was deferred as the named fix for that gap, gated on [#449].

PR [#476] closed the reuse gap on 2026-06-26 by fixing the malformed-tree
contamination that prevented B from reusing deep nested subtrees. The validity
guard `deep-edit reuse: A=7 B=0` became `A=7 B=7`. The condition for re-opening
the emitter was met — but re-measuring showed that even without the emitter,
B is now **at full parity and faster than A** on the incremental hot path.

## Benchmark data (2026-07-10, wasm-gc on WSL2)

| Metric | A (hand parser) | B (`interpret`) | B/A |
|---|---|---|---|
| Flat — full parse | 104.44 µs | 131.53 µs | 1.26× |
| Deep — full parse | 133.90 µs | 166.45 µs | 1.24× |
| Flat — incremental (8 edits) | 598.71 µs | 570.52 µs | **0.95×** |
| Deep — incremental (8 edits) | 729.99 µs | 664.60 µs | **0.91×** |

Full parse: B is consistently ~25% slower — expected interpreter overhead. This
is not the hot path.

On the **incremental hot path** (what a user experiences while typing): B is
faster than hand-written A on both workloads (0.95× and 0.91×). The dominant
costs (damage tracking, SyntaxNode facade reconstruction, diagnostics) are
shared; `parse_root` runs only on the damaged region, so the interpreter's
overhead disappears into the noise at the flat parity already measured, and on
deep edits the interpreter is now *structurally faster* than the hand code.

## Decision

1. **Delete `loomgen/emit_grammar.mbt`** and all associated test/fixture files.
   The emitter generates MoonBit `parse_<Rule>` source code that duplicates the
   semantics of `@grammar.interpret`. The sole performance justification
   (deep-subtree reuse gap) no longer exists. The emitter carries ~1766 lines
   of maintenance burden with no measurable benefit.

2. **Keep `@grammar.interpret` as the only parser backend.** The tree-walking
   interpreter is at throughput parity or better on all workloads. The remaining
   loomgen generators (syntax_kind, token_impls, views, lexer, spec, lexmode,
   GrammarIr data) are unaffected — these are MoonBit boilerplate generators
   with no runtime alternative.

3. **Close issue [#449].** The deep-subtree reuse gap that motivated the emitter
   is resolved by #476. No further work on a code-generated parser is planned.

## Consequences

- **Positive**: loomgen shrinks to code that moon prove can verify. The emitter's
  output (a MoonBit source `String`) was not provably equivalent to `interpret`.
- **Positive**: removes `@pretty` indirect dependency through `mbt_ast.mbt` (the `@pretty.Pretty` impl for `MbtModule` is deleted). Direct `@pretty` usage in `emit_grammar_ir.mbt` is unaffected — it uses `@pretty.Layout` directly for formatting GrammarIr data.
- **Positive**: `loomgen/mbt_ast.mbt` trims from 581 lines to the subset used by
  `emit_grammar_ir.mbt` (`MbtExpr`, `MbtPat`, `MbtMatchArm`, `MbtParam`).
- **Positive**: removes 3 fixture parity packages (`grammar_parity/`,
  `grammar_parity_reuse/`, `grammar_parity_native/`) and the
  `--regenerate-fixtures` CLI flag's grammar-parity code path.
- **Neutral**: ADR 2026-06-22 and ADR 2026-07-03 (structural AST testing) are
  marked as superseded but kept in the archive index for historical context.
- **No runtime impact**: The emitter's output was never consumed by production
  code. All examples use `@grammar.interpret` or hand-written parsers.

## References

- [#444]: benchmark gate for `@grammar` incremental throughput
- [#449]: tracked the deep-subtree reuse gap (now closed)
- [#476]: fixed malformed-tree contamination on lambda deep-edit workload
- [2026-06-22 ADR](2026-06-22-grammar-incremental-throughput-gate.md): the gate
  that graduated the interpreter and deferred the emitter

[#444]: https://github.com/dowdiness/loom/issues/444
[#449]: https://github.com/dowdiness/loom/issues/449
[#476]: https://github.com/dowdiness/loom/issues/476
