# ADR: Unified Parser — Replace Two-Parser Split With Single Parser + Multiple Update Paths

**Date:** 2026-04-17
**Status:** Accepted (2026-04-18)
**Supersedes:** [2026-03-02: Two-Parser Design](2026-03-02-two-parser-design.md)
**Implementation plan:** [docs/plans/2026-04-17-unified-parser.md](../plans/2026-04-17-unified-parser.md)

## Context

ADR [2026-03-02](2026-03-02-two-parser-design.md) decided to maintain two
sibling parsers:

- `ImperativeParser[Ast]` — caller drives with explicit `Edit`, CST-node-level reuse
- `ReactiveParser[Ast]` — caller sets source, `Signal`/`Memo` pipeline handles recomputation

The rationale was that node-level reuse requires knowing the edit position, and
this forces a separate API from the source-string update model used by language
servers and build tools.

Since March, the two parsers have been used in production — the imperative
parser powers canopy's text editor (keystroke-level CRDT edits); the reactive
parser powers `attach_typecheck` and the lambda example tests, providing
reactive composition with `@incr`-based downstream stages.

Two observations from this period prompted the rethink:

1. **Canopy's web demo needs both.** The editor consumes the imperative path
   for edit-aware reuse; the type-checker needs reactive composition off the
   same parse. Today the only clean paths are to replace the editor parser
   wholesale, run a second parallel reactive parse and accept double-parsing,
   or bypass the typecheck helper. None are acceptable.

2. **Comparable projects use a single parser.** All four references we looked
   at (mizchi/markdown.mbt, tree-sitter, rust-analyzer/rowan, lezer) cluster
   on a single-parser + separate-composition-layer design — not two sibling
   parser types.

This ADR proposes that the split into two types is an implementation artifact,
not a fundamental design constraint, and that convergence unblocks downstream
composition without sacrificing either parser's current capabilities.

## Research

### mizchi/markdown.mbt

Single `Document` type with two entry points: fresh parse and incremental
parse. Primary update path is CST patch operations; re-parsing is a repair
path. Block-level fragment reuse via stable `nodeId`.

### tree-sitter

One `TSParser` per language. `ts_parser_parse` accepts an optional
`old_tree` — same function for both fresh and incremental modes. Pure
parser library; no built-in reactive composition.

### rust-analyzer / rowan

Parser is hand-written recursive descent; parses fresh on every text
change. Incrementality comes from Salsa's revision counter + structural
sharing, not from the parser itself. Update model:
`AnalysisHost::apply_change(new_source)`.

### lezer

One `LRParser` per grammar. Update via `TreeFragment.applyChanges` —
caller annotates the cache with edit ranges, parser reuses unchanged
fragments on next parse.

### Common pattern

The four projects don't all share a single design, but they cluster on two
points:

1. **Downstream composition is a separate layer** (Salsa queries, tree
   walking, reactive Memos) built on top of a parser that produces values
   — true for all four, including rust-analyzer which reparses fresh.
2. **Where incremental reuse exists, it is internal to the parser**, not
   composed by the caller from smaller pieces.

The stronger claim — "single parser type, multiple update paths in the
same API" — holds for tree-sitter, lezer, and markdown.mbt.
rust-analyzer is the counter-example; it is relevant to this ADR for
its *composition* model, not its update-API model.

## First-Principles Analysis

The [2026-03-02 ADR](2026-03-02-two-parser-design.md) justifies the split with:

> *"Node-level reuse is fundamentally impossible without knowing where the
> edit happened."*

This is true. But the correct conclusion is not "two parser types." The
correct conclusion is "two update methods." The bundled differences in
loom's current design — update API, reuse granularity, reactive composition
— are three orthogonal axes, not one:

| Axis | Today | Tree-sitter |
|------|-------|-------------|
| Update API | Split (`edit` vs `set_source`) | Unified (`ts_parser_parse`) |
| Reuse granularity | Split (node vs pipeline) | Unified (subtree if old_tree provided) |
| Reactive composition | Split (impossible vs natural) | N/A (tree-sitter has no reactive layer) |

A single parser type can accept both update methods, use edit information
internally to drive CST-node reuse when available and fall back to full
re-parse when not, and publish its output through read-only reactive
handles so downstream stages compose regardless of which update method the
caller used.

The prior ADR's own future-trajectory section supports this reading —
`ImperativeParser` as the engine, the `@incr` graph as the distribution
layer. A sibling reactive parser is not required by that vision and in
fact obstructs it, because the reactive graph cannot sit on top of the
imperative engine if they are peers that neither references the other.

## Source of truth (scope)

Before specifying the parser API, fix the layer that is primary. This ADR
commits to **text as the source of truth** and treats CST and AST as derived
views.

### Choice: `String`

Canopy already treats source text as primary — the CRDT operates on text,
the imperative parser derives the CST, downstream stages are memos over that
derivation. Consistent with the existing architecture:

- **Universal at every boundary** — file I/O, LSP, git, clipboard, terminal.
- **Mature collaboration story** — text CRDTs are production-grade;
  tree CRDTs remain research-grade.
- **Robust to malformed input** — half-typed code is just a string.
- **Lossless** — trivia, comments, formatting survive round-trip for free.

Costs — no stable node identity, every edit flows through the parser,
character-granularity collaboration conflicts — are acceptable within this
ADR's scope.

### Deferred: `SyntaxNode` as primary (CST-as-source-of-truth)

Would unlock true subtree identity, structural editing (Hazel/Grove-style),
and semantic merges. Tree CRDTs, malformed-input invariants, and
text-boundary serializers are the cost. Separate, larger decision —
flagged as future trajectory in ADR 2026-03-02 and explicitly not bundled
here.

### Rejected: `Ast` / `Term` as primary

Loses source fidelity (trivia, comments, formatting, error recovery),
cannot represent incomplete code well, and requires a pretty-printer that
will inevitably diverge from the parser. Appropriate as a derived view,
not the source of truth.

## Decision

Consolidate into a single unified parser type. In principle:

1. **Keep the imperative engine unchanged.** `ImperativeParser[Ast]`
   remains the low-level engine — node-level reuse, damage tracking, block
   reparse all stay inside it. It does not gain an `@incr` dependency.

2. **Introduce a unified `Parser[Ast]` as a thin reactive wrapper.** It
   owns the engine, exposes both update methods (`set_source` and
   `apply_edit`), and publishes reactive views over derived state.

3. **Publication contract:**
   - Source, syntax tree, AST, and diagnostics are all published as
     read-only `@incr.Memo` views.
   - Both update methods update all derived cells together, atomically,
     inside a single `Runtime::batch`.
   - The reactive layer is a publication mechanism, not the compute
     graph — `@incr` never drives parsing; the engine does.

4. **Read-only views, not raw signals.** Callers should not be able to
   `.set()` the underlying cells and desynchronize the engine from
   published state. `@incr.Memo` is the read-only view type; raw
   `Signal` cells stay private. This is value-safety, not
   capability-safety — the escape hatch via `Runtime::dispose_cell`
   exists and is treated as out of contract.

5. **Accepted regressions vs today's `ReactiveParser`.** The staged
   pipeline memos (token-stage trivia-insensitive cutoff, lazy
   `cst()`/`diagnostics()` staging) and lazy `term()` evaluation are
   dropped in the initial design. What is preserved — reactive
   publication of source, syntax tree, AST, and diagnostics, plus
   `Ast : Eq` backdating for downstream memos. External runtime
   injection (the `from_parts` capability) is preserved; its exact
   shape is an implementation detail in the plan. Re-adding any
   dropped capability is a follow-up ADR if a consumer demonstrates
   need.

Concrete API signatures, internal structure, and the staged file-by-file
migration live in the [implementation plan](../plans/2026-04-17-unified-parser.md).

## Why this is better than the status quo

**One type instead of two** for every use case currently served by either
parser:

| Use case | Today | Proposed |
|----------|-------|----------|
| Text editor with CRDT edits | `ImperativeParser` (no reactive composition) | `Parser` + `apply_edit` + reactive source |
| Language server | `ReactiveParser` (no node-level reuse) | `Parser` + `set_source` + reactive source |
| Projection / source-map / token-spans | `ReactiveParser::cst()` | `Parser` reactive syntax tree |
| Parse-error surfacing (FFI / UI) | `ImperativeParser::diagnostics()` (pull) | `Parser` reactive diagnostics, batched with syntax tree |
| Editor + downstream typecheck (canopy web demo) | **No clean path** | Single `Parser` owned by the editor; typecheck attaches to reactive syntax tree |

**CST-node reuse + reactive composition together** — which the current
design splits into two incompatible choices.

**One reactive layer** — the `@incr` graph — covers the full pipeline
from source text to downstream stages. Matches the 2026-03-02 trajectory
literally.

## Consequences

### Wins

- **Single conceptual parser surface** — one type to learn, one type to
  document, one place to fix bugs.
- **Canopy web demo unblocked — no more double-parsing.** The editor
  and the type-checker share one parser and one runtime; the duplicate
  parse in the FFI goes away.
- **Closer alignment with tree-sitter and lezer** (single parser type
  with explicit + implicit update paths). rust-analyzer is a weaker
  analogue — it reparses fresh — but its *composition* model (parser
  below, reactive graph above) is the one this ADR adopts.
- **Concrete path toward the 2026-03-02 trajectory** — executes the
  "expand `@incr` foundation to cover the full pipeline" step.
- **Ast-level backdating still works.** `Ast : Eq` short-circuits
  downstream Memos when edits produce equal ASTs, same mechanism as
  today, one layer down.

### Costs

- **Cross-cutting migration.** Touches loom pipeline code, canopy
  editor core, three language companions, and the lambda FFI. Staged
  over ~6 PRs; one transitional release where `Parser` and
  `ReactiveParser` coexist. Details in the plan.
- **Accepted regressions.** Staged pipeline memos and lazy `term()`
  are dropped in the initial design. Trivia-only edits will do more
  downstream work than today. CST and diagnostics remain reactive,
  just via single eager Memos rather than staged ones. External
  runtime injection is preserved.
- **Benchmark verification required.** `Parser::apply_edit` must
  retain the imperative engine's node-reuse performance (should be
  identical — the engine is unchanged).

### Non-consequences

- **`ImperativeParser` is not deprecated.** It remains the engine; its
  internal improvements continue to benefit `Parser` transparently.
- **No change to the `seam` CST model.** `Parser` publishes the same
  `Ast` type the engine produces today.
- **No change to `@incr`'s public API.** `Parser` is a new consumer.

## Open questions

No open questions at the principle level. Implementation-shaped
questions (constructor / runtime-injection shape, final type name,
whether `apply_edit` accepts an `Editable` trait) are captured in the
[plan](../plans/2026-04-17-unified-parser.md) to be resolved in the
Stage 1 PR.

## Alternatives considered

### Keep current design, add compatibility glue per consumer

Each consumer manually bridges `ImperativeParser` ↔ `ReactiveParser` in
its own way.

**Rejected:** glue code accumulates, never gets removed, each consumer
reinvents the bridge differently, the mental model stays "two parsers"
indefinitely.

### Converge inside `ImperativeParser` by adding `@incr` dependency

The engine grows a reactive publication field directly. No new type.

**Rejected:** expands `@incremental`'s dependency graph to include
`@incr`, which is a one-way door coupling the engine to the reactive
layer. Cleaner to layer via a wrapper.

### Hazel-style: CST-as-source-of-truth now

Skip unifying text-based parsers entirely; move straight to structural
edits.

**Rejected:** too large a leap. The text-edit input path works and
serves CRDT correctly. Structural editing is a future direction that
builds on top of unified parsing — not a replacement for it.

## References

### Prior ADRs

- [2026-03-02: Two-Parser Design](2026-03-02-two-parser-design.md) — the decision
  this proposal supersedes.
- [2026-03-15: Reintroduce TokenStage Memo](2026-03-15-reintroduce-token-stage-memo.md) —
  the three-memo pipeline that `ReactiveParser` wraps; relevant to the
  dropped staged-memo regression.

### Implementation

- [docs/plans/2026-04-17-unified-parser.md](../plans/2026-04-17-unified-parser.md) — API signatures, struct layout, staged migration.

### Related loom docs

- [docs/api/choosing-a-parser.md](../api/choosing-a-parser.md) — user-facing
  parser selection guide; rewritten or retired during Stage 5 of the
  [implementation plan](../plans/2026-04-17-unified-parser.md).
- [docs/architecture/pipeline.md](../architecture/pipeline.md) — parse pipeline
  architecture; affected by the consolidation.

### External projects cited

- mizchi/markdown.mbt — [README](https://github.com/mizchi/markdown.mbt).
  Single `Document` type with incremental entry point; CST-as-source-of-truth
  model.
- tree-sitter — [using-parsers](https://tree-sitter.github.io/tree-sitter/using-parsers/).
  Subtree reuse via optional old-tree hint.
- rust-analyzer — [architecture](https://rust-analyzer.github.io/book/contributing/architecture.html).
  No incremental parsing; Salsa + structural sharing for downstream
  incrementality.
- lezer — [guide](https://lezer.codemirror.net/docs/guide/). LRParser with
  `TreeFragment.applyChanges` for incremental updates.

### Papers informing the future trajectory

- [eg-walker CRDT](https://arxiv.org/abs/2409.14252)
- [Total Type Error Localization and Recovery with Holes (POPL 2024)](https://dl.acm.org/doi/10.1145/3632910)
- [Gradual Structure Editing with Obligations (VL/HCC 2023)](https://hazel.org/papers/teen-tylr-vlhcc2023.pdf)
- [Grove: Collaborative Structure Editor (POPL 2025)](https://hazel.org/papers/grove-popl25.pdf)

## Decision

Accepted 2026-04-18. The 2026-03-02 two-parser-design ADR was marked
**Superseded by** this ADR, and Stage 1 of the
[implementation plan](../plans/2026-04-17-unified-parser.md) landed
the same day (`Parser[Ast]` added alongside `ReactiveParser` in
`loom/src/pipeline/`). Stages 2–6 proceed per the plan.
