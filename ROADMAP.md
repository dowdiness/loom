# Roadmap: dowdiness/loom — Incremental Parser Framework

**Updated:** 2026-03-03
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

- [ ] Delete local `graphviz/` module and switch `loom/moon.mod.json` to the published `antisatori/graphviz` package version.
- [ ] Redesign `FlatProj` for flat AST (`Term::Module`). Current `from_proj_node` is lossy: def identity uses init child's `node_id` (lost on init change), and def start positions shift to init expressions. The editor hot path (`tree_edit_bridge.mbt:41`) uses `from_proj_node`. Long-term: Approach C — simplify FlatProj to work directly with Module's flat structure instead of decomposing/reconstructing a spine.

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
