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
- [architecture/block-reparse.md](architecture/block-reparse.md) — Block Reparse Architecture

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

## Analysis

- [analysis/code-analysis-report.md](analysis/code-analysis-report.md) — comprehensive code analysis: module structure, dependency hierarchy, execution paths
- [analysis/defect-analysis-report.md](analysis/defect-analysis-report.md) — defect analysis: common bug patterns, failure modes, risk areas

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
- [decisions/2026-03-15-reintroduce-token-stage-memo.md](decisions/2026-03-15-reintroduce-token-stage-memo.md) — reintroduce TokenStage memo with position-independent equality (reverses 2026-02-27 removal)

## Examples

- [../examples/lambda/ROADMAP.md](../examples/lambda/ROADMAP.md) — lambda calculus grammar expansion plans, CRDT exploration

## Active Plans

- [plans/2026-03-21-grammar-extension-design.md](plans/2026-03-21-grammar-extension-design.md) — Lambda Grammar Extension Design
- [plans/2026-03-21-grammar-extension-impl.md](plans/2026-03-21-grammar-extension-impl.md) — Lambda Grammar Extension Implementation Plan
- [plans/2026-03-22-block-reparse-impl-design.md](plans/2026-03-22-block-reparse-impl-design.md) — Block Reparse Implementation Design
- [plans/2026-03-22-block-reparse-impl.md](plans/2026-03-22-block-reparse-impl.md) — Block Reparse Implementation Plan
- [plans/2026-03-22-json-parser-design.md](plans/2026-03-22-json-parser-design.md) — JSON Parser Design
- [plans/2026-03-22-json-parser-impl.md](plans/2026-03-22-json-parser-impl.md) — JSON Parser Implementation Plan
- [plans/2026-03-28-egglog-egraph-lambda-design.md](plans/2026-03-28-egglog-egraph-lambda-design.md) — Egglog Type Checker + Egraph Evaluator for Lambda Calculus

## Development

- [development/managing-modules.md](development/managing-modules.md) — monorepo workflow, per-module development, publishing to mooncakes.io

## Archive (Historical / Completed)

- [archive/completed-phases/](archive/completed-phases/) — all completed phase plans (Phases 0–7, SyntaxNode-first layer, NodeInterner, docs reorganization, dead-code audit, loom extraction, rabbita monorepo migration, parser API simplification, roadmap separation, typed SyntaxNode views, CRDT exploration, loom/core simplification, seam trait cleanup, AstNode removal, Term::Error variant, multi-expression files, step-lexing redesign, seam Phase 2, flat grammar unification, flat AST Term::Module, SyntaxNode view helpers, projectional edit text delta)
- [archive/completed-phases/2026-03-04-multi-expression-files-design.md](archive/completed-phases/2026-03-04-multi-expression-files-design.md) — multi-expression files design (LetDef*, Unit term, parse_source_file)
- [archive/completed-phases/2026-03-04-multi-expression-files.md](archive/completed-phases/2026-03-04-multi-expression-files.md) — multi-expression files implementation plan (6 tasks, complete)
- [archive/completed-phases/2026-03-05-loom-error-recovery.md](archive/completed-phases/2026-03-05-loom-error-recovery.md) — loom error recovery combinators (expect, skip_until, skip_until_balanced, node_with_recovery, expect_and_recover)
- [archive/completed-phases/2026-03-05-lambda-error-recovery.md](archive/completed-phases/2026-03-05-lambda-error-recovery.md) — lambda parser error recovery using loom combinators
- [archive/completed-phases/2026-03-05-loom-incomplete-nodes.md](archive/completed-phases/2026-03-05-loom-incomplete-nodes.md) — incomplete_kind: distinguish EOF-incomplete from syntax errors
- [archive/completed-phases/2026-03-06-loom-ambiguity-resilience-plan.md](archive/completed-phases/2026-03-06-loom-ambiguity-resilience-plan.md) — ambiguity resilience: eliminate crashes, data loss, add speculative parsing
- [archive/completed-phases/2026-03-15-flat-grammar-unification.md](archive/completed-phases/2026-03-15-flat-grammar-unification.md) — flat grammar unification design
- [archive/completed-phases/2026-03-15-flat-grammar-unification-plan.md](archive/completed-phases/2026-03-15-flat-grammar-unification-plan.md) — flat grammar unification implementation plan
- [archive/completed-phases/2026-03-14-incremental-overhead.md](archive/completed-phases/2026-03-14-incremental-overhead.md) — incremental overhead waste elimination (3 fixes, benchmarked)
- [archive/completed-phases/2026-03-06-position-independent-tokens.md](archive/completed-phases/2026-03-06-position-independent-tokens.md) — position-independent tokens + trivia-insensitive TokenStage early cutoff (all phases)
- [archive/completed-phases/2026-03-15-try-reuse-fast-path.md](archive/completed-phases/2026-03-15-try-reuse-fast-path.md) — emit_reused fast path: has_any_error flag, incremental overhead profiling, architectural analysis
- [archive/completed-phases/2026-03-09-semantic-error-variants-design.md](archive/completed-phases/2026-03-09-semantic-error-variants-design.md) — `Term::Unbound` semantic error variant: design
- [archive/completed-phases/2026-03-09-semantic-error-variants-impl.md](archive/completed-phases/2026-03-09-semantic-error-variants-impl.md) — `Term::Unbound` semantic error variant: implementation (7 tasks)
- [archive/completed-phases/2026-03-08-memoized-cst-fold.md](archive/completed-phases/2026-03-08-memoized-cst-fold.md) — memoized CST fold: design
- [archive/completed-phases/2026-03-08-memoized-cst-fold-impl.md](archive/completed-phases/2026-03-08-memoized-cst-fold-impl.md) — memoized CST fold: implementation (15 tasks)
- [archive/completed-phases/2026-03-28-egglog-lambda-typechecker-impl.md](archive/completed-phases/2026-03-28-egglog-lambda-typechecker-impl.md) — Egglog Lambda Type Checker (egglog relational DB, bidirectional typing, 13 rules)
- [archive/completed-phases/2026-03-28-egraph-lambda-evaluator-impl.md](archive/completed-phases/2026-03-28-egraph-lambda-evaluator-impl.md) — Egraph Lambda Evaluator (equality saturation, beta reduction, capture-avoiding substitution, constant folding)
- [archive/](archive/) — research notes (Lezer, fragment reuse) and historical status docs
