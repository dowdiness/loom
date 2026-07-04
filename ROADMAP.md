# Roadmap: dowdiness/loom — Incremental Parser Framework

**Updated:** 2026-05-30
**Status:** Active — framework stable; Typed SyntaxNode views complete
**Goal:** A reusable, language-agnostic incremental parser framework for MoonBit. Any grammar plugs in via `LanguageSpec[T,K]` and gets green tree (CST), error recovery, subtree reuse, and a reactive pipeline for free.

> Lambda calculus example roadmap: [examples/lambda/ROADMAP.md](examples/lambda/ROADMAP.md)

---

## Target Architecture

Layer diagram and architectural principles:
[docs/architecture/overview.md](docs/architecture/overview.md) (single source of truth).

---

## Completed Work

- **Phase 0: Reckoning** ✅ (2026-02-01) — removed dead cache infrastructure (~581 lines) — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 1: Incremental Lexer** ✅ (2026-02-02) — splice-based `TokenBuffer` re-lexes only damaged region — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 2: Green Tree** ✅ (2026-02-19) — `CstNode`/`SyntaxNode`, `EventBuffer`, `seam/` package — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 3: Error Recovery** ✅ (2026-02-03) — sync-point recovery, `ErrorNode`, up to 50 errors per parse — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 4: Subtree Reuse** ✅ (2026-02-03) — `ReuseCursor` 4-condition protocol, O(depth) per lookup — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 5: Generic Parser Framework** ✅ (2026-02-23) — `ParserContext[T,K]`, `LanguageSpec[T,K]`, `parse_with` — [notes](docs/archive/completed-phases/2026-02-23-generic-parser-impl.md)
- **Phase 6: Generic Incremental Reuse** ✅ (2026-02-24) — `ReuseCursor[T,K]`, `node()`/`wrap_at()` combinators — [notes](docs/archive/completed-phases/2026-02-24-generic-incremental-reuse-design.md)
- **Phase 7: Reactive Pipeline** ✅ (2026-02-25) — `ReactiveParser`: `Signal[String]`→`Memo[CstStage]`→`Memo[Ast]` — [ADR](docs/decisions/2026-02-27-remove-tokenStage-memo.md)
- **SyntaxNode-First Layer** ✅ (2026-02-25) — `SyntaxToken`, `SyntaxElement`, `.cst` private — [notes](docs/archive/completed-phases/2026-02-25-syntax-node-first-layer.md)
- **NodeInterner** ✅ (2026-02-28) — `Interner` + `NodeInterner`, session-global interners — [notes](docs/archive/completed-phases/2026-02-25-node-interner.md)
- **Grammar Abstraction** ✅ (2026-03-01) — `Grammar[T,K,Ast]`, `new_imperative_parser`/`new_reactive_parser` — [notes](docs/archive/completed-phases/2026-03-01-extract-generic-factories.md)
- **Loom Extraction** ✅ (2026-03-01) — `core/incremental/pipeline/viz` → `dowdiness/loom` sibling module — [notes](docs/archive/completed-phases/2026-03-01-examples-folder.md)
- **Rabbita Monorepo Migration** ✅ (2026-03-02) — submodules absorbed, lambda → `examples/lambda/` — [notes](docs/archive/completed-phases/2026-03-02-rabbita-style-monorepo.md)
- **Parser API Simplification** ✅ (2026-03-02) — `ImperativeParser`/`ReactiveParser`, global interners, `diagnostics()`/`reset()`, CST equality skip — [notes](docs/archive/completed-phases/2026-03-02-parser-api-impl.md)
- **Typed SyntaxNode Views** ✅ (2026-03-03) — rust-analyzer-style typed wrappers (`LambdaExprView`, `AppExprView`, …) replacing `AstNode`; `syntax_node_to_term` via views; `SyntaxNode::Eq`/`ToJson`; `AstView` trait in loom/core — [design](docs/archive/completed-phases/2026-03-03-typed-syntax-node-views-design.md) · [impl](docs/archive/completed-phases/2026-03-03-typed-syntax-node-views.md)
- **Seam Trait Cleanup** ✅ (2026-03-04) — removed all 7 closure fields from `LanguageSpec`; replaced with MoonBit traits `IsTrivia`/`IsEof`/`ToRawKind`/`FromRawKind` on `T`/`K` type params; deleted `src/bridge/` — [design](docs/archive/completed-phases/2026-03-04-seam-trait-cleanup-design.md) · [impl](docs/archive/completed-phases/2026-03-04-seam-trait-cleanup.md)
- **AstNode Removal** ✅ (2026-03-05) — removed `AstNode`/`AstKind` entirely; `syntax_node_to_term` converts `SyntaxNode` → `Term` directly via typed views; collapsed `cst_convert.mbt` — [design](docs/archive/completed-phases/2026-03-05-remove-astnode-design.md) · [impl](docs/archive/completed-phases/2026-03-05-remove-astnode.md)
- **Term::Error Variant** ✅ (2026-03-05) — `Term::Error(String)` replaces 18 `Term::Var("<error>")` sentinels; `print_term` renders as `<error: msg>` — [notes](docs/archive/completed-phases/2026-03-05-term-error-variant.md)
- **Multi-Expression Files** ✅ (2026-03-05) — `parse_source_file`/`parse_source_file_term`; top-level `let` sequences; `LetDef`/`SourceFile` CST nodes; independent subtree reuse verified — [design](docs/archive/completed-phases/2026-03-04-multi-expression-files-design.md) · [impl](docs/archive/completed-phases/2026-03-04-multi-expression-files.md)

---

## Phase Summary

```
Phase 0: Reckoning                  ✅ COMPLETE (2026-02-01)
    |
    +------ Phase 1: Incremental Lexer      ✅ COMPLETE (2026-02-02)
    |
    +------ Phase 2: Green Tree / seam/     ✅ COMPLETE (2026-02-19)
                |
                +------ Phase 3: Error Recovery         ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 4: Subtree Reuse          ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 5: Generic Parser Ctx     ✅ COMPLETE (2026-02-23)
                |           |
                |           +-- Phase 6: Generic Reuse  ✅ COMPLETE (2026-02-24)
                |
                +------ SyntaxNode-First Layer          ✅ COMPLETE (2026-02-25)
                |           Phase 1: SyntaxNode API
                |           Phase 2: .cst private
                |           Phase 3: Typed views        ✅ COMPLETE (2026-03-03)
                |
                +------ Phase 7: Reactive Pipeline      ✅ COMPLETE (2026-02-25)
                |
                +------ NodeInterner                    ✅ COMPLETE (2026-02-28)
                |
                +------ Grammar Abstraction             ✅ COMPLETE (2026-03-01)
                |
                +------ Loom Extraction                 ✅ COMPLETE (2026-03-01)
                |
                +------ Rabbita Monorepo Migration      ✅ COMPLETE (2026-03-02)
                |
                +------ Parser API Simplification       ✅ COMPLETE (2026-03-02)
                |
                +------ Typed SyntaxNode Views          ✅ COMPLETE (2026-03-03)
                |
                +------ Seam Trait Cleanup              ✅ COMPLETE (2026-03-04)
                |
                +------ AstNode Removal                 ✅ COMPLETE (2026-03-05)
                |
                +------ Term::Error Variant             ✅ COMPLETE (2026-03-05)
                |
                +------ Multi-Expression Files          ✅ COMPLETE (2026-03-05)
```

---

## Milestones

| Milestone | Status |
|-----------|--------|
| Honest Foundation (Phase 0) | ✅ Complete (2026-02-01) |
| Incremental Lexer (Phase 1) | ✅ Complete (2026-02-02) |
| Green Tree / CST (Phase 2) | ✅ Complete (2026-02-19) |
| Error Recovery (Phase 3) | ✅ Complete (2026-02-03) |
| Subtree Reuse (Phase 4) | ✅ Complete (2026-02-03) |
| Generic Parser Framework (Phase 5) | ✅ Complete (2026-02-23) |
| Generic Incremental Reuse (Phase 6) | ✅ Complete (2026-02-24) |
| Reactive Pipeline (Phase 7) | ✅ Complete (2026-02-25) |
| NodeInterner | ✅ Complete (2026-02-28) |
| Grammar Abstraction | ✅ Complete (2026-03-01) |
| Infrastructure Extraction (dowdiness/loom) | ✅ Complete (2026-03-01) |
| Rabbita Monorepo Migration | ✅ Complete (2026-03-02) |
| Parser API Simplification | ✅ Complete (2026-03-02) |
| Typed SyntaxNode Views | ✅ Complete (2026-03-03) |
| Seam Trait Cleanup | ✅ Complete (2026-03-04) |
| AstNode Removal | ✅ Complete (2026-03-05) |
| Term::Error Variant | ✅ Complete (2026-03-05) |
| Multi-Expression Files | ✅ Complete (2026-03-05) |

---

## TODO

- [x] ~~Delete local `graphviz/` module and switch `loom/moon.mod.json` to the published `graphviz` package version~~ — **done** via PR #98 (2026-04-22): swapped broken `antisatori/graphviz` path-dep for published `dowdiness/graphviz@0.1.0` (namespace is owned by `dowdiness/`, not `antisatori/`).
- [x] ~~**#58** Add `Folder` / `TransformFolder` / `Finder` / `MutVisitor` traits to `seam/` for zero-cost traversal~~ — **Folder, TransformFolder, Finder all done** (`seam/cst_traits.mbt:16,30`, `seam/cst_traverse.mbt:185`). `MutVisitor` deferred — see #59. The "zero-cost" framing was partially invalidated by the 2026-04-19 bench (closures match or beat traits for benchmarked workloads); only build new traits if a concrete consumer shows measurable closure-perf wall.
- [ ] **#60** Extract `walk_children_flat` into a public `CstNode::each` method — **deferred**. 2026-04-22 verification: (a) `each` name collides with the existing public `CstElement::each` (`seam/cst_traverse.mbt:89`, depth-first tree walker with early-termination Bool callback) — two `each` methods at adjacent types with different callback shapes is a readability cost; (b) promised "dedup" doesn't materialize — all 6 internal callers need `parent : SyntaxNode` + `offset : Int` threaded through callbacks, so method form barely improves on the private helper; (c) no concrete external consumer. Apply the "require a concrete consumer" rule used for #58/#59; keep `walk_children_flat` private until demand appears.
- [ ] **#59** `MutVisitor` for `CstNode::new()` metadata — **deferred**. 2026-04-19 bench shows `build_tree with ReuseNode` (which drives `CstNode::new`) completes in 34.72 µs for a 50×100 token tree. Not on the critical path, per the ROADMAP item's own caveat. Do not build speculatively; require a concrete consumer with a measured closure-perf wall first. See `docs/analysis/2026-04-19-architecture-diagnosis.md` §6 Stage B.
- [x] ~~**#62** Clean up `cst-transform/` before merge: remove `transform_cps` and `transform_view`.~~ — **done** 2026-05-08: entire `cst-transform/` package deleted (zero canopy consumers; production traits live in `seam/`). Feasibility report preserved at `docs/performance/2026-03-30-cst-traversal-tiers.md`.
- [x] ~~**#61** Explore token text as source spans (zero-copy lexing)~~ — **implemented 2026-05-30**. `CstToken` now stores source spans and exposes `text() -> StringView`; the generic parser builds non-interned span-backed CSTs. Public `ReuseNode` rebuilds with owned token text, while parser-owned reuse rebases token spans onto the current source buffer to avoid retaining old full source strings. See updated ADR [2026-03-14](docs/decisions/2026-03-14-physical-equal-interner.md).
- [x] ~~**#186** Seam API hardening before stabilization~~ — **implemented 2026-05-30**. Backing-source inspection now uses the explicitly unstable `CstToken::unsafe_backing_source()` name (`CstToken::source()` is deprecated), parser-owned rebase hooks now use `EventBuffer::push_parser_reuse_node_rebased*` names (old `push_reuse_node_at*` names are deprecated), and public application reuse remains `push(ParseEvent::ReuseNode(...))` with owned token text.
- [x] ~~**#187** Recover incremental reuse performance after #61~~ — **implemented 2026-05-30**. Added benchmark coverage for matching-source parser-owned rebase and a validated unchecked parser path (`push_parser_reuse_node_rebased_unchecked`) that keeps current-source-backed token views without direct-splicing old nodes or retaining old source buffers. Benchmarks for the 50×100-token reuse tree: safe matching rebase ~140µs vs unchecked ~104µs on wasm-gc, and ~199µs vs ~125µs on JS. Downstream physical-identity consumer found in canopy was migrated to structural `CstNode` equality before the parent submodule bump.
- [ ] `children_iter` (lazy, no-alloc) on `SyntaxNode` — **deferred, perf opportunity**. `SyntaxNode::children()` allocates a fresh `Array[SyntaxNode]` on every call (`seam/syntax_node.mbt:184`). The lambda example's `callers` projection (`examples/lambda/src/callers/callers.mbt`) — first identified consumer — hits this in its tree-walk catch-all branch on every CST edit. Only build once a concrete bench shows the allocation cost on the Derived recompute budget; same "require a concrete consumer" rule as #58/#59/#60.
- [x] ~~**Authoring identity after deletion/shift edits**~~ — **resolved for the
  current Loom contract** by PR #135 (2026-05-21). Pure deletion can preserve
  reusable left-adjacent CST subtrees when leading and trailing token context
  still validates. Parser-owned token/subtree identity projection is deferred:
  add it only if a downstream workflow needs stable logical identity through
  insertion, replacement, token split/merge, full reparse, or AST/domain
  projection.
- [x] ~~**Prefer edit-based reuse cursor construction**~~ — **done**
  2026-05-21: `ReuseCursor::new_with_edit` is documented as the parser-owned
  incremental path. Raw damage-coordinate `ReuseCursor::new` remains available
  as a low-level escape hatch for focused tests and infrastructure; example
  raw-coordinate helpers now route through `Edit`.
- [x] ~~**Name the incremental reuse contract explicitly**~~ — **done**
  2026-05-21: public docs name validated CST subtree reuse, not stable
  parser-owned identity. The correctness doc covers deletion-only
  left-adjacent relaxation, token-merge conservatism, and the concrete-consumer
  threshold for any future identity projection.
- [x] ~~**Systematic edit-matrix parser tests**~~ — **done** 2026-05-21:
  lambda parser differential tests now cover deletion, insertion, replacement,
  token merge, token split, prefix/suffix/middle edits, and repeated edit
  sequences. The primary oracle is structural AST equality against a full
  reparse; the only new reuse-count assertion is the unambiguous same-length
  sibling `let` reuse fixture.
- [x] ~~**Reuse rejection diagnostics**~~ — **done** 2026-05-21: core
  whitebox tests can inspect why a regular node reuse candidate was rejected:
  global disable, edited offset, missing candidate, size policy, damage overlap,
  leading-token mismatch, or follow-token mismatch. The hook is package-private,
  so release behavior and public API stay unchanged.
- [x] ~~**Reuse policy API cleanup**~~ — **no change needed** 2026-05-21:
  rejection diagnostics did not add policy knobs. Keep the single
  `allow_left_adjacent_reuse` boolean until a second real knob appears; do not
  introduce `ReusePolicy` preemptively.
- [x] ~~Redesign FlatProj for flat AST~~ — Resolved by PR #37: `from_proj_node` removed from hot path. Tree edits now produce text deltas directly via source map. Known limitation: `Drop` moves child text without surrounding operators/separators.

---

## What This Roadmap Does NOT Include

1. **Parser generation.** Hand-written recursive descent remains the production
   path; checkpoint-based reuse compensates for lower reuse granularity vs
   Lezer/tree-sitter. The reified grammar-IR substrate (`loom/src/grammar/`,
   added in PR #443) drives the lambda example via a tree-walking interpreter.
   The incremental-throughput gate (#444) has now been **run** (3 passes,
   wasm-gc): on the common incremental path (flat tail edits) the interpreter is
   at parity with hand-written recursive descent (B/A ≈ 0.9–1.0×), with no
   consistent raw-parse penalty (slower on flat full parse, *faster* on deep).
   The one consistent deficiency, surfaced by stress-testing deep nested
   structures, is **deep-subtree reuse granularity**: a wall-clock control
   confirms B re-parses deep nested subtrees instead of reusing them (B's deep
   per-edit cost ≈ its full-parse cost, while A's is ≪), costing ~1.15–2.4× on
   deep nested-structure edits — see
   [ADR 2026-06-22](docs/decisions/2026-06-22-grammar-incremental-throughput-gate.md)
   and `examples/lambda/benchmarks/grammar_incremental_benchmark.mbt`.
   **Outcome:** the tree-walking interpreter **graduates** as a kept, validated
   framework substrate, while the **code-emitter stays deferred with a named
   motivation** — closing that deep-subtree reuse gap (emitted code can establish
   the reuse checkpoints the generic interpreter lacks; tracked as #449). Emission
   is off the production roadmap until a consumer hits a deep-grammar incremental
   workload;
   shipped examples (lambda, JSON) are shallow enough that B is already at parity.
   `@grammar` remains **unblessed by the root facade** until it has a non-spike
   consumer.
2. **GLR or Earley parsing.** Unambiguous grammars don't need generalized parsing.
3. **Language server protocol.** An LSP layer sits on top of the CST; out of scope here.
4. **Evaluation / type checking.** This is a parser framework roadmap.
5. **Lambda calculus grammar expansion.** See [examples/lambda/ROADMAP.md](examples/lambda/ROADMAP.md).

---

## Cross-Cutting Concern: Incremental Correctness

**Invariant:** For any edit, incremental parse must produce a tree structurally identical to full reparse.

Verified via differential oracle (random source + random edits → compare incremental vs full reparse result). Property-based fuzzing with sequences of 10–100 random edits catches state accumulation bugs. Status: ✅ verified. New grammars plugged in via `LanguageSpec` must extend the oracle when added.

---

## Success Criteria for "Stabilized"

1. **Correctness:** Incremental parse produces identical trees to full reparse for any edit, verified by property-based testing over millions of random edits.
2. **Performance:** Single-character edits in a 1000-token file complete in under 100 microseconds (not counting initial parse).
3. **Error resilience:** Any input (including random bytes) produces a tree without panicking.
4. **Architecture:** No dead infrastructure. New grammar rules require only parser + syntax kind enum changes.
5. **Test coverage:** >95% line coverage on parser, lexer, tree builder, and incremental engine.
6. **Documentation:** Every public API has doc comments. Architecture decisions documented with rationale.

---

## References

### Architecture Inspiration
- [Roslyn's Red-Green Trees](https://ericlippert.com/2012/06/08/red-green-trees/)
- [rust-analyzer Architecture](https://github.com/rust-lang/rust-analyzer/blob/master/docs/dev/syntax.md)
- [swift-syntax](https://github.com/apple/swift-syntax)

### Incremental Parsing
- Wagner & Graham (1998) - [Efficient and Flexible Incremental Parsing](https://harmonia.cs.berkeley.edu/papers/twagner-parsing.pdf)
- [Lezer](https://lezer.codemirror.net/) — LR-based incremental parsing (inspiration, not template)
- [Tree-sitter](https://tree-sitter.github.io/) — Generated recursive descent with incrementality

### Error Recovery
- [Error Recovery in Recursive Descent Parsers](https://www.cs.tufts.edu/~nr/cs257/archive/donn-seeley/repair.pdf)
- [Panic Mode Recovery](https://en.wikipedia.org/wiki/Panic_mode)

### CRDT and Collaborative Editing
- Gentle et al. (2024) - [eg-walker: Mergeable Tree Structures](https://arxiv.org/abs/2409.14252)
- [diamond-types](https://github.com/josephg/diamond-types) — Rust reference implementation
- [Loro](https://loro.dev) — Production CRDT library; `TextDelta (Retain | Insert | Delete)`
- [Quill Delta format](https://quilljs.com/docs/delta/) — Retain/Insert/Delete with lengths

### MoonBit
- [MoonBit Language Reference](https://www.moonbitlang.com/docs/syntax)
- [MoonBit Core Libraries](https://mooncakes.io/docs/#/moonbitlang/core/)
