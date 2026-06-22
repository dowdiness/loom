# ADR: `@grammar` incremental-throughput gate — graduate the interpreter, defer the emitter as the named fix for a deep-subtree reuse gap

**Date:** 2026-06-22
**Status:** Accepted
**Issue:** [#444](https://github.com/dowdiness/loom/issues/444)
**Supersedes:** the interim in-PR annotation from [#443](https://github.com/dowdiness/loom/pull/443); finalizes the ROADMAP "Parser generation" deferral.
**Benchmark:** `examples/lambda/src/benchmarks/grammar_incremental_benchmark.mbt`
**Spec gated:** [docs/superpowers/specs/2026-06-21-loomgen-ir-contract-design.md](../superpowers/specs/2026-06-21-loomgen-ir-contract-design.md) §6.

## Context

PR #443/#445 added the reified grammar-IR substrate `loom/src/grammar/`
(`@grammar`) and drives the lambda example through it via a tree-walking
interpreter (B), re-validating D1/D2a/D2b parity against the hand-written
recursive-descent lambda parser (A). PR #446 added an A-vs-B separator fuzzer —
a **correctness** proof that A and B agree. Neither said anything about **speed**.

The spec (§6) committed the tree-walking interpreter as the one backend and
**deferred the analyzing/table-driven interpreter and the code-emitter behind a
single benchmark gate**: incremental edit throughput (`apply_edit` cycles, *not*
fresh full-parse). The spec is explicit (§6/§D) that loom is incremental, so
monogram's analyze-once speedup is **not** assumed to carry — the throughput
question was genuinely open. ROADMAP "Success Criteria for Stabilized" #4 ("no
dead infrastructure") makes the cost of leaving an unjustified interpreter in the
framework tree concrete.

This ADR records the result of running that gate.

## The benchmark

`grammar_incremental_benchmark.mbt` builds A and B through the spike's
`normalized_syntax_grammar`, so the **only** difference between the two parsers
is `spec.parse_root` (A's hand parser vs B's `@grammar.compile(...)` +
tree-walking interpreter). Both are driven exactly as the D1/D2a/D2b oracle
drives them: `@loom.new_syntax_parser` → `apply_edit` → force-read
`snapshot().read_or_abort()`.

Two workloads, each measured at full-parse and as an 8-edit incremental session
(net-neutral, replayed against a parser built **once** outside the measured
loop):

- **Flat** — an 80-definition `let`-chain; the incremental session types ` + 1`
  at the buffer tail and deletes it (the common editor hot path).
- **Deep** — a 20-definition chain of deeply-nested lambdas; the incremental
  session flips leaves buried inside the last definition's nested structure
  (the stress case the perf discipline demands — test the weakest input).

Measured on wasm-gc (`moon bench --release`), **three full passes** (per-run σ is
high — WSL2 system noise — so the verdict rests on direction repeated across
runs, never a single number):

| Metric | A (hand) | B (interp) | B / A |
|---|---|---|---|
| Flat — full parse | 465 / 300 / 575 µs | 703 / 508 / 577 µs | 1.51 / 1.69 / 1.00 |
| Flat — incremental (8 edits) | 2.74 / 2.47 / 2.97 ms | 2.80 / 2.20 / 2.75 ms | **1.02 / 0.89 / 0.93** |
| Deep — full parse | 751 / 691 / 814 µs | 488 / 468 / 545 µs | **0.65 / 0.68 / 0.67** |
| Deep — incremental (8 edits) | 4.21 / 1.61 / 3.18 ms | 4.82 / 3.84 / 4.25 ms | 1.15 / 2.39 / 1.34 |

The validity guards (permanent tests in the same file) print, per run:
`tail-edit reuse: A=1 B=1`, `flat in-place reuse: A=8 B=8`,
`deep-edit reuse: A=7 B=0`.

## Interpretation

**1. B has no consistent raw-parse penalty.** The full-parse rows are
workload-dependent and cut both ways: B is slower on the flat chain (1.0–1.7×)
but *faster* on the deep chain (consistently ~0.67×). There is no single
"interpreter overhead" constant — tree-walk + `Pred::test` dispatch is a wash
against inlined hand code, sometimes better. So raw parse speed is **not** a
graduation concern.

**2. B is at parity on the common incremental path.** On the flat tail-edit
session — the editor hot path — B/A is 1.02 / 0.89 / 0.93 across three runs:
B is as often faster as slower than A. The `flat in-place reuse: A=8 B=8` guard
confirms B reuses identically to A on a shallow in-place edit. Incrementality is
the amortizer: `parse_root` runs only on the damaged region while the dominant
per-edit costs (damage tracking, projecting the full `SyntaxNode` facade +
diagnostics) are identical for A and B and dilute the `parse_root` difference to
nothing.

**3. The one consistent deficiency is deep-subtree reuse granularity.** On a deep
nested-lambda edit, the `deep-edit reuse: A=7 B=0` guard says A reuses subtrees B
does not. Because the spec (§6) flags `reuse_count` as potentially "vacuous"
(engine-level node reuse can compensate for missing repeat-group reuse, uncounted),
this ADR does **not** rest the claim on the counter. The deep **full-parse**
control benchmark corroborates it by wall clock:

| Workload | B per-edit (session/8) | B full-parse | per-edit ÷ full | Reuse? |
|---|---|---|---|---|
| Deep | 602 / 480 / 531 µs | 488 / 468 / 545 µs | **1.23 / 1.03 / 0.97** | **NO** |
| Flat | 350 / 275 / 344 µs | 703 / 508 / 577 µs | 0.50 / 0.54 / 0.60 | yes |

And the same control on A (the control's control):

| Workload | A per-edit | A full-parse | per-edit ÷ full | Reuse? |
|---|---|---|---|---|
| Deep | 526 / 201 / 398 µs | 751 / 691 / 814 µs | **0.70 / 0.29 / 0.49** | **yes** |

B's deep per-edit cost ≈ its full-parse cost every run (ratio ≈ 1.0) — B
re-parses the whole deep tree on each edit. A's deep per-edit is ≪ its full-parse
every run (ratio ≈ 0.3–0.7) — A reuses. The wall clock independently confirms the
counter: B's reuse deficiency on deep nested structures is **real**, not a
counter artifact. This is the cause of the deep-tier slowdown.

The resulting deep-incremental B/A penalty is consistently present but its
*magnitude* is noisy (1.15–2.4×). The noise lives in **A's baseline**, not B:
A's deep-incremental is bimodal (4.21 / 1.61 / 3.18 ms, with disjoint confidence
intervals — a reuse-path behavior, not sampling jitter), while B's is steady
(4.82 / 3.84 / 4.25 ms). Hence the ADR reports the **range**, not a mean — the
mean of bimodal-disjoint data represents neither mode.

## Decision

The gate produces **two separable verdicts**, and collapsing them into one
graduate/sunset bit would lose the finding:

1. **Graduate the reified IR + tree-walking interpreter.** B is *not* a
   throughput liability: parity on the common incremental path (flat B/A ≈
   0.9–1.0×) and no consistent raw-parse penalty (slower flat, faster deep). The
   dead-infrastructure risk on **performance** grounds is cleared. `@grammar`
   stays in `loom/src/grammar/` as the committed interpreter substrate.

2. **Defer the code-emitter — now with a *named* motivation, not "TBD".** The gate
   was designed to let throughput justify building specialized emitted code.
   Earlier in this investigation the result read as "no per-edit gap to close";
   stress-testing the deep workload corrected that. There **is** one concrete,
   bounded gap: B does not reuse deep nested subtrees (control-confirmed across
   three runs), costing ~1.15–2.4× on deep nested-structure edits. The emitter
   (and the analyzing/table-driven interpreter that feeds it) is the natural fix —
   emitted/specialized code can establish the A-equivalent reuse checkpoints at
   nested boundaries that the generic tree-walking interpreter currently lacks
   (tracked as [#449](https://github.com/dowdiness/loom/issues/449)).
   It stays deferred until a **real consumer hits deep-grammar incremental
   workloads** (the lambda/JSON examples are shallow enough that B is already at
   parity). Per spec §6: reification *enables* the emitter; this benchmark
   confirms it does not yet *justify* it for shipped workloads, while naming
   exactly what would.

### Blessing / facade re-export

`@grammar` remains **unblessed by the root facade** for now. Its only consumers
today are the lambda spike and the JSON E3 grammar — both spike/test code. The
performance gate pausing the dead-infrastructure clock is necessary but not
sufficient for full blessing; that should wait for a **non-spike (production)
consumer**. Keeping it in `loom/src/grammar/` unblessed is the honest middle
state: validated substrate, not yet public API.

## Residues and growth points (tracked, not blocking)

Unchanged by this gate; they bound any future "cross-language" claim, not the
throughput verdict:

- The deep-subtree reuse gap (this ADR) is the headline future-work item for the
  emitter/analyzing-interp; it is the thing that would re-open the deferral.
  Tracked: [loom #449](https://github.com/dowdiness/loom/issues/449).
- Two probe-local residues remain (`ManualNewlineAppExpr` recursion-threaded
  mode; atom-position error recovery) — spec §5.3.
- Two `Pred` growth points (bounded-scan lookahead, token-text predicates) are
  known future vocabulary extensions — spec §4.
- The L1-A RawKind/content-hash identity issue (loom #427 / canopy #729) is a
  separate, non-blocking gate for the eventual emitter, not the interpreter
  benchmarked here.

## Consequences

- ROADMAP "What This Roadmap Does NOT Include" §1 is updated from "*under active
  spike, gate not yet run*" to its final state: gate run, interpreter graduated,
  emitter deferred with a named motivation (close the deep-subtree reuse gap).
- A regression guard (`grammar_incremental_benchmark.mbt`) now exists; the
  `deep-edit reuse: A=7 B=0` test will **fail if B's deep reuse is later improved**
  — that failure is the signal to revisit this graduate-with-caveat verdict.
- The emitter is not on the production roadmap. Re-opening it requires a consumer
  with a deep-grammar incremental workload (or a non-incremental analyze-once axis).

## Caveats

- Measured on **wasm-gc** (the `moon bench` default). Canopy targets the web (JS).
  A JS-target confirmation (Node harness over the generated parser) would
  strengthen the verdict, but is unlikely to flip the flat-incremental parity or
  the control's per-edit-vs-full-parse direction; recorded as a follow-up, not a
  blocker.
- Per-run variance is high (WSL2). The flat-parity and deep-reuse-deficiency
  verdicts each repeat across all three runs in *direction*; the deep-slowdown
  *magnitude* (1.15–2.4×) does not converge because A's deep-incremental baseline
  is bimodal. The decision rests on the repeated direction and the control, not
  on any single magnitude.
