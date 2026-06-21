# Parser-Generation Spike Results

**Status:** Complete  
**Date:** 2026-06-21  
**Spike plan:** [superpowers/plans/2026-06-20-parser-generation-spike.md](../superpowers/plans/2026-06-20-parser-generation-spike.md)  
**Decision record:** no new ADR needed — this doc serves as the decision record (cross-reference: [analysis/2026-06-20-parser-generation-direction.md](2026-06-20-parser-generation-direction.md) §Spike gating)

---

## Verdict: CONDITIONAL GO

Safety gates all pass. Ergonomics gates reveal missing IR combinators (Seq, Pratt) that block a useful second-grammar encoding. The architecture is sound — proceed to IR extension as the next investment, then re-spike E3 with the extended IR.

---

## What Was Built

Tasks 0–14 of the spike plan were executed in `examples/lambda/src/spike/`:

| File | Purpose |
|------|---------|
| `types.mbt` | `GrammarIr`, `Expr` enum, `RuleId`, `DivergenceClass` |
| `interpreter.mbt` | `interpret(ir)` → `parse_root` closure; all Expr variants |
| `lambda_ir.mbt` | `lambda_spike_ir()`, `build_b_syntax_grammar()`, `normalized_syntax_grammar()` |
| `leaves.mbt` | `project_lambda_leaves()` — deterministic CST leaf extractor |
| `oracle.mbt` | `run_oracle_fixture()`, D1/D2a/D2b/reuse-parity checks, divergence classifier |
| `fixtures.mbt` | Edit-sequence fixtures covering let-defs, Pratt, error recovery, combined |
| `measurements.mbt` | E1/E2/E3 ergonomics measurements and E3 probe plan |

**Config-normalization invariant:** Both parser A (hand-written `parse_lambda_root`) and parser B (IR-interpreted) are built through `normalized_syntax_grammar(spec, lex)` with `incremental_relex_enabled=false, block_reparse_spec=None`. Only `parse_root` differs between A and B.

---

## Safety Oracle Results

### D1: Incremental matches fresh

**PASS** — all fixtures, both A and B.

For every edit step across all fixtures (let-def, app/bop Pratt, error recovery, combined), the incremental parse result equals a fresh full parse on the same source. B's interpreted `parse_root` is incrementally correct.

### D2a: A and B parse trees are structurally identical

**PASS (structural) + REPLICATION_RESIDUAL noted.**

CST `tree_diff` is empty for all fixtures. Diagnostic structural fields (`source`, `severity`, `code`, `primary`) are equal between A and B for all fixtures.

**ReplicationResidual finding:** B's error message wording differs from A's on malformed inputs ("delete second RHS" step in the combined fixture). This is a cross-implementation wording difference, not a structural divergence. It does NOT block GO. Filed as a known deviation.

### D2b: Stable projection IDs agree

**PASS** (with honesty scoping documented).

Both trackers seeded before first `apply_edit`. Stable IDs agree across all non-malformed steps. Malformed intermediates recorded correctly; recovery resumes correctly.

**Honesty scoping (Task 9):** Under this wiring, D2b is not an independent path-dependence oracle — a D2b mismatch implies a D2a CST mismatch. D2b's independent value is: (1) hash-collision blind spot guard, (2) consumer-facing stable-ID assertion. Both are exercised by the fixtures.

### REUSE-PARITY: reuse counts match

**VACUOUS** (Task 10 finding).

`reuse_count` in `SyntaxSnapshot` tracks both repeat-group reuse (`try_reuse_repeat_group`) and engine-level node reuse (`ctx.node()` fast-path). When repeat-group reuse is disabled (crippled B), engine-level reuse compensates — yielding the same count. REUSE-PARITY is always satisfied and provides no signal for this spike.

**Implication:** The repeat-group reuse optimization is PERFORMANCE-ONLY and does not affect `reuse_count`. Throughput comparison between A and B requires benchmarking (Task 13 E3 probe), not oracle comparison.

---

## Ergonomics Results

### E1: Rule coverage ratio

**1 / 7 (~14%) rules are truly declarative.**

| Rule | Classification | Reason |
|------|---------------|--------|
| Source | **Declarative** | `RepeatTopLevel` dispatched generically through `run_expr` |
| Definition | Hardcoded | `parse_definition_ir` called directly by `parse_top_level_repeat`, never via IR |
| Expression | Hardcoded (dependent) | `Ref(Binary)` special-cased in `run_expr` |
| Binary | Hardcoded | `parse_binary_ir` — Pratt binary; special case in `run_expr` |
| Application | Hardcoded | `parse_application_ir` — Pratt application; special case in `run_expr` |
| Atom | Escape hatch | `ManualAtom` — no `Seq` combinator in IR to express paren/block/error |
| ParamList | Escape hatch | `ManualParamList` — comma-delimited token loop not expressible in IR |

### E2: Lambda-specific escape hatches

**2 escape hatches, 2 missing combinators.**

| Missing combinator | Impact |
|--------------------|--------|
| `Seq` — sequential token emission + recursion | Blocks Atom, paren-expr, block-expr encoding |
| `Pratt` — infix operator and left-associative application table | Blocks Binary, Application encoding |

Without these two combinators, most grammar rules fall back to hardcoded `parse_*_ir` functions, providing minimal declarative benefit over hand-writing the grammar.

### E3: Second-grammar reuse probe

**BLOCKED** on E2 findings.

The E3 probe (build a second grammar, JSON-like, and run the oracles) would accumulate the same escape hatches before proving generalization. E3 is only meaningful after adding `Seq` and `Pratt` to `GrammarIr.Expr`. Target: E1 ≥ 5/7 for the second grammar as the GO gate for full loomgen investment.

---

## Decision

### What the spike proved

1. The oracle infrastructure is correct and exercisable. D1/D2a/D2b all pass on a non-trivial grammar with error recovery, Pratt parsing, and multi-definition sources.
2. The architecture supports grammar-as-data: a `GrammarIr` → `parse_root` → loom engine pipeline is viable. The `normalized_syntax_grammar` wrapper correctly isolates the parse function as the only variable between A and B.
3. `reuse_count` is not a useful parity oracle — both repeat-group and node-level reuse increment it.
4. The current IR is too thin: 1/7 rules declarative, 5/7 hardcoded/escaped.

### What must happen before full loomgen investment

1. Add `Seq` combinator to `GrammarIr.Expr` — allows expressing "emit token A, recurse, expect token B" without an escape hatch.
2. Add `Pratt` combinator (infix operator table + application precedence) to `GrammarIr.Expr`.
3. Re-spike E3: build a minimal second grammar (JSON-like, no Pratt needed) with the extended IR. Target E1 ≥ 5/7.
4. If E3 passes, loomgen can proceed to code-generation stage.

### What does NOT need to change

- The oracle harness (D1/D2a/D2b) is reusable as-is.
- The `normalized_syntax_grammar` pattern is correct — use for all future spike grammars.
- `project_lambda_leaves` + `ProjectionIdentityTracker` seeding protocol works correctly.

---

## Commit history

| Commit | Task | Description |
|--------|------|-------------|
| c182f68 | 0 | Spike moon.pkg |
| (prior context) | 1–7 | Types, interpreter, leaves, oracle stubs |
| 76f5128 | 8 | Lambda IR, `build_b_syntax_grammar`, B smoke tests |
| eac37b8 | 9 | Persistent A-vs-B oracle harness |
| fd084cf | 10 | REUSE-PARITY positive control + finding |
| effa11e | 11 | Divergence classifier and stop condition |
| e940102 | 12 | E1/E2 ergonomics measurements |
| 691cfad | 13 | E3 second-grammar reuse probe plan |
