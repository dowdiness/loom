# Documentation Index

Navigation map for the incremental parser. Start here, go one level deeper for detail.

> **Maintenance rules:** (1) Update this file in the same commit as any `.md` add/move/remove.
> (2) When a plan is complete: add `**Status:** Complete` to the file, then `git mv` to `archive/completed-phases/`.
> (3) Keep `README.md` ≤60 lines and `ROADMAP.md` ≤450 lines — extract details into sub-docs.

## Architecture

Understanding how the layers fit together:

- [architecture/overview.md](architecture/overview.md) — layer diagram, architectural principles
- [architecture/pipeline.md](architecture/pipeline.md) — parse pipeline step by step
- [architecture/language.md](architecture/language.md) — grammar, syntax, Token/Term data types
- [architecture/seam-model.md](architecture/seam-model.md) — `CstNode`/`SyntaxNode` two-tree model
- [architecture/generic-parser.md](architecture/generic-parser.md) — `LanguageSpec`, `ParserContext` API
- [architecture/polymorphism-patterns.md](architecture/polymorphism-patterns.md) — choosing between generic, trait object, struct-of-closures, defunctionalization

## API Reference

- [api/reference.md](api/reference.md) — all public functions, error types, usage examples
- [api/choosing-a-parser.md](api/choosing-a-parser.md) — when to use ImperativeParser vs ReactiveParser
- [api/api-contract.md](api/api-contract.md) — API contract and stability guarantees
- [api/imperative-api-contract.md](api/imperative-api-contract.md) — ImperativeParser API contract
- [api/pipeline-api-contract.md](api/pipeline-api-contract.md) — ReactiveParser pipeline API contract

## Correctness

- [correctness/CORRECTNESS.md](correctness/CORRECTNESS.md) — correctness goals and verification
- [correctness/STRUCTURAL_VALIDATION.md](correctness/STRUCTURAL_VALIDATION.md) — structural validation details
- [correctness/EDGE_CASE_TESTS.md](correctness/EDGE_CASE_TESTS.md) — edge-case test catalog

## Performance

- [performance/PERFORMANCE_ANALYSIS.md](performance/PERFORMANCE_ANALYSIS.md) — benchmarks and analysis
- [performance/benchmark_history.md](performance/benchmark_history.md) — historical benchmark log
- [performance/bench-baseline.tsv](performance/bench-baseline.tsv) — machine-readable baseline for `bench-check.sh`
- [performance/incremental-overhead.md](performance/incremental-overhead.md) — incremental parser overhead analysis and low-hanging-fruit waste elimination opportunities
- [performance/grammar-design-for-incremental.md](performance/grammar-design-for-incremental.md) — grammar shapes that help/hurt incremental parsing: flat > left-recursive > balanced > right-recursive
- [../BENCHMARKS.md](../BENCHMARKS.md) — benchmark results and raw data (root-level)
- [../bench-check.sh](../bench-check.sh) — regression guard (`--update` to refresh baseline)

## Architecture Decisions (ADRs)

- [decisions/2026-02-27-remove-tokenStage-memo.md](decisions/2026-02-27-remove-tokenStage-memo.md)
- [decisions/2026-02-28-edit-lengths-not-endpoints.md](decisions/2026-02-28-edit-lengths-not-endpoints.md)
- [decisions/2026-03-02-two-parser-design.md](decisions/2026-03-02-two-parser-design.md)
- [decisions/2026-03-09-reactive-parser-token-eq-bound.md](decisions/2026-03-09-reactive-parser-token-eq-bound.md)
- [decisions/2026-03-14-physical-equal-interner.md](decisions/2026-03-14-physical-equal-interner.md) — `physical_equal` in `CstNode::Eq`/`CstToken::Eq` to fix O(n²) interner equality on nested trees

## Examples

- [../examples/lambda/ROADMAP.md](../examples/lambda/ROADMAP.md) — lambda calculus grammar expansion plans, CRDT exploration

## Active Plans

- [plans/2026-03-06-position-independent-tokens.md](plans/2026-03-06-position-independent-tokens.md) — position-independent tokens: `TokenInfo(token, len)` + parallel `starts` array, reintroduce `TokenStage` memo
- [plans/2026-03-08-memoized-cst-fold.md](plans/2026-03-08-memoized-cst-fold.md) — memoized CST fold: design document
- [plans/2026-03-08-memoized-cst-fold-impl.md](plans/2026-03-08-memoized-cst-fold-impl.md) — memoized CST fold: implementation plan (14 tasks)
- [plans/2026-03-09-semantic-error-variants-design.md](plans/2026-03-09-semantic-error-variants-design.md) — `Term::Unbound` semantic error variant: design document
- [plans/2026-03-09-semantic-error-variants-impl.md](plans/2026-03-09-semantic-error-variants-impl.md) — `Term::Unbound` semantic error variant: implementation plan (7 tasks)
- [plans/2026-03-14-incremental-overhead.md](plans/2026-03-14-incremental-overhead.md) — incremental parser waste elimination: 3 fixes (defensive copy, lazy old-token lookup, ReuseNode event)
- [plans/2026-03-15-flat-grammar-unification.md](plans/2026-03-15-flat-grammar-unification.md) — flat grammar unification: remove lambda_grammar, unify on LetDef* with layout-aware lexing
- [plans/2026-03-15-flat-grammar-unification-plan.md](plans/2026-03-15-flat-grammar-unification-plan.md) — flat grammar unification: implementation plan (8 tasks)

## Development

- [development/managing-modules.md](development/managing-modules.md) — monorepo workflow, per-module development, publishing to mooncakes.io

## Archive (Historical / Completed)

- [archive/completed-phases/](archive/completed-phases/) — all completed phase plans (Phases 0–7, SyntaxNode-first layer, NodeInterner, docs reorganization, dead-code audit, loom extraction, rabbita monorepo migration, parser API simplification, roadmap separation, typed SyntaxNode views, CRDT exploration, loom/core simplification, seam trait cleanup, AstNode removal, Term::Error variant, multi-expression files, step-lexing redesign, seam Phase 2)
- [archive/completed-phases/2026-03-04-multi-expression-files-design.md](archive/completed-phases/2026-03-04-multi-expression-files-design.md) — multi-expression files design (LetDef*, Unit term, parse_source_file)
- [archive/completed-phases/2026-03-04-multi-expression-files.md](archive/completed-phases/2026-03-04-multi-expression-files.md) — multi-expression files implementation plan (6 tasks, complete)
- [archive/completed-phases/2026-03-05-loom-error-recovery.md](archive/completed-phases/2026-03-05-loom-error-recovery.md) — loom error recovery combinators (expect, skip_until, skip_until_balanced, node_with_recovery, expect_and_recover)
- [archive/completed-phases/2026-03-05-lambda-error-recovery.md](archive/completed-phases/2026-03-05-lambda-error-recovery.md) — lambda parser error recovery using loom combinators
- [archive/completed-phases/2026-03-05-loom-incomplete-nodes.md](archive/completed-phases/2026-03-05-loom-incomplete-nodes.md) — incomplete_kind: distinguish EOF-incomplete from syntax errors
- [archive/completed-phases/2026-03-06-loom-ambiguity-resilience-plan.md](archive/completed-phases/2026-03-06-loom-ambiguity-resilience-plan.md) — ambiguity resilience: eliminate crashes, data loss, add speculative parsing
- [archive/completed-phases/2026-03-15-flat-grammar-unification.md](archive/completed-phases/2026-03-15-flat-grammar-unification.md) — flat grammar unification design
- [archive/completed-phases/2026-03-15-flat-grammar-unification-plan.md](archive/completed-phases/2026-03-15-flat-grammar-unification-plan.md) — flat grammar unification implementation plan
- [archive/completed-phases/2026-03-15-try-reuse-fast-path.md](archive/completed-phases/2026-03-15-try-reuse-fast-path.md) — emit_reused fast path: has_any_error flag, incremental overhead profiling, architectural analysis
- [archive/](archive/) — research notes (Lezer, fragment reuse) and historical status docs
