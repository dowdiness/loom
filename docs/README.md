# Documentation Index

Navigation map for the incremental parser. Start here, go one level deeper for detail.

> **Maintenance rules:** (1) Update this file in the same commit as any `.md` add/move/remove.
> (2) When a plan is complete: add `**Status:** Complete` to the file, then `git mv` to `archive/completed-phases/`.
> (3) Keep `README.md` ≤60 lines and `ROADMAP.md` ≤450 lines — extract details into sub-docs.

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

## API Reference

Framework-level:

- [api/choosing-a-parser.md](api/choosing-a-parser.md) — when to reach for `ImperativeParser` directly instead of the unified `Parser[Ast]`
- [api/api-contract.md](api/api-contract.md) — `Parser[Ast]` API contract and stability guarantees
- [api/imperative-api-contract.md](api/imperative-api-contract.md) — `ImperativeParser` API contract
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
- [architecture/language.md](architecture/language.md) — grammar, syntax, Token/Term data types
- [architecture/seam-model.md](architecture/seam-model.md) — `CstNode`/`SyntaxNode` two-tree model
- [architecture/generic-parser.md](architecture/generic-parser.md) — `LanguageSpec`, `ParserContext` API
- [architecture/polymorphism-patterns.md](architecture/polymorphism-patterns.md) — choosing between generic, trait object, struct-of-closures, defunctionalization
- [architecture/block-reparse.md](architecture/block-reparse.md) — Block Reparse Architecture
- [architecture/egraph-vs-egglog.md](architecture/egraph-vs-egglog.md) — EGraph vs Egglog: when to use which, how Canopy uses both

### Architecture Decisions (ADRs)

Short records of the *why* behind significant design choices. Most recent first.

- [decisions/2026-04-17-unified-parser-proposal.md](decisions/2026-04-17-unified-parser-proposal.md) — **Accepted** unified `Parser[Ast]` with multiple update paths; supersedes 2026-03-02 two-parser design (see [plan](archive/completed-phases/2026-04-17-unified-parser.md))
- [decisions/2026-03-15-reintroduce-token-stage-memo.md](decisions/2026-03-15-reintroduce-token-stage-memo.md) — reintroduce TokenStage memo with position-independent equality (reverses 2026-02-27 removal)
- [decisions/2026-03-14-physical-equal-interner.md](decisions/2026-03-14-physical-equal-interner.md) — `physical_equal` in `CstNode::Eq`/`CstToken::Eq` to fix O(n²) interner equality on nested trees
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

- [analysis/2026-04-19-architecture-diagnosis.md](analysis/2026-04-19-architecture-diagnosis.md) — change pressures, sibling-module boundary issues, staged migration proposal (Stages A–D)

## Performance

- [performance/PERFORMANCE_ANALYSIS.md](performance/PERFORMANCE_ANALYSIS.md) — benchmarks and analysis
- [performance/benchmark_history.md](performance/benchmark_history.md) — historical benchmark log
- [performance/bench-baseline.tsv](performance/bench-baseline.tsv) — machine-readable baseline for `bench-check.sh`
- [performance/incremental-overhead.md](performance/incremental-overhead.md) — incremental parser overhead analysis and low-hanging-fruit waste elimination opportunities
- [performance/grammar-design-for-incremental.md](performance/grammar-design-for-incremental.md) — grammar shapes that help/hurt incremental parsing: flat > left-recursive > balanced > right-recursive
- [performance/2026-03-31-map-specialization.md](performance/2026-03-31-map-specialization.md) — closure specialization vs generic map in wasm-gc (narrower types ≠ faster)
- [../BENCHMARKS.md](../BENCHMARKS.md) — benchmark results and raw data (root-level)
- [../bench-check.sh](../bench-check.sh) — regression guard (`--update` to refresh baseline)

---

## Contributor

- [development/managing-modules.md](development/managing-modules.md) — multi-module workflow, per-module development, publishing to mooncakes.io
- [decisions-needed.md](decisions-needed.md) — triage items flagged `needs-human-review`

### Examples

Each example demonstrates a different `@loom.Grammar` feature axis:

- [../examples/lambda/README.md](../examples/lambda/README.md) — typed `SyntaxNode` views, classical recursive descent
- [../examples/json/README.md](../examples/json/README.md) — step-based `prefix_lexer` + `block_reparse_spec`
- [../examples/markdown/README.md](../examples/markdown/README.md) — mode-aware lexing via `ModeLexer`
- [../examples/lambda/ROADMAP.md](../examples/lambda/ROADMAP.md) — lambda grammar expansion plans, CRDT exploration

### Active Plans

_No active plans._ When adding one, create `plans/YYYY-MM-DD-<slug>.md` and link it here.

---

## Historical & Archive

> **Do not read files in this section unless you need historical context.** These documents describe past design iterations, completed work, and point-in-time analyses. The code is the source of truth; where archive material and current docs disagree, trust the code and the current docs.

- [archive/completed-phases/](archive/completed-phases/) — 88 completed phase plans (SyntaxNode-first layer, NodeInterner, docs hierarchy, dead-code audit, loom extraction, parser API simplification, typed SyntaxNode views, CRDT exploration, loom/core simplification, seam trait cleanup, AstNode removal, multi-expression files, step-lexing redesign, flat grammar unification, error recovery, ambiguity resilience, memoized CST fold, grammar extensions, block reparse, JSON parser, Egglog typechecker, EGraph evaluator, StringView threading, unified `Parser[Ast]`, and more)
- [archive/](archive/) — research notes and retired design snapshots:
  - [archive/lezer.md](archive/lezer.md), [archive/LEZER_IMPLEMENTATION.md](archive/LEZER_IMPLEMENTATION.md), [archive/LEZER_FRAGMENT_REUSE.md](archive/LEZER_FRAGMENT_REUSE.md) — Lezer parser framework investigation
  - [archive/green-tree-extraction.md](archive/green-tree-extraction.md) — Green Tree / Red Tree research
  - [archive/pipeline-api-contract.md](archive/pipeline-api-contract.md) — pre-Stage 6 `ReactiveParser` pipeline API contract (superseded 2026-04-19)
  - [archive/2026-03-06-code-analysis-report.md](archive/2026-03-06-code-analysis-report.md) — *(stale 2026-04-17)* comprehensive code analysis — pre-unification architecture
  - [archive/2026-03-06-defect-analysis-report.md](archive/2026-03-06-defect-analysis-report.md) — *(stale 2026-04-17)* defect analysis — pre-unification architecture
  - [archive/TODO.md](archive/TODO.md), [archive/TODO_ARCHIVE.md](archive/TODO_ARCHIVE.md), [archive/COMPLETION_SUMMARY.md](archive/COMPLETION_SUMMARY.md), [archive/IMPLEMENTATION_COMPLETE.md](archive/IMPLEMENTATION_COMPLETE.md), [archive/IMPLEMENTATION_SUMMARY.md](archive/IMPLEMENTATION_SUMMARY.md) — historical status docs
