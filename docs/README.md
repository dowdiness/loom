# Documentation Index

Navigation map for the incremental parser. Start here, go one level deeper for detail.

> **Maintenance rules:** (1) Update this file in the same commit as any `.md` add/move/remove.
> (2) When a plan is complete: add `**Status:** Complete`, add a decision-record note, then `git mv` to `archive/completed-phases/`.
> (3) Create or update an ADR for major plan closures; otherwise write `No ADR needed` with a short reason. See [ADR 2026-05-11](decisions/2026-05-11-major-plan-closure-decision-records.md).
> (4) Keep `README.md` ≤60 lines and `ROADMAP.md` ≤450 lines — extract details into sub-docs.

---

## Start Here

New to loom? Read in this order:

1. [../README.md](../README.md) — monorepo landing, what each module does
2. [../loom/README.md](../loom/README.md) — `dowdiness/loom` package: install, Quick Start, public API
3. [architecture/overview.md](architecture/overview.md) — layer diagram and architectural principles
4. [api/choosing-a-parser.md](api/choosing-a-parser.md) — `Parser` vs `ImperativeParser`
5. [../examples/lambda/](../examples/lambda/) — a complete grammar as reference

Going deeper:

- [../ROADMAP.md](../ROADMAP.md) — phase status and future work
- [../CHANGELOG.md](../CHANGELOG.md) — user-facing changes

## API Reference

Framework-level:

- [api/choosing-a-parser.md](api/choosing-a-parser.md) — when to reach for `ImperativeParser` directly instead of the unified `Parser[Ast]`
- [api/api-contract.md](api/api-contract.md) — `Parser[Ast]` API contract and stability guarantees
- [api/imperative-api-contract.md](api/imperative-api-contract.md) — `ImperativeParser` API contract
- [api/projection-guide.md](api/projection-guide.md) — CST → private IR → semantic model projection guide, including direct CST shape validation
- [api/cst-traversal-idioms.md](api/cst-traversal-idioms.md) — the three CST traversal idioms (`SyntaxNode` direct queries / `CstFold` / position-independent `CstElement` combinators) and when to use which
- [api/authoring-only-integration.md](api/authoring-only-integration.md) — keep Loom-backed editor diagnostics/projections behind an authoring facade without leaking into runtime packages
- [api/last-good-semantic-attachment.md](api/last-good-semantic-attachment.md) — authoring attachment pattern for immediate parser diagnostics plus last-good semantic document retention
- [../loom/src/pkg.generated.mbti](../loom/src/pkg.generated.mbti) — generated `.mbti` signatures for the `@loom` facade

Language-specific:

- [api/reference.md](api/reference.md) — **Lambda example** public API (parse / tokenize / pretty-print / `Term`)

Superseded:

- [archive/pipeline-api-contract.md](archive/pipeline-api-contract.md) — *(archived 2026-04-19)* pre-Stage 6 `ReactiveParser` pipeline API contract; superseded by the unified `Parser[Ast]` (see [ADR 2026-04-17](decisions/2026-04-17-unified-parser-proposal.md))

---

## Architecture & Design

Understanding how the layers fit together. Principles only — no specific types/fields/lines.

- [architecture/overview.md](architecture/overview.md) — layer diagram, architectural principles
- [architecture/pipeline.md](architecture/pipeline.md) — parse pipeline step by step
- [architecture/markdown-ir.md](architecture/markdown-ir.md) — MarkdownIR responsibilities, invariants, anti-CST-cloning rule, extension scope, and M0/M1 exit criteria
- [architecture/language.md](architecture/language.md) — grammar, syntax, Token/Term data types
- [architecture/seam-model.md](architecture/seam-model.md) — `CstNode`/`SyntaxNode` two-tree model
- [architecture/generic-parser.md](architecture/generic-parser.md) — `LanguageSpec`, `ParserContext` API
- [architecture/lexer-guidelines.md](architecture/lexer-guidelines.md) — preferred lexer cursor, `StringView`, and Unicode-safe offset patterns
- [architecture/polymorphism-patterns.md](architecture/polymorphism-patterns.md) — choosing between generic, trait object, struct-of-closures, defunctionalization
- [architecture/block-reparse.md](architecture/block-reparse.md) — Block Reparse Architecture
- [architecture/egraph-vs-egglog.md](architecture/egraph-vs-egglog.md) — EGraph vs Egglog: when to use which, how Canopy uses both

### Architecture Decisions (ADRs)

Short records of the *why* behind significant design choices. Most recent first.

- [decisions/2026-06-17-markdown-ir-recovery-adapter-contract.md](decisions/2026-06-17-markdown-ir-recovery-adapter-contract.md) — **Accepted** MarkdownIR target adapters must handle `Recovered` / `Raw` explicitly; future HTML adapters must choose escaped/sanitized/comment/error presentation rather than silent passthrough
- [decisions/2026-06-17-diagnostic-range-filter-boundary.md](decisions/2026-06-17-diagnostic-range-filter-boundary.md) — **Accepted** keep downstream diagnostic attachment range/filter semantics language-local until multiple consumers prove a shared Loom-core helper
- [decisions/2026-06-16-markdown-ir-performance-policy.md](decisions/2026-06-16-markdown-ir-performance-policy.md) — **Accepted** MarkdownIR performance, memoization, and eager/lazy policy; MarkdownIR is built lazily on demand and is not memoized by position-independent `CstFold` because it stores absolute source origins
- [decisions/2026-06-15-markdown-ir-target-contract.md](decisions/2026-06-15-markdown-ir-target-contract.md) — **Accepted** MarkdownIR target contract: semantic transform layer between CST and `Block`/mdast/HTML/rewrite/formatter adapters, with anti-CST-cloning rule
- [decisions/2026-06-14-block-reparse-context-deferral.md](decisions/2026-06-14-block-reparse-context-deferral.md) — **Accepted** defer `BlockReparseContext` API churn until Markdown or another concrete grammar needs more than `SyntaxNode`; conservative successor shape recorded for #315
- [decisions/2026-06-13-lambda-moonbit-style-syntax.md](decisions/2026-06-13-lambda-moonbit-style-syntax.md) — **Accepted** lambda example uses MoonBit-style `let`/`fn`/arrow syntax and rejects legacy `λ`/`\` abstractions
- [decisions/2026-06-13-parsercontext-method-only-boundary.md](decisions/2026-06-13-parsercontext-method-only-boundary.md) — **Accepted** `ParserContext` grammar-author API is method-only; raw parser-state fields are private implementation detail
- [decisions/2026-06-11-separated-list-boundary-model.md](decisions/2026-06-11-separated-list-boundary-model.md) — **Accepted** N-separators→N+1-slots boundary model shared by the seam projection grouping helper and the `ParserContext::separated_list` combinator; empty slots stay represented
- [decisions/2026-06-08-json-role-span-export.md](decisions/2026-06-08-json-role-span-export.md) — **Accepted** JSON-local editor-neutral role-span export shape for CodeMirror-facing consumers without a frontend dependency
- [decisions/2026-06-07-parser-context-grammar-author-helpers.md](decisions/2026-06-07-parser-context-grammar-author-helpers.md) — **Accepted** small `ParserContext` grammar-author helpers; broader field-boundary decision resolved by [ADR 2026-06-13](decisions/2026-06-13-parsercontext-method-only-boundary.md)
- [decisions/2026-06-07-reactive-syntax-only-parser.md](decisions/2026-06-07-reactive-syntax-only-parser.md) — **Accepted** syntax-only reactive parser path for CST/diagnostics consumers whose AST is unavailable or not naturally `Eq`
- [decisions/2026-05-30-seam-source-span-api-hardening.md](decisions/2026-05-30-seam-source-span-api-hardening.md) — **Accepted** unstable names for backing-source inspection and parser-owned source-span reuse hooks before seam stabilization
- [decisions/2026-05-29-stable-semantic-projection-identity.md](decisions/2026-05-29-stable-semantic-projection-identity.md) — **Accepted** leaf-level helper preserves semantic projection IDs across edit windows and malformed-input recovery
- [decisions/2026-05-28-authoring-last-good-semantic-projection.md](decisions/2026-05-28-authoring-last-good-semantic-projection.md) — **Accepted** stateful authoring attachments keep parser diagnostics immediate while retaining last-good semantic projections across parser/projection failures
- [decisions/2026-05-28-authoring-only-integration-boundary.md](decisions/2026-05-28-authoring-only-integration-boundary.md) — **Accepted** optional authoring-only Loom integration boundary for downstream runtime isolation
- [decisions/2026-05-25-direct-cst-projection-queries.md](decisions/2026-05-25-direct-cst-projection-queries.md) — **Accepted** projection-friendly direct CST query helpers for safer semantic validation
- [decisions/2026-05-22-callers-visible-from-memo.md](decisions/2026-05-22-callers-visible-from-memo.md) — **Accepted** callers `visible_from` as a pure Derived projection, with Datalog deferred until relation retraction exists
- [decisions/2026-05-20-lambda-rename-consumer.md](decisions/2026-05-20-lambda-rename-consumer.md) — **Accepted** lambda rename consumer as a one-shot package over callers facts, with structured diagnostics for conflict reporting
- [decisions/2026-05-17-canonical-companion-trait.md](decisions/2026-05-17-canonical-companion-trait.md) — **Accepted** `Canonical` companion trait as a framework-level capability with opt-in `default_placeholder_via_canonical` free function (no supertrait coupling on `Renderable`)
- [decisions/2026-05-14-structured-parser-diagnostics-boundary.md](decisions/2026-05-14-structured-parser-diagnostics-boundary.md) — **Accepted** publish parser snapshots and structured diagnostics at public parser boundaries
- [decisions/2026-05-11-major-plan-closure-decision-records.md](decisions/2026-05-11-major-plan-closure-decision-records.md) — **Accepted** create/update ADRs for major plan closures; require an explicit decision-record note when archiving plans
- [decisions/2026-05-11-moji-unicode-boundaries.md](decisions/2026-05-11-moji-unicode-boundaries.md) — **Accepted** use `moji` at grapheme/word boundary layers while keeping Loom core spans as UTF-16 code-unit offsets
- [decisions/2026-05-11-derived-source-locations.md](decisions/2026-05-11-derived-source-locations.md) — **Accepted** keep UTF-16 offsets canonical and derive line/column positions with `LineIndex` at presentation boundaries
- [decisions/2026-04-17-unified-parser-proposal.md](decisions/2026-04-17-unified-parser-proposal.md) — **Accepted** unified `Parser[Ast]` with multiple update paths; supersedes 2026-03-02 two-parser design (see [plan](archive/completed-phases/2026-04-17-unified-parser.md))
- [decisions/2026-03-15-reintroduce-token-stage-memo.md](decisions/2026-03-15-reintroduce-token-stage-memo.md) — reintroduce TokenStage memo with position-independent equality (reverses 2026-02-27 removal)
- [decisions/2026-03-14-physical-equal-interner.md](decisions/2026-03-14-physical-equal-interner.md) — `physical_equal` in `CstNode::Eq`/`CstToken::Eq` to fix O(n²) interner equality on nested trees; updated for #61 source-span tokens
- [decisions/2026-03-09-reactive-parser-token-eq-bound.md](decisions/2026-03-09-reactive-parser-token-eq-bound.md)
- [decisions/2026-03-02-two-parser-design.md](decisions/2026-03-02-two-parser-design.md) *(superseded by 2026-04-17 ADR)*
- [decisions/2026-02-28-edit-lengths-not-endpoints.md](decisions/2026-02-28-edit-lengths-not-endpoints.md)
- [decisions/2026-02-27-remove-tokenStage-memo.md](decisions/2026-02-27-remove-tokenStage-memo.md) *(superseded by 2026-03-15 ADR)*

---

## Correctness

- [correctness/CORRECTNESS.md](correctness/CORRECTNESS.md) — correctness goals and verification
- [correctness/STRUCTURAL_VALIDATION.md](correctness/STRUCTURAL_VALIDATION.md) — structural validation details
- [correctness/EDGE_CASE_TESTS.md](correctness/EDGE_CASE_TESTS.md) — edge-case test catalog

## Analysis

Point-in-time diagnoses. Dated snapshots — verify against current code before acting.

- [analysis/2026-05-08-architecture-status-update.md](analysis/2026-05-08-architecture-status-update.md) — delta on the 2026-04-19 diagnosis: what shipped, revised Stage C (egraph stays as peer library — supersedes prior `experiments/` proposal)
- [analysis/2026-04-19-architecture-diagnosis.md](analysis/2026-04-19-architecture-diagnosis.md) — change pressures, sibling-module boundary issues, staged migration proposal (Stages A–D)

## Performance

- [performance/PERFORMANCE_ANALYSIS.md](performance/PERFORMANCE_ANALYSIS.md) — benchmarks and analysis
- [performance/benchmark_history.md](performance/benchmark_history.md) — historical benchmark log
- [performance/bench-baseline.tsv](performance/bench-baseline.tsv) — machine-readable baseline for `bench-check.sh`
- [performance/incremental-overhead.md](performance/incremental-overhead.md) — incremental parser overhead analysis and straightforward waste elimination opportunities
- [performance/grammar-design-for-incremental.md](performance/grammar-design-for-incremental.md) — grammar shapes that help/hurt incremental parsing: flat > left-recursive > balanced > right-recursive
- [performance/2026-03-30-cst-traversal-tiers.md](performance/2026-03-30-cst-traversal-tiers.md) — feasibility report for the three traversal tiers (closures, Folder/TransformFolder, MutVisitor); drove the seam port and motivated removing the original `cst-transform/` sandbox
- [performance/2026-03-31-map-specialization.md](performance/2026-03-31-map-specialization.md) — closure specialization vs generic map in wasm-gc (narrower types ≠ faster)
- [../BENCHMARKS.md](../BENCHMARKS.md) — benchmark results and raw data (root-level)
- [../bench-check.sh](../bench-check.sh) — regression guard (`--update` to refresh baseline)

---

## Contributor

- [development/managing-modules.md](development/managing-modules.md) — multi-module workflow, per-module development, publishing to mooncakes.io
- [development/agent-docs-protocol.md](development/agent-docs-protocol.md) — coding-agent workflow for completing plans, deciding when ADRs are required, and keeping the docs index consistent
- [decisions-needed.md](decisions-needed.md) — triage items flagged `needs-human-review`

### Examples

Each example demonstrates a different `@loom.Grammar` feature axis:

- [../examples/lambda/README.md](../examples/lambda/README.md) — typed `SyntaxNode` views, classical recursive descent
- [../examples/json/README.md](../examples/json/README.md) — step-based total lexing + `block_reparse_spec`
- [../examples/json-settings/README.md](../examples/json-settings/README.md) — checked last-good semantic projection attachment (pure derived + imperative `settle`)
- [../examples/markdown/README.md](../examples/markdown/README.md) — mode-aware lexing via `ModeLexer`
- [../examples/moonbit/README.md](../examples/moonbit/README.md) — official MoonBit lexer adapter + coarse Loom CST skeleton
- [../examples/graph-dsl/README.md](../examples/graph-dsl/README.md) — source-map/token-role graph authoring example with graph-operation lowering
- [../examples/lambda/ROADMAP.md](../examples/lambda/ROADMAP.md) — lambda grammar expansion plans, CRDT exploration

### Sibling Utility Modules

- [../text-change/README.md](../text-change/README.md) — pure contiguous text-change utilities (migrated from canopy 2026-05, #147)
- [../moji/README.md](../moji/README.md) — UAX #29 grapheme cluster + word boundary segmentation, UTF-16 indexed (migrated from canopy 2026-05, #147)

### Active Plans

_No active plans._

_Previously active: ParserContext grammar-author boundary shipped 2026-06-11 as PR #290 (issue #251; see [ADR](decisions/2026-06-13-parsercontext-method-only-boundary.md) and [archived design](archive/completed-phases/2026-06-12-parsercontext-field-boundary-design.md))._
_Previously active: separated-list parsing & grouping shipped 2026-06-11 as PR #285/#286 (issue #279; see [ADR](decisions/2026-06-11-separated-list-boundary-model.md), [archived design](archive/completed-phases/2026-06-11-separated-list-grouping.md), and [archived plan](archive/completed-phases/2026-06-11-separated-list-grouping-plan.md))._
_Previously active: json-settings last-good attachment example shipped 2026-06-01 as [`examples/json-settings/`](../examples/json-settings/) (issue #202; no ADR — implements accepted last-good + stable-identity decisions). See [archived plan](archive/completed-phases/2026-06-01-json-settings-last-good-attachment-plan.md)._
_Completed: callers `visible_from` shipped 2026-05-19 in PR #129 (see [ADR](decisions/2026-05-22-callers-visible-from-memo.md), [archived spec](archive/completed-phases/2026-05-19-callers-visible-from.md), and [archived plan](archive/completed-phases/2026-05-19-callers-visible-from-plan.md))._
_Shipped: Canonical companion trait shipped 2026-05-17 (see [ADR](decisions/2026-05-17-canonical-companion-trait.md) and [archived plan](archive/completed-phases/2026-05-17-canonical-trait.md))._

---

## Historical & Archive

> **Do not read files in this section unless you need historical context.** These documents describe past design iterations, completed work, and point-in-time analyses. The code is the source of truth; where archive material and current docs disagree, trust the code and the current docs.

- [archive/completed-phases/](archive/completed-phases/) — completed phase plans and implementation notes (SyntaxNode-first layer, NodeInterner, docs hierarchy, dead-code audit, loom extraction, parser API simplification, typed SyntaxNode views, CRDT exploration, loom/core simplification, seam trait cleanup, AstNode removal, multi-expression files, step-lexing redesign, flat grammar unification, error recovery, ambiguity resilience, memoized CST fold, grammar extensions, block reparse, JSON parser, Egglog typechecker, EGraph evaluator, StringView threading, unified `Parser[Ast]`, line-index source locations, structured parser diagnostics, post-112 follow-ups, lambda rename consumer, callers `visible_from`, and more)
- [archive/](archive/) — research notes and retired design snapshots:
  - [archive/lezer.md](archive/lezer.md), [archive/LEZER_IMPLEMENTATION.md](archive/LEZER_IMPLEMENTATION.md), [archive/LEZER_FRAGMENT_REUSE.md](archive/LEZER_FRAGMENT_REUSE.md) — Lezer parser framework investigation
  - [archive/green-tree-extraction.md](archive/green-tree-extraction.md) — Green Tree / Red Tree research
  - [archive/pipeline-api-contract.md](archive/pipeline-api-contract.md) — pre-Stage 6 `ReactiveParser` pipeline API contract (superseded 2026-04-19)
  - [archive/2026-03-06-code-analysis-report.md](archive/2026-03-06-code-analysis-report.md) — *(stale 2026-04-17)* comprehensive code analysis — pre-unification architecture
  - [archive/2026-03-06-defect-analysis-report.md](archive/2026-03-06-defect-analysis-report.md) — *(stale 2026-04-17)* defect analysis — pre-unification architecture
  - [archive/TODO.md](archive/TODO.md), [archive/TODO_ARCHIVE.md](archive/TODO_ARCHIVE.md), [archive/COMPLETION_SUMMARY.md](archive/COMPLETION_SUMMARY.md), [archive/IMPLEMENTATION_COMPLETE.md](archive/IMPLEMENTATION_COMPLETE.md), [archive/IMPLEMENTATION_SUMMARY.md](archive/IMPLEMENTATION_SUMMARY.md) — historical status docs
