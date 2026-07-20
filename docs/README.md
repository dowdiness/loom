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
- [../loom/pkg.generated.mbti](../loom/pkg.generated.mbti) — generated `.mbti` signatures for the `@loom` facade

Language-specific:

- [api/reference.md](api/reference.md) — **Lambda example** public API (parse / tokenize / pretty-print / `Term`)

Superseded:

- [archive/pipeline-api-contract.md](archive/pipeline-api-contract.md) — *(archived 2026-04-19)* pre-Stage 6 `ReactiveParser` pipeline API contract; superseded by the unified `Parser[Ast]` (see [ADR 2026-04-17](decisions/2026-04-17-unified-parser-proposal.md))

---

## Architecture & Design

Understanding how the layers fit together. Principles only — no specific types/fields/lines.

- [architecture/overview.md](architecture/overview.md) — layer diagram, architectural principles
- [architecture/pipeline.md](architecture/pipeline.md) — parse pipeline step by step
- [architecture/markdown-ir.md](architecture/markdown-ir.md) — MarkdownIR responsibilities, identity boundary, invariants, anti-CST-cloning rule, extension scope, and M0/M1 exit criteria
- [architecture/language.md](architecture/language.md) — grammar, syntax, Token/Term data types
- [architecture/seam-model.md](architecture/seam-model.md) — `CstNode`/`SyntaxNode` two-tree model
- [architecture/generic-parser.md](architecture/generic-parser.md) — `LanguageSpec`, `ParserContext` API
- [architecture/goal-token-source.md](architecture/goal-token-source.md) — parser-directed goal tokenization for lexical-goal-ambiguous languages (JS Div/RegExp); GoalTokenSource overlay on TokenBuffer, invalidation model, coexistence with ModeLexer
- [architecture/lexer-guidelines.md](architecture/lexer-guidelines.md) — preferred lexer cursor, `StringView`, and Unicode-safe offset patterns
- [architecture/polymorphism-patterns.md](architecture/polymorphism-patterns.md) — choosing between generic, trait object, struct-of-closures, defunctionalization
- [architecture/block-reparse.md](architecture/block-reparse.md) — Block Reparse Architecture
- [architecture/egraph-vs-egglog.md](architecture/egraph-vs-egglog.md) — EGraph vs Egglog: when to use which, how Canopy uses both
- [superpowers/specs/2026-07-14-parser-context-lookahead-rename-design.md](superpowers/specs/2026-07-14-parser-context-lookahead-rename-design.md) — approved #716 clean cutover from `ParserContext::speculative` to `ParserContext::lookahead`
- [superpowers/specs/2026-07-14-markdown-code-span-authoring-contract-design.md](superpowers/specs/2026-07-14-markdown-code-span-authoring-contract-design.md) — draft #484 contract for CommonMark code-span normalization, raw-source fidelity, and block-editor authoring facts
- [superpowers/specs/2026-07-15-markdown-projection-identity-design.md](superpowers/specs/2026-07-15-markdown-projection-identity-design.md) — approved #341 policy for MarkdownIR-to-editor identity anchors, semantic keys, recovery, and view-local projection IDs
- [superpowers/specs/2026-07-17-payload-capture-design.md](superpowers/specs/2026-07-17-payload-capture-design.md) — approved private design for #loom.payload capture extraction (#688)
- [superpowers/specs/2026-07-17-loomgen-named-token-sets-design.md](superpowers/specs/2026-07-17-loomgen-named-token-sets-design.md) — accepted #687 design for centralized named token sets and generated membership functions
- [superpowers/specs/2026-07-19-loomgen-html-element-properties-design.md](superpowers/specs/2026-07-19-loomgen-html-element-properties-design.md) — proposed #607 design for one tag classifier, generated element properties, parse-local tag stacks, and HostGuard dispatch
- [superpowers/specs/2026-07-20-grammar-compiled-capabilities-design.md](superpowers/specs/2026-07-20-grammar-compiled-capabilities-design.md) — proposed #607 follow-up for slot-resolved compiled grammar, executable binding, and native capabilities
- [superpowers/specs/2026-07-17-payload-producer-boundary-design.md](superpowers/specs/2026-07-17-payload-producer-boundary-design.md) — proposed future boundary separating lexer-level custom hooks from generated variant plans (#688)
- [decisions/2026-07-17-payload-capture.md](decisions/2026-07-17-payload-capture.md) — **Accepted** private regex capture payload annotations and Markdown helper integration (#688)
- [superpowers/archive/completed-phases/2026-07-17-payload-capture.md](archive/completed-phases/2026-07-17-payload-capture.md) — completed implementation plan for #loom.payload capture extraction (#688)
- [architecture/markdown-execution-roadmap.md](architecture/markdown-execution-roadmap.md) — dependency order for MarkdownIR editor compatibility, CommonMark block/inline work, incremental conformance hardening, and the independent loomgen lane

- [grammar_ir_contract.md](grammar_ir_contract.md) — strict LL(1) alternation contract for the `#loom.rule` / `--grammar-ir` subset: disjoint FIRST sets enforced at generation time, `@fragment` escape hatch for non-LL(1) patterns, decision rationale (issue #540)
### Architecture Decisions (ADRs)

Short records of the *why* behind significant design choices. Most recent first.

- [decisions/2026-07-19-loomgen-html-element-properties.md](decisions/2026-07-19-loomgen-html-element-properties.md) — **Proposed** #607 design for shared tag classification, generated element properties, parse-local tag stacks, and HostGuard dispatch
- [superpowers/plans/2026-07-19-loomgen-html-element-properties.md](superpowers/plans/2026-07-19-loomgen-html-element-properties.md) — implementation plan for #607, including failing tests, generated classifier, source-span fidelity, and compile-once HostGuard lifecycle
- [decisions/2026-07-15-markdown-projection-identity-boundary.md](decisions/2026-07-15-markdown-projection-identity-boundary.md) — **Accepted** Markdown owns typed semantic identity alignment; Canopy owns the ephemeral current-view attachment (#341, #332)
- [decisions/2026-07-17-pattern-allowlist-tokenizer.md](decisions/2026-07-17-pattern-allowlist-tokenizer.md) — **Accepted** one fail-closed pattern parser with typed quantifiers and native counted-bound validation (#529)
- [decisions/2026-07-17-loomgrammar-production-boundaries.md](decisions/2026-07-17-loomgrammar-production-boundaries.md) — **Accepted** `.loomgrammar` production headers are first-token-on-line boundaries for diagnostic isolation (#556)
- [decisions/2026-07-17-loomgen-named-token-sets.md](decisions/2026-07-17-loomgen-named-token-sets.md) — **Accepted** centralized named token sets, shared membership lowering, and generated `is_<name>` APIs (#687)
- [decisions/2026-07-15-block-reparse-ancestor-widening.md](decisions/2026-07-15-block-reparse-ancestor-widening.md) — **Accepted** `BlockReparseSpec` selectors receive candidate-local source/tokens; core widens only after explicit decline, and `ModeRelexFactory` keeps lexer-mode snapshots session-owned
- [decisions/2026-07-14-lookahead-rollback-boundary.md](decisions/2026-07-14-lookahead-rollback-boundary.md) — **Accepted** `ParserContext::lookahead` rolls back a defined parser-owned checkpoint state for pure lookahead; any concrete out-of-contract mutation triggers review, while broadening requires independent-grammar evidence (#438, PRs #715 and #717)
- [decisions/2026-07-13-benchmark-detector-policy.md](decisions/2026-07-13-benchmark-detector-policy.md) — **Accepted** benchmark rows are explicitly gated or informational; inventory and verifier failures remain fail-closed (#644)
- [decisions/2026-07-13-benchmark-inventory-reconciliation.md](decisions/2026-07-13-benchmark-inventory-reconciliation.md) — **Accepted** baseline scope matches Moon's root `moon.work` discovery from the `examples/lambda` launch directory; 105 event-graph-walker rows retired with the removed workspace member (#712)
- [decisions/2026-07-30-error-node-ebnf-syntax.md](decisions/2026-07-30-error-node-ebnf-syntax.md) — **Accepted** `@error_node(Kind, Token)` EBNF syntax for error recovery (#605, PR #663)
- [decisions/2026-07-13-line-lexer-skeleton-integration.md](decisions/2026-07-13-line-lexer-skeleton-integration.md) — **Accepted** generated line-mode helpers delegate through preserved skeleton override points; exact stubs migrate automatically (#699)
- [decisions/2026-07-12-line-mode-fallback-lexer.md](decisions/2026-07-12-line-mode-fallback-lexer.md) — **Accepted** `#loom.fallback_lex("fn")` delegates line-mode no-match input to a mode-compatible fallback lexer while preserving `Invalid` without the annotation (#700)
- [decisions/2026-07-10-remove-emit-grammar-code-generator.md](decisions/2026-07-10-remove-emit-grammar-code-generator.md) — **Accepted** remove `loomgen/emit_grammar.mbt` — code-generated parser is no longer justified because `@grammar.interpret` reached full throughput parity (flat incremental B/A=0.95×, deep incremental B/A=0.91×); supersedes the 2026-06-22 gate
- [decisions/2026-07-17-loomgen-emitter-checklist.md](decisions/2026-07-17-loomgen-emitter-checklist.md) — **Accepted** loomgen emitter author-side verification checklist (#575)
- [decisions/2026-07-10-separated-list-ebnf-syntax.md](decisions/2026-07-10-separated-list-ebnf-syntax.md) — **Accepted** `Expr{Sep}` separated-list EBNF syntax for `RepeatTopLevel` lowering with incremental delimiter reuse (#604)
- [decisions/2026-07-06-markdown-inline-native-only.md](decisions/2026-07-06-markdown-inline-native-only.md) — **Accepted** Markdown inline parsing stays permanently `@native` host code; loomgen targets the CommonMark block subset but does NOT generate inline (emphasis is a non-context-free delimiter-stack, link reference definitions are document-global two-pass) — keeping the IR data-only per #541; won't-generate, not deferred (#642, #608)
- [decisions/2026-07-03-structural-ast-testing-grammar-emitter.md](decisions/2026-07-03-structural-ast-testing-grammar-emitter.md) — *(superseded by 2026-07-10 ADR)* **Accepted** extract `emit_grammar_module` → `MbtModule` AST to test the grammar emitter structurally via `derive(Eq)` instead of fragile `source.contains` string matching; fixture regeneration requires `moon fmt` post-processing
- [decisions/2026-06-22-grammar-incremental-throughput-gate.md](decisions/2026-06-22-grammar-incremental-throughput-gate.md) — *(superseded by 2026-07-10 ADR)* **Accepted** `@grammar` #444 throughput gate: the tree-walking interpreter is at incremental parity on the flat/common path (B/A ≈ 0.9–1.0×) but has a deep-subtree reuse gap (B re-parses deep nested subtrees instead of reusing them → B/A ≈ 1.15–2.4× on deep edits) — graduate the interpreter, defer the code-emitter as the named fix for that gap (#449), keep `@grammar` unblessed until a non-spike consumer
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

## Analysis

Point-in-time diagnoses. Dated snapshots — verify against current code before acting.
> Archive: Do not read files in this section unless user explicitly asks for historical context.
- [archive/completed-phases/2026-07-14-parser-context-lookahead-rename.md](archive/completed-phases/2026-07-14-parser-context-lookahead-rename.md) — **Complete** #716 clean rename from `ParserContext::speculative` to `ParserContext::lookahead` (PR #717)

- [archive/completed-phases/2026-07-10-remove-emit-grammar-realign-loomgen.md](archive/completed-phases/2026-07-10-remove-emit-grammar-realign-loomgen.md) — **Complete** implementation plan for removing the `emit_grammar.mbt` parser code generator (`@grammar.interpret` reached full parity) and trimming `mbt_ast.mbt` to the subset used by `emit_grammar_ir.mbt`; 6 tasks, supersedes 2026-06-28 plan
- [archive/completed-phases/2026-07-fallback-lex.md](archive/completed-phases/2026-07-fallback-lex.md) — **Complete** implementation plan for `#loom.fallback_lex`, including parser validation, line-mode emission, fixture regeneration, and verification
- [superpowers/specs/2026-07-13-line-lexer-migration-properties-design.md](superpowers/specs/2026-07-13-line-lexer-migration-properties-design.md) — approved design for structural QuickCheck coverage of exact, non-destructive line-lexer skeleton migration
- [archive/completed-phases/2026-07-13-line-lexer-migration-properties.md](archive/completed-phases/2026-07-13-line-lexer-migration-properties.md) — **Complete** implementation plan for structural QuickCheck generation and an independent exact-string line-lexer skeleton migration oracle (PR #709, follow-up to #708)
- [superpowers/specs/2026-07-13-line-lexer-skeleton-design.md](superpowers/specs/2026-07-13-line-lexer-skeleton-design.md) — approved design for non-destructive line-mode lexer skeleton integration (#699)
- [archive/completed-phases/2026-07-13-line-lexer-skeleton-integration.md](archive/completed-phases/2026-07-13-line-lexer-skeleton-integration.md) — **Complete** implementation plan for automatic, non-destructive line-mode lexer skeleton integration (#699)
- [superpowers/specs/2026-07-12-fallback-lex-design.md](superpowers/specs/2026-07-12-fallback-lex-design.md) — approved design for mode-compatible line-mode lexer fallback delegation (#700)
- [superpowers/specs/2026-07-15-block-reparse-ancestor-widening-design.md](superpowers/specs/2026-07-15-block-reparse-ancestor-widening-design.md) — approved design for context-aware block-reparse candidate widening after explicit language rejection
- [archive/completed-phases/2026-07-15-block-reparse-ancestor-widening.md](archive/completed-phases/2026-07-15-block-reparse-ancestor-widening.md) — **Complete** implementation plan for context-aware block-reparse candidate widening after explicit language rejection
- [archive/completed-phases/2026-07-14-markdown-code-span-authoring-contract.md](archive/completed-phases/2026-07-14-markdown-code-span-authoring-contract.md) — **Complete** implementation plan for native CommonMark code spans, baseline indentation decomposition, and lossless raw-content origins (#484; authoring-fact delivery deferred)
- [archive/completed-phases/2026-07-15-markdown-projection-identity.md](archive/completed-phases/2026-07-15-markdown-projection-identity.md) — **Complete** implementation plan for MarkdownIR-owned editor identity alignment, recovery, and view-local projection separation (#341; PR #724)
- [superpowers/plans/2026-06-28-grammar-ir-emitter.md](superpowers/plans/2026-06-28-grammar-ir-emitter.md) — *(superseded by 2026-07-10 ADR)* implementation plan for the mode-agnostic Grammar IR emitter: generate `parse_root`/`parse_<rule>` MoonBit code from existing `@grammar.GrammarIr`, verify emitted parsers against `@grammar.interpret`, and keep `SwitchLexMode` deferred pending parser-runtime mode design
- [superpowers/plans/2026-06-20-parser-generation-spike.md](superpowers/plans/2026-06-20-parser-generation-spike.md) — implementation plan for the lambda parser-generation de-risk spike: grammar-IR interpreter, persistent A-vs-B oracle, reuse-parity calibration, ergonomics gates, and decision record template
- [analysis/2026-06-20-parser-generation-spike-results.md](analysis/2026-06-20-parser-generation-spike-results.md) — **CONDITIONAL GO**: D1/D2a/D2b all pass; E1=1/7 declarative rules; missing Seq+Pratt combinators block E3; next step = IR extension before full loomgen investment
- [analysis/2026-06-20-parser-generation-direction.md](analysis/2026-06-20-parser-generation-direction.md) — recommendation + de-risk spike for "morm-style parser-generation-friendly" loom: loomgen plumbing = target, grammar-as-data interpreter = spike-gated hypothesis, ideal = one grammar value as single source; the spike's CST-master-invariant oracle and (i)-vs-(ii) equivalence-bar fork
- [superpowers/specs/2026-06-29-fold-term-algebra-printers-design.md](superpowers/specs/2026-06-29-fold-term-algebra-printers-design.md) — design spec for migrating the lambda example's two hand-recursing printers (`to_source`/`to_layout`) onto the `interpret` catamorphism: precedence is already compositional, Module bracing made uniform (always-brace, round-trip-safe) to drop the only top-down flag, sugar dropped as accepted cosmetic churn; adds minimal-paren `SourceText`, retires test-only `Pretty`, ~150 lines net deleted
- [superpowers/specs/2026-07-13-benchmark-detector-policy-design.md](superpowers/specs/2026-07-13-benchmark-detector-policy-design.md) — approved design for benchmark eligibility, inventory, and infrastructure-failure classification (#644)
- [archive/completed-phases/2026-07-13-benchmark-inventory-reconciliation-improvements-design.md](archive/completed-phases/2026-07-13-benchmark-inventory-reconciliation-improvements-design.md) — **Complete** design for the benchmark candidate evidence boundary and fail-closed guard clarification (#712), linked to the implementation plan and ADR
- [archive/completed-phases/2026-07-13-benchmark-inventory-reconciliation-improvements.md](archive/completed-phases/2026-07-13-benchmark-inventory-reconciliation-improvements.md) — **Complete** implementation plan for final candidate measurements, ADR evidence, guard clarification, and final verification (#713)
- [archive/completed-phases/2026-07-17-quantifier-unification.md](archive/completed-phases/2026-07-17-quantifier-unification.md) — **Complete** implementation plan for the typed quantifier AST and validated counted bounds (#529)
- [archive/completed-phases/2026-07-13-benchmark-detector-policy.md](archive/completed-phases/2026-07-13-benchmark-detector-policy.md) — **Complete** implementation plan for fail-closed benchmark parsing/inventory checks and explicit gated/informational detector policy (#644)
- [superpowers/plans/2026-06-29-fold-term-algebra-printers.md](superpowers/plans/2026-06-29-fold-term-algebra-printers.md) — implementation plan for migrating lambda printers onto the `interpret` fold
- [superpowers/specs/2026-06-21-loomgen-ir-contract-design.md](superpowers/specs/2026-06-21-loomgen-ir-contract-design.md) — design spec for the minimal grammar-IR contract (loomgen codegen stage 1): reify predicates as `Pred[T]` (no `Opaque`), reify-first escape-hatch policy, backend (c) — one reified IR, tree-walker committed, analyzing-interpreter + emitter benchmark-gated on incremental throughput; grounded in monogram; Codex-validated sound-with-fixes
- [analysis/2026-06-20-architecture-restructuring.md](analysis/2026-06-20-architecture-restructuring.md) — pressure-gated architecture diagnosis: the parser engine still needs no restructuring; pressure moved into the language-authoring layer + `loom/src/core`; the one dependency-graph-proven move is extracting `projection_identity` into `loom/projection` (Stage A1); `proj_traits` relocation, the markdown-monolith split, and the AP5 attachment-promotion question are judgments/gates, not facts
- [analysis/2026-06-20-ideal-package-decomposition.md](analysis/2026-06-20-ideal-package-decomposition.md) — first-principles (ungated) companion to the restructuring diagnosis: the structurally-ideal `loom/core` cut is a contract/implementation boundary running *through* the machinery (public reuse/buffer protocol + combinators; mechanism hidden), with MoonBit `internal/` earning at most one package (recovery, conditional) since the heaviest mechanism already lives in `seam`
- [analysis/2026-05-08-architecture-status-update.md](analysis/2026-05-08-architecture-status-update.md) — delta on the 2026-04-19 diagnosis: what shipped, revised Stage C (egraph stays as peer library — supersedes prior `experiments/` proposal)
- [analysis/2026-04-19-architecture-diagnosis.md](analysis/2026-04-19-architecture-diagnosis.md) — change pressures, sibling-module boundary issues, staged migration proposal (Stages A–D)

## Performance

- [performance/PERFORMANCE_ANALYSIS.md](performance/PERFORMANCE_ANALYSIS.md) — benchmarks and analysis
- [performance/benchmark_history.md](performance/benchmark_history.md) — historical benchmark log
- [performance/bench-baseline.tsv](performance/bench-baseline.tsv) — machine-readable baseline for `bench-check.sh`
- [performance/bench-detector-policy.tsv](performance/bench-detector-policy.tsv) — versioned gated/informational benchmark eligibility policy used by `bench-check.sh`
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
- [../loomgen/README.md](../loomgen/README.md) — code generator for loom language plumbing (`#loom.*` annotated Token → `syntax_kind.g.mbt`)
- [../loomgen/HANDOFF.md](../loomgen/HANDOFF.md) — session handoff context for loomgen Phase 1 implementation
- [decisions-needed.md](decisions-needed.md) — triage items flagged `needs-human-review`

### Examples

Each example demonstrates a different `@loom.Grammar` feature axis:


- [../examples/css/](../examples/css/) — `#loom.rule` EBNF syntax `~` (Emit), `!` (EmitOr), `@until` (ErrorUntil) with parity-verified CSS declaration-list grammar
- [../examples/lambda/README.md](../examples/lambda/README.md) — typed `SyntaxNode` views, classical recursive descent
- [../examples/json/README.md](../examples/json/README.md) — step-based total lexing + `block_reparse_spec`
- [../examples/json-settings/README.md](../examples/json-settings/README.md) — checked last-good semantic projection attachment (pure derived + imperative `settle`)
- [../examples/markdown/README.md](../examples/markdown/README.md) — mode-aware lexing via `ModeLexer`
- [../examples/jsx/README.mbt.md](../examples/jsx/README.mbt.md) — streaming-prefix error recovery, truncation-preserving lexer/parser/AST (canopy JSX plan Phase 1)
- [../examples/moonbit/README.md](../examples/moonbit/README.md) — official MoonBit lexer adapter + coarse Loom CST skeleton
- [../examples/graph-dsl/README.md](../examples/graph-dsl/README.md) — source-map/token-role graph authoring example with graph-operation lowering
- [../examples/lambda/ROADMAP.md](../examples/lambda/ROADMAP.md) — lambda grammar expansion plans, CRDT exploration

### Sibling Utility Modules

- [../text-change/README.md](../text-change/README.md) — pure contiguous text-change utilities (migrated from canopy 2026-05, #147)
- [../moji/README.md](../moji/README.md) — UAX #29 grapheme cluster + word boundary segmentation, UTF-16 indexed (migrated from canopy 2026-05, #147)

### Active Plans

- _Shipped: #529 fail-closed pattern allowlist tokenizer. See [archived plan](archive/completed-phases/2026-07-17-pattern-allowlist-tokenizer.md) and [ADR](decisions/2026-07-17-pattern-allowlist-tokenizer.md)._
- [parse_patternリファクタリング計画](archive/completed-phases/2026-07-17-parse-pattern-refactoring.md) — #529後のprivate pattern parser責務分割を完了。受理範囲・診断優先順位・生成出力を維持。
 - [Quantifier統一計画](archive/completed-phases/2026-07-17-quantifier-unification.md) — typed quantified-pattern AST and verified counted bounds.
_Shipped: [#484 Markdown code span contract](archive/completed-phases/2026-07-14-markdown-code-span-authoring-contract.md) — native-only parsing with maximal delimiter runs and CommonMark normalization; structural continuation ownership and contiguous-only content origins apply to supported projections. List-item setext headings remain CST-only and await MarkdownIR block-child lowering. Authoring-fact delivery remains deferred until a concrete editor host owns snapshot identity._
_Shipped: block reparse ancestor widening — context-aware candidate selection widened to strict reparseable ancestors. See [archived plan](archive/completed-phases/2026-07-15-block-reparse-ancestor-widening.md) and [ADR](decisions/2026-07-15-block-reparse-ancestor-widening.md)._
_Shipped: `Native(RuleName)` IR escape-hatch node for context-sensitive productions (HTML tag matching) — issue [#541](https://github.com/dowdiness/loom/issues/541) closed, merged as PR #551. See [plan](superpowers/plans/2026-07-01-native-rulename-ir-node.md) (pending archival)._
_Shipped: view framework consumer design (Phase A of #514) — `AstView` moved to `@seam`, loomgen generates `AstView` impl on `*Proj` structs. See [design spec](superpowers/specs/2026-06-28-view-framework-consumer-design.md)._
_Previously active: the minimal grammar-IR contract (loomgen codegen stage 1) **merged** as PR #443 — `dowdiness/loom/grammar` package with generic `[T,K]` IR, `Pred[T]` reification, dense-slot rule interning, the reified escape hatches (grown vocabulary), the evidence-gated `ManualNewlineAppExpr` residue, and D1/D2a/D2b re-validated on the reified lambda IR. See [plan](superpowers/plans/2026-06-22-loomgen-ir-contract.md) and [design spec](superpowers/specs/2026-06-21-loomgen-ir-contract-design.md)._

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
  - [archive/STRUCTURAL_VALIDATION.md](archive/STRUCTURAL_VALIDATION.md), [archive/EDGE_CASE_TESTS.md](archive/EDGE_CASE_TESTS.md) — *(archived 2026-07-04)* Lezer-era incremental-parser status docs; describe `TokenCache`/`ParseCache`/`RecoveringParser` code deleted in the Phase 0 cleanup
