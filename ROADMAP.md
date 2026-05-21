# Roadmap: dowdiness/loom — Incremental Parser Framework

**Updated:** 2026-05-21
**Status:** Active — framework stable; Typed SyntaxNode views complete
**Goal:** A reusable, language-agnostic incremental parser framework for MoonBit. Any grammar plugs in via `LanguageSpec[T,K]` and gets green tree (CST), error recovery, subtree reuse, and a reactive pipeline for free.

> Lambda calculus example roadmap: [examples/lambda/ROADMAP.md](examples/lambda/ROADMAP.md)

---

## Target Architecture

```
                        +-----------------------+
                        |     Edit Protocol     |
                        |  (apply, get_tree)    |
                        +-----------+-----------+
                                    |
                        +-----------v-----------+
                        |   Incremental Engine  |
                        |   - Damage tracking   |
                        |   - Reuse decisions   |
                        |   - Orchestration     |
                        +-----------+-----------+
                                    |
                  +-----------------+------------------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |  Incremental Lexer  |            |  Incremental Parser   |
       |  - Token buffer     |            |  - Subtree reuse at   |
       |  - Edit-aware       |            |    grammar boundaries |
       |  - Only re-lex      |            |  - Checkpoint-based   |
       |    damaged region   |            |    validation         |
       +----------+----------+            +-----------+-----------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |    Token Buffer     |            |   Green Tree (CST)    |
       |  - Contiguous array |            |  - Immutable nodes    |
       |  - Position-tracked |            |  - Structural sharing |
       |  - Cheaply sliceable|            |  - Lossless syntax    |
       +---------------------+            +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Red Tree (Facade)   |
                                          |  - Absolute positions |
                                          |  - Parent pointers    |
                                          |  - On-demand          |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Typed AST (Lazy)    |
                                          |  - Semantic analysis  |
                                          |  - Derived from CST   |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Error Recovery      |
                                          |  - Integrated in      |
                                          |    parser loop        |
                                          |  - Sync point based   |
                                          |  - Multiple errors    |
                                          +-----------------------+
```

### Architectural Principles

1. **No dead infrastructure.** Every cache, buffer, and data structure must be read by something during the parse pipeline.
2. **Immutability enables sharing.** Green tree nodes are immutable. When nothing changed, the old node IS the new node — not a copy, the same pointer.
3. **Separation of structure and position.** Green tree nodes store widths; red tree nodes compute absolute positions on demand.
4. **Incremental lexing is the first real win.** Re-tokenizing only the damaged region and splicing gives the parser unchanged tokens for free.
5. **Subtree reuse at grammar boundaries.** Check: kind match + leading token context + trailing token context + no damage overlap. All four must pass. The trailing context check is essential — a node's parse can depend on what follows it.
6. **Error recovery is part of the parser, not around it.** Record error → synchronize to known point → continue parsing.

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
- [ ] **#61** Explore token text as source spans (zero-copy lexing) — **needs decision**, see [docs/decisions-needed.md](docs/decisions-needed.md).
- [ ] `children_iter` (lazy, no-alloc) on `SyntaxNode` — **deferred, perf opportunity**. `SyntaxNode::children()` allocates a fresh `Array[SyntaxNode]` on every call (`seam/syntax_node.mbt:184`). The lambda example's `callers` projection (`examples/lambda/src/callers/callers.mbt`) — first identified consumer — hits this in its tree-walk catch-all branch on every CST edit. Only build once a concrete bench shows the allocation cost on the Memo recompute budget; same "require a concrete consumer" rule as #58/#59/#60.
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
- [ ] **Systematic edit-matrix parser tests** — add focused tests for deletion,
  insertion, replacement, token merge, token split, prefix/suffix/middle edits,
  and repeated edit sequences. Each case should assert incremental parse equals
  full reparse; only assert reuse counts where the fixture makes the expected
  reusable subtree unambiguous.
- [ ] **Reuse rejection diagnostics** — add a debug-only trace or inspection
  hook that explains why a candidate subtree was rejected: damage overlap,
  leading token mismatch, follow-token mismatch, token merge/split context, or
  reuse policy. This should help diagnose future parser-seam regressions without
  changing release behavior.
- [ ] **Reuse policy API cleanup** — if more reuse knobs appear, replace boolean
  flags such as `allow_left_adjacent_reuse` with a small `ReusePolicy` or
  `EditReusePolicy` value. Do not churn the API for this single flag alone.
- [x] ~~Redesign FlatProj for flat AST~~ — Resolved by PR #37: `from_proj_node` removed from hot path. Tree edits now produce text deltas directly via source map. Known limitation: `Drop` moves child text without surrounding operators/separators.

---

## What This Roadmap Does NOT Include

1. **Parser generation.** Hand-written recursive descent. Checkpoint-based reuse compensates for lower reuse granularity vs Lezer/tree-sitter.
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
