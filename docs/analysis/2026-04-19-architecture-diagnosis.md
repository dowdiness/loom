# Architecture Diagnosis — 2026-04-19

**Status:** Point-in-time diagnosis. Not an ADR. Not an execution plan. Informs future plans.

**Headline:** The core framework does not need restructuring. Real issues are at repo scope (sibling-module ambiguity), at the extension API (no public traversal traits), and at a pass-through facade layer.

---

## 1. Change pressures driving redesign

| Pressure | Type | Evidence |
|----------|------|----------|
| CST traversal primitives missing | Extensibility friction | ROADMAP #58 ("public CST traversal traits"), blocks #59/#60 |
| Sibling-module sprawl | Boundary ambiguity | `cst-transform` flagged for cleanup (ROADMAP #62); `graphviz` awaiting publish (ROADMAP:174); `egraph`→`lambda` reverse dep; `egglog`→`incr` with no documented contract |
| Typed-view boilerplate | Scalability friction | `examples/lambda/src/views.mbt` is 514 lines of cast-and-extract; no codegen; every new language pays the cost |
| Zero-copy lexing deferred | Performance | `#61`, `decisions-needed.md` |
| Post-consolidation cleanup | Hygiene | Stages 1–6 completed 2026-04-10→2026-04-17; `ReactiveParser` deleted (d85d5ff); `pipeline/` now thin |

**Not pressuring change** (out of scope):
- Parser engine correctness — no churn in `loom/src/core/*` in 30 commits.
- CST model — `seam/` unchanged, language-agnostic.
- Reactive publication layer — just consolidated; ADR 2026-04-17 accepted same day.

## 2. Current architecture diagnosis

**Subsystems:**

| Subsystem | Owns | Size | Recent churn |
|-----------|------|------|-------------|
| `seam/` | `CstNode`, `SyntaxNode`, `EventBuffer` | 715+643 LOC core files | none |
| `incr/` (submodule) | Reactive signals/memos | n/a | 2 bumps |
| `loom/src/core/` | `Edit`/`Range`/`TextDelta`, `TokenBuffer`, `ReuseCursor`, `ParserContext`, `LanguageSpec` | 979+697+687 LOC | none |
| `loom/src/incremental/` | `ImperativeParser` orchestration, damage tracking | sealed | none |
| `loom/src/pipeline/` | `Parser[Ast]` wrapper + language adapter; publishes `@incr.Memo` | 178+ LOC | **all recent churn** |
| `loom/src/viz/` | CST→Dot renderer | 239 LOC | none |
| `loom/src/loom.mbt` | Facade (pure re-export) | 47 LOC | low |

**Dependency graph (from `moon.pkg.json`):** acyclic tree.
- Roots: `seam`, `incr`.
- `loom` → `seam` + `incr` + `graphviz` + `text-change`.
- Examples → `loom` + `seam` + `incr` + `pretty`.
- `egraph` → `lambda` (reverse dep: research imports example — for test oracle).
- `egglog` → `incr` directly; purpose not documented.
- `cst-transform` → isolated; nothing imports it.

**Ownership:** clean. Parser state sealed in `ImperativeParser`. Reactive cells owned by `Parser[Ast]`. No shared mutable state across package boundaries.

## 3. Architectural problems

Four genuine issues (not code smells):

**P1. Facade adds no value.** `loom/src/loom.mbt` is pure `pub using` re-export. Seam without invariant or abstraction.

**P2. Sibling modules have unclear boundaries** (updated 2026-04-19 after investigation).
- `egraph` → `lambda` is **test-only** (`egraph/moon.pkg` suppresses warning `-29`; `*_wbtest.mbt` files only; core `egraph.mbt` has zero `@lambda` imports). Core library is language-agnostic. Research-phase: 45+ TODO items flagged high/medium/lower priority.
- `egglog` → `incr` is a **deep algorithmic coupling**, not a hidden internal: `@incr.FunctionalRelation[String, Value]` drives semi-naive Datalog delta tracking; `@incr.Runtime` is reset per `Saturate` iteration; `rt.fixpoint()` drives the reactive graph to stabilization. This is the core algorithm, not a convenience import. Production-oriented, actively maintained.
- `cst-transform`'s `transform_cps` + `transform_view` are flagged for removal (ROADMAP #62) but still in-tree.
- `graphviz/` is a local path dep awaiting a published replacement (ROADMAP:174).

The boundary issue is not that these modules are coupled — it is that the coupling status (test-only, algorithmic, cleanup-pending, awaiting-publish) is not documented anywhere and must be reverse-engineered from sources.

**P3. CST traversal is almost fully in place; the only real gap is #60** (corrected 2026-04-19 after reading `seam/cst_traits.mbt` + running `cd seam && moon bench --release`).

`seam/cst_traverse.mbt` (ported 2026-03-30) provides closure methods `transform`, `fold`, `transform_fold`, `each`, `iter`, `map` + the `Finder` trait. **Additionally, `seam/cst_traits.mbt` provides `Folder` and `TransformFolder` traits** — I missed this on the first pass of the diagnosis. Current ROADMAP #58–#60 status:

| ROADMAP ask | Status | Evidence |
|-------------|--------|----------|
| `Folder` trait | ✅ **done** | `cst_traits.mbt:16` + `CstElement::accept_fold` at :38 |
| `TransformFolder` trait | ✅ **done** | `cst_traits.mbt:30` + `CstElement::accept_transform_fold` at :52 |
| `Finder` trait | ✅ **done** | `cst_traverse.mbt:185–207` |
| `MutVisitor` trait (#59) | missing — **and evidence argues against building it** | see benchmark data below |
| `CstNode::each` public (#60) | missing | `walk_children_flat` is private in `syntax_node.mbt:193` with repeat-group flattening; 8+ internal call sites |

**Measured performance (`cd seam && moon bench --release`, 2026-04-19):**

| Benchmark | Time |
|-----------|------|
| `build_tree with ReuseNode` (50 × 100 tokens; drives `CstNode::new`) | 34.72 µs |
| `text_len via accept_fold[TextLen]` (trait) | 400.53 µs |
| `text_len via closure fold` | **316.29 µs** (closure is 26% faster than trait here) |
| `node_count via accept_transform_fold[NodeCount]` (trait) | 287.69 µs |
| `node_count via closure transform_fold` | 291.14 µs (parity with trait) |

**What the numbers show:**
- The "closures are ~2× slower than traits" framing in `cst_traverse.mbt:37-39` does not hold for the benchmarked workloads. Closures match or beat traits. The narrow claim (closures *with captured upvars* specifically) may still apply in some cases, but no measured evidence exists for it in-repo.
- `build_tree` (which invokes `CstNode::new` for every finished node) completes in 34 µs for a mid-sized tree. `CstNode::new` is not hot.
- The ROADMAP #59 caveat ("only worthwhile if `CstNode::new` is not on the critical path") resolves in the negative: it is not on one.

**Consequence:** ROADMAP #58 is effectively complete. The only remaining item with a clear justification is #60's visibility change. `MutVisitor` should not be built speculatively — require a concrete consumer that demonstrates a measurable closure-perf wall before implementing.

**P4. Extension API has remnant closure-shaped hooks.** The 2026-03-04 trait cleanup eliminated 7 closures; `parse_root: (ParserContext) -> Unit` remains. Minor — flag, do not fix now.

## 4. Target architecture

A deliberately **modest** target. Keep what works; fix what the evidence identifies.

```
Examples (lambda, json, markdown)
    │
    ▼
loom (public surface)
  pipeline/: Parser[Ast] + Memo cells
  incremental/: ImperativeParser
  viz/: renderer (uses traversal traits)
  core/: Edit, Range, ParserContext, LanguageSpec,
         TokenBuffer, ReuseCursor
    │
    ▼
seam (data + traversal)
  CstNode, SyntaxNode, EventBuffer
  traversal/: Folder, MutVisitor, Finder (NEW)
    │
    ▼
incr (reactive primitives, submodule)

Out-of-tree / quarantined:
  experiments/ (cst-transform, egraph, egglog)
    — may depend on loom; loom MUST NOT depend on them
```

**Changes vs current:**
1. Add `seam/traversal/` package — tiny, trait-only.
2. Move `cst-transform`, `egraph`, `egglog` under `experiments/` (or delete `cst-transform` per ROADMAP #62).
3. Delete or justify `loom/src/loom.mbt`.
4. Replace local `graphviz/` with published dep.

**No new patterns.** Traversal traits follow the existing `IsTrivia`/`IsEof`/`ToRawKind` trait-based extension pattern (2026-03-04 ADR precedent).

## 5. Dependency and boundary rules

| Rule | Rationale |
|------|-----------|
| `seam` must not import `loom`, `incr`, or anything above it | Already true; keeps CST model reusable |
| `loom/core` may depend on `seam` but not on `loom/pipeline` / `loom/incremental` | Already true; layer direction |
| `loom/pipeline` may depend on `loom/incremental`, `loom/core`, `incr` | Already true |
| Examples must use loom's public API (not `loom/src/core/*` internals) | Enforced by package visibility |
| `experiments/*` may depend on loom; loom MUST NOT depend on experiments | **New rule** |
| `seam/traversal` depends only on `seam` itself | Avoids orphan-rule workarounds |

## 6. Migration strategy (staged)

Each stage is independently reversible and individually shippable.

**Stage A — facade + sibling hygiene (1–2 PRs, 1 day).**
- Decide: delete `loom/src/loom.mbt` OR replace its re-exports with a documented invariant. Evidence tips toward delete.
- Switch `graphviz/` to published `antisatori/graphviz`.
- Update `docs/README.md` to reflect any moves.
- Verification: `moon check --deny-warn` per module; examples compile; `check-docs.sh` clean.

Note: module relocations are moved to Stage C, because the three modules now have different statuses (see updated P2).

**Stage B — `CstNode::each` extraction only (1 PR, 1–2 hours).** Addresses ROADMAP #60. Scope collapsed 2026-04-19 after bench evidence resolved #58 and #59.

ROADMAP #58's `Folder` and `TransformFolder` traits are already in `seam/cst_traits.mbt` (see §3 P3 status table). ROADMAP #59's `MutVisitor` is unjustified by measured evidence: closures match or beat traits in the existing benches, and `CstNode::new` (34 µs per `build_tree`) is not hot. That leaves #60:

1. **Promote `walk_children_flat` to public `CstNode::each` (#60).** Extract the repeat-group-aware flattening logic from `syntax_node.mbt:193` as a pub method on `CstNode`. Migrate the 8 internal call sites. No new semantics — visibility change + dedup.

**Defer** `MutVisitor` (#59) until a concrete consumer demonstrates a closure-perf wall via microbenchmark. Do not build speculatively; the ROADMAP caveat already warned against it and measurement confirms.

Rules:
- Do **not** touch parser internals (`reuse_cursor.mbt`) — stateful iteration patterns differ from tree traversal.
- Verification: existing `walk_children_flat` call sites in `syntax_node.mbt` behave identically after migration; `moon test` green for seam; `moon bench --release` on seam shows no regression >5%.

**Stage C — sibling-module rationalization (1 PR per module, as-needed).** Revised 2026-04-19 after investigation — the three modules get three different treatments.
- `cst-transform` → **delete** `transform_cps`+`transform_view` per ROADMAP #62. Confirmed zero external consumers across canopy (grep 2026-04-19: all hits are self-references, documentation mentions, or archived plan notes). The useful methods were ported to `seam/cst_traverse.mbt` on 2026-03-30. Operational follow-ups when the package is removed: (a) update `.claude/settings.json` hook which still runs `cd ../cst-transform && moon check && moon test`; (b) update comment references in `seam/cst_traverse.mbt:3` and `seam/cst_traits.mbt:7` that cite `cst-transform/REPORT.md` — either move `REPORT.md` into `loom/docs/performance/` or inline its findings; (c) update `alga/src/experiment/EXPERIMENT_REPORT.md:10` citation link. None are blockers, but all need the same-PR treatment.
- `egraph` → **move to `experiments/`**. Research-phase fits the label; lambda dep is test-only (confirmed via `egraph/moon.pkg` warning suppression). Add a one-line README note that lambda is imported as a test oracle only.
- `egglog` → **do NOT label "experiment".** Production-oriented with a documented algorithmic contract against `@incr`. Leave at top level as a peer library; add a README section recording: (a) which `@incr` symbols it depends on (`FunctionalRelation`, `Runtime`, `CellId`), (b) which semantic guarantees it relies on (fixpoint-to-stabilization, delta draining via `delta_scan()`), (c) migration strategy if `@incr`'s fixpoint contract ever changes.
- Verification: each module has a README stating its status — `experiment` (egraph), `peer library` (egglog), or `removed` (cst-transform).

**Stage D — deferred.** Zero-copy lexing (#61); codegen for typed views (wait for 4th language); CST-as-primary-source (deferred in unified-parser ADR).

## 7. Verification and observability plan

| Invariant | How verified |
|-----------|--------------|
| Acyclic package deps | `moon.pkg.json` inspection; add `check-deps.sh` mirroring `check-docs.sh` |
| Examples only touch public loom API | Grep for `@loom/core` in `examples/*/src/*.mbt`; fail CI if found |
| `seam` stays language-agnostic | No imports of `loom` / examples in `seam/moon.pkg.json` |
| Traversal traits statically dispatched | `.mbti` inspection; confirm monomorphization |
| No performance regression | `cd examples/lambda && moon bench --release` before/after Stage B |
| Existing tests pass | `moon test` per module touched |
| ADR lifecycle respected | ADRs immutable in place with `Status:` field |

## 8. Functional and non-functional risk analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Traversal traits slower than inline iteration | Medium | Benchmark regression | Measure `moon bench --release`; MoonBit traits monomorphize (static dispatch) |
| Facade deletion breaks downstream imports | Low | Compile errors | `pub using` preservation; migrate examples in same PR |
| Moving experiments breaks CI | Low | CI red | Single-PR moves with path updates |
| Zero-copy pressure re-emerges mid-migration | Low | Distraction | Reject PRs touching `TokenBuffer` during Stage A–C |
| `egglog`/`egraph` have hidden consumers | Medium | Surprise breakage | Inventory grep before moving; document before touching |

No expected degradation in correctness, concurrency, security, or API compatibility.

## 9. Trade-offs and alternatives

**Traversal traits in `seam` vs `loom/core`.** Chose `seam` — traits live with types (avoids orphan-rule workarounds). Cost: `seam` slightly grows. Alternative (loom/core) requires newtype wrappers; rejected.

**Delete facade vs document.** Leaning delete — no invariant to preserve; consumers import `@loom/pipeline` directly. Alternative (keep as stability contract) is defensible; re-evaluate with user input.

**Move experiments vs delete.** Chose move-and-document — reversible. Alternative (delete) is acceptable for `cst-transform`'s `transform_cps`/`transform_view` specifically (ROADMAP #62 authorizes).

**Traversal traits now vs codegen later.** Chose traversal traits — concrete pressure (ROADMAP #58), small surface. Codegen is speculative until a 4th language quantifies pain.

### Related libraries considered for Stage B

Two existing canopy libraries were evaluated as possible implementations for the traversal traits. Neither is a drop-in fit; the verdicts are recorded here so future sessions do not re-litigate them.

**`canopy/lib/zipper` (`dowdiness/zipper`) — partial fit. Reuse the pattern, not the library.**

- *Where it aligns:* McBride's one-hole context is the textbook abstraction for `MutVisitor` (O(1) replace-and-rebuild) and `Finder` (free path reconstruction from the context stack).
- *Where it breaks:* `RoseNode[T]` requires uniform children (`Array[RoseNode[T]]`). `CstNode.children` is `Array[CstElement]` where `CstElement = Token(CstToken) | Node(CstNode)`. Forcing CST into `RoseNode` either wraps tokens (losing kind distinction) or flattens the variant (losing seam's interning and structural-sharing guarantees). Neither is free.
- *Options:* (1) mirror `RoseZipper`'s structure in a new `CstZipper` typed over `CstElement`; (2) generalize `dowdiness/zipper` to support variant children (larger, riskier); (3) skip zippers — `SyntaxNode` already has parent pointers and offsets, which covers most Finder/MutVisitor needs.
- *Default:* option 3. Build a `CstZipper` only if a concrete consumer hits a wall; lib/zipper then serves as a working template, not a dependency.

**`canopy/alga` (`dowdiness/alga`) — wrong layer for CST traversal.**

- *Why it doesn't fit Stage B:* alga is a directed-graph algebra with `Int` vertices and `successors(v) -> Iter[Int]`. CST is a tree of heterogeneous nodes with owning references. Mapping CST into alga requires a node→`Int` indirection and loses tree structure; DFS over the mapped graph gives no more than recursive descent at higher cost.
- *Separate niche for loom-adjacent work:* alga does fit AST-semantic analyses (not CST traversal), and should be remembered when these arise:
  - `let`-binding def-use → `reachable`, `reversed`
  - evaluation order → `toposort`, `topo_levels`
  - recursion detection in multi-expression files → `has_cycle`, `tarjan_scc`
  - future module-import graph → `condensation`
  - scope/shadowing analysis → `dfs_events` with `BackEdge` classification
- *Scope:* these sit in Stage D (deferred) or outside the loom framework entirely (example-specific AST passes). Not a Stage B input.

**General principle.** Reusing a library and reusing a pattern are different operations. When a library's types don't match the consumer's shape, keep the technique and rewrite the code rather than contorting the types to fit.

## 10. Scope definition

**Included:**
- Sibling-module rationalization
- Facade cleanup
- CST traversal trait extraction (ROADMAP #58)

**Explicitly excluded:**
- Parser engine redesign (no pressure)
- CST data-model changes (stable)
- Zero-copy lexing (#61)
- Parser-generation facility (ROADMAP:186 rules out)
- LSP layer (out of scope)
- Plugin/registry for languages (speculative at 3 languages)
- CST-as-primary-source (deferred in unified-parser ADR)
- `incr` internals (separate submodule)
- AST-semantic graph analysis via `dowdiness/alga` (def-use, SCC, toposort) — useful eventually but not CST traversal; see §9 "Related libraries considered"

## 11. Constraints and unknowns

**Hard constraints:**
- MoonBit orphan rule: traits must live where types are, or use newtype wrappers.
- `pub` vs `pub(all)`: cross-package construction needs thought.
- `moon check --deny-warn` in CI.
- ADRs immutable in place; use `Status:` field.
- Submodule workflow: `incr` changes need PR → push → parent update.

**Unknowns closed 2026-04-19 (investigation results summarized above):**
- ✅ `egglog`'s `@incr` dependency: semi-naive Datalog via `@incr.FunctionalRelation`, `@incr.Runtime`, `rt.fixpoint()`. Deep algorithmic coupling, not a hidden internal; see updated §3 P2 and §6 Stage C.
- ✅ `egraph`'s `lambda` dependency: test-only, declared via `-29` warning suppression in `egraph/moon.pkg`; core library is language-agnostic.
- ✅ Neither module is imported outside itself anywhere in the canopy repo (leaf nodes).

**Also closed 2026-04-19 (grep across full canopy tree):**
- ✅ `cst-transform` has zero import consumers across all canopy modules (event-graph-walker, order-tree, lib/*, alga, editor, etc.). The 13 grep hits are self-references, documentation mentions, a `.claude/settings.json` test hook, and archived plan notes — no MoonBit imports.
- ✅ `seam/cst_traverse.mbt` already ports 6 closure methods + `Finder` trait from `cst-transform` (2026-03-30 archive plan). Stage B scope narrows accordingly.

**Also closed 2026-04-19 (bench run `cd seam && moon bench --release`):**
- ✅ #58 `Folder` and `TransformFolder` traits already exist in `seam/cst_traits.mbt:16,30` — I missed this on the first pass. `Finder` confirmed at `cst_traverse.mbt:185`. Only `MutVisitor` remains unimplemented.
- ✅ `CstNode::new` critical-path question: `build_tree with ReuseNode` completes in 34.72 µs for a 50×100 token tree. Not a hot path. ROADMAP #59's own caveat ("only worthwhile if `CstNode::new()` is not on the critical path") resolves against building `MutVisitor`.
- ✅ Closure-vs-trait perf assumption: the "~2× closure overhead" framing in `cst_traverse.mbt:37-39` does not hold for the benchmarked workloads. Closures are at parity or faster. The narrow claim (closures *with captured upvars* specifically) remains untested and should not justify speculative trait work.
- ✅ #60's `walk_children_flat` is private in `syntax_node.mbt:193` with repeat-group flattening semantics; extraction to public `CstNode::each` is the only Stage B deliverable with a clear justification.

**Still open:**
- Whether canopy web demo has near-term requirements that would shift pipeline pressure.

## 12. Recommended next steps

1. Confirm scope with decision-maker: Stage A only / A+B / full A+B+C.
2. Read `egglog`/`egraph` source to close Stage C knowledge gap.
3. If Stage B proceeds: draft `Folder` trait signature; validate via `viz/dot_tree_node.mbt` pilot.

**Recommended first bite:** Stage A+B — real pressure, low risk, reversible.
