# Architecture Restructuring Analysis — 2026-06-20

**Status:** Point-in-time diagnosis. Not an ADR. Not an execution plan. Informs future plans.
**Builds on:** [2026-04-19 diagnosis](2026-04-19-architecture-diagnosis.md) and its [2026-05-08 update](2026-05-08-architecture-status-update.md). Those remain the baseline; this records what has *changed* in the two months since and re-scopes the open questions accordingly.

> **Correction (2026-06-21).** The file-structure census in this doc (`parser.mbt` LOC, `core` and `markdown` LOC/file counts, the §2 co-change table) was measured against a pre-#381 mental model and **not re-`wc`'d at HEAD** — it mis-attributes the parser subsystem's ~1 481-LOC aggregate to the single file `parser.mbt`. Load-bearing numbers are corrected in place below with `[corrected 2026-06-21: …]` markers; the affected *conclusions* (AP3 is already resolved; the §2 co-change table is a pre-#381 historical aggregate) are in the [Correction note](#correction-note--2026-06-21) at the end. The architectural verdicts (CP1, CP3, AP1, AP2, AP5, the dependency rules) are census-independent and **unaffected**.

**Headline:** The parser engine still does not need restructuring — the 2026-04-19 conclusion holds on its real premises (acyclic deps, sealed ownership, no shared mutable state; all re-verified below). What *has* changed is where the system absorbs change: pressure has moved decisively into the **language-authoring layer** (3 → 6 example languages) and into **`loom/src/core`**, which went from "no churn in 30 commits" (April) to **153 changes in the last 250 commits**. The defensible structural moves are narrow: lift the one accreted leaf subsystem (`projection_identity`) out of the engine core, give languages a canonical package shape, and surface — without deciding — that an ADR-documented pattern has now reached its own promotion threshold.

---

## 1. Change pressures driving redesign

Pressures are ranked by evidence strength. Only the first three are *fresh since 2026-05-08*; the rest are explicitly affirmed as **not** pressuring change.

| # | Pressure | Type | Evidence (2026-06-20) |
|---|----------|------|------------------------|
| CP1 | Per-language authoring cost has scaled past the prior deferral trigger | Scalability friction | Languages went 3 → 6 (`lambda, json, markdown, moonbit, graph-dsl, json-settings`). The 2026-04-19 doc deferred typed-view codegen "until a 4th language quantifies pain" — that trigger is now exceeded. `lambda/src/views.mbt` grew 514 → **644 lines** of cast-and-extract. Examples have **no canonical internal shape**: `lambda` is 9 sub-packages; `markdown` is a flat **17-non-test-file / 5 008-LOC** `[corrected 2026-06-21: was "30-file / 4 435-LOC"; re-measured at HEAD — markdown grew since authoring; AP2's qualitative "no canonical shape" is unaffected]` single package. |
| CP2 | `loom/src/core` is the system's accretion point | Boundary / cognitive-load | `core` is **6 974 non-test LOC across 25 source files** `[corrected 2026-06-21: was "14 299 / 32"]` spanning ≥6 unrelated subsystems. Churn: **153 changes / 250 commits** (vs `incremental/` = 5). Grammar combinators (`ParserContext::at_adjacent`, `separated_list`) are defined in **`core/parser_combinators.mbt`** `[corrected 2026-06-21: was "inside the engine file core/parser.mbt"; #279/#381 separated them — see AP3 correction]` — every language that needs a new boundary/recovery primitive grows the `core` package. |
| CP3 | The last-good attachment lifecycle is now duplicated | Duplicated concept (ADR-governed) | `graph-dsl/src/attachment.mbt` (261 LOC) and `json-settings/src/settings_attachment.mbt` (263 LOC) implement a **near-identical** skeleton: a `State` enum + `state()`/`current_result()`/`last_good()`/`apply_edit()`/`set_source()`/`dispose()`. The 2026-05-28 ADR *documented this exact lifecycle as a canonical pattern but deliberately kept it language-owned.* |
| — | Parser-engine correctness / incrementality | **Not pressuring** | `incremental/` churn = 5/250; differential oracle green; no `change-X-broke-Y` evidence in core (see §3). |
| — | CST data model (`seam`) | **Not pressuring** | `seam` is language-agnostic; the two-tree model is stable. Its churn (97) is feature growth (direct queries, group helpers), not structural strain. |
| — | Facade, sibling modules, traversal traits | **Settled** | Closed or shipped by the 2026-05-08 update (graphviz swap, `cst-transform` delete, egraph/egglog peer-library READMEs, `#58` traits). Out of scope here — do not re-open. |

**The single sentence:** the engine is finished infrastructure; the friction is now in *building languages on top of it* and in *the core package having become the junk drawer where shared authoring primitives land*.

---

## 2. Current architecture diagnosis

### Subsystems and ownership

| Subsystem | Owns | Size (non-test) | Churn (250) |
|-----------|------|------------------|-------------|
| `seam/` | `CstNode`, `CstToken`, `SyntaxNode`, `EventBuffer`, traversal, interner, `projection_shape`/`projection_group` | event 1106 + syntax_node 778 + cst_node 448 | 97 (feature) |
| `incr/` (submodule) | Reactive `Input`/`Derived` cells, `Runtime` | n/a | 19 (bumps) |
| `loom/src/core/` | Edit model, diagnostics, lexer infra, **parser engine + combinators**, reuse, **projection-identity** | **6 974 / 25 files** `[corrected 2026-06-21: was 14 299 / 32]` | **153** |
| `loom/src/incremental/` | `ImperativeParser`, damage tracking | sealed | 5 |
| `loom/src/pipeline/` | `Parser[Ast]`; publishes `@incr.Input`/`Derived` | thin | 26 |
| `loom/src/viz/` | CST → Dot renderer | 239 | 6 |
| `loom/src/loom.mbt` | Facade (pure `pub using` re-export) | ~50 | 10 |
| `examples/*` | 6 grammars + their projections | lambda 10 056; markdown 5 008 `[corrected 2026-06-21: was 4 435]`; graph-dsl 2 004; json 1 703; moonbit 1 541; json-settings 432 | **547** |

### Dependency direction (re-verified from `moon.pkg`, 2026-06-20)

```
seam ─┐                       (data + traversal; depends only on quickcheck)
      ├─ loom/core ─┐         core → seam, text_change, pretty
incr ─┘             ├─ loom/incremental → core, seam
                    ├─ loom/pipeline    → core, incremental, seam, incr
                    └─ loom/src (facade) → all of the above
loom/viz → graphviz   (independent)
examples/* → loom (+ seam, incr, pretty)
```

**Acyclic. No import cycles** (confirmed by the 2026-06-08 graph: "Import Cycles: None detected"). Parser state is sealed in `ImperativeParser`; reactive cells are owned by `Parser[Ast]`; **no shared mutable state crosses a package boundary.** The 2026-04-19 ownership conclusion still holds — and it rested on *these* properties, not on "core doesn't change." They have not degraded.

### What the per-file evidence actually shows about `core`

Co-change analysis (`git log --name-only`, how often each `core` file appears in the *same commit* as the engine file `parser.mbt`) — **[corrected 2026-06-21: this table is a pre-#381 historical aggregate.** PR #381 split `parser.mbt` (now 141 LOC) into ~8 `parser_*.mbt` files, so "co-touch `parser.mbt`" reflects the monolith era, not current state; the *reading* (low coupling) still holds, the per-row percentages are historical]:

| File | Commits | Co-touch `parser.mbt` | Reading |
|------|---------|----------------------|---------|
| `reuse_cursor.mbt` | 29 | 16 (55%) | **engine** — inseparable from `parser.mbt` |
| `block_reparse.mbt` | 10 | 6 (60%) | **engine** |
| `diagnostics.mbt` | 17 | 6 (35%) | mostly independent |
| `token_buffer.mbt` | 32 | 7 (22%) | mostly independent (lexing) |
| `projection_identity.mbt` | 7 | 1 (14%) | **independent leaf** |
| `mode_lexer.mbt` | 6 | 0 | fully independent |
| `lex_cursor.mbt` | 3 | 0 | fully independent |

This is the **low-coupling signature**, not a tangled gravity well: the subsystems change on *independent* timelines and do not cross-contaminate. `core` is a cognitive-load problem (one package, many unrelated concerns), **not** a blast-radius problem. That distinction governs the whole redesign (see §3).

---

## 3. Architectural problems

Stated as **confirmed problems**, **design judgments**, and **uncertainties** — kept separate per the project's evidence discipline.

### Confirmed problems (observed, not inferred)

**AP1 — A layering inversion: a downstream-consumer concern lives inside the engine core.**
`core/projection_identity.mbt` (833 LOC: stable-ID realignment, `align_or_allocate`, `compose_projection_identity_edits`) is consumed **only** by the facade re-export and by `graph-dsl` + `json-settings` attachments. Verified: the engine layers (`pipeline/`, `incremental/`) reference it **zero** times, and `projection_identity` references the engine (`ParserContext`/`parse_with`/`TokenBuffer`/`ReuseCursor`) **zero** times — it touches only `@shared_text_change`. It sits in `core` by accretion, not necessity. A pure parsing-engine package should not own editor projection-identity. *This is the one core subsystem the dependency graph proves is misplaced.*

**AP2 — Languages have no canonical package shape, so each reinvents structure.**
`lambda` is decomposed into `token / syntax / lexer / ast / eval / typecheck / rename / callers` packages; `markdown` — the most actively developed example (#355–#377) — is a flat 30-file monolith mixing lexer, parser, IR, mdast export, CommonMark fixtures, and block/inline conversion in one package. A new language author has no reference layout. This is changeability/onboarding friction, not a correctness issue.

### Design judgments (defensible reading of evidence, reasonable people could differ)

**AP3 — Grammar combinators accrete into the engine file.** `[corrected 2026-06-21: this watch-item is already resolved — combinators are in their own file; see below.]`
`ParserContext::at_adjacent`/`separated_list` live in **`core/parser_combinators.mbt`** `[corrected 2026-06-21: was "core/parser.mbt"]`, a dedicated combinator file — **not** the engine file. PR #279 (`separated_list`) and PR #381 ("split parser implementation by responsibility") already separated the grammar-author DSL surface from the engine: `parser.mbt` is now **141 LOC** — **[corrected 2026-06-21:** was "1 474 LOC"; that figure was the ~1 481-LOC sum of all 8 `parser_*.mbt` files mis-attributed to the single file]. MoonBit's orphan rule still pins these methods to `ParserContext`'s package, so they stay in `core` — but they are no longer tangled into the engine file. **Judgment (corrected):** the watch-item is **closed**; the combinator surface is already its own file within `core`.

**AP4 — `core` is a 6-subsystem package.**
Edit model · diagnostics · lexer infra · engine+reuse · projection-identity in one ~7k-LOC unit `[corrected 2026-06-21: was "14k-LOC"]`. Given the §2 low-coupling evidence, a broad split would reduce *navigability* but not *blast radius* — there is no observed "changed X, broke Y." **Judgment:** a full split is largely cosmetic and not currently warranted; only the AP1 extraction is justified by the dependency graph.

### Uncertainties (need a decision-maker, not more analysis)

**AP5 — Has the ADR-documented attachment pattern crossed its promotion threshold?**
The 2026-05-28 ADR keeps the last-good lifecycle language-owned *on purpose* ("keeps Loom's parser API simple; downstream projects decide which semantic documents are safe to publish"). CP3 now shows two near-identical hand-rolled copies. The codebase's repeated rule is "keep language-local until *multiple consumers* prove a shared policy." Two consumers now exist. Whether that meets the bar — versus the ADR's stated reason to stay out of the parser API — is a maintainer call, not a fact this analysis can settle.

### A non-problem (explicitly, to prevent false commonality)

The per-language projection layers are **not** a single duplicated abstraction to unify. Applying "what must I discard to make them the same?": `json/roles_attachment` (70 LOC, read-only span export, no lifecycle), `markdown/markdown_ir` (2 039 LOC, a recursive semantic IR with mdast/Block/rewrite exports), and the stateful attachments (graph-dsl, json-settings) are **three different abstractions**. Only the last pair share structure (AP5). Forcing roles + IR + attachment into one "projection layer" would manufacture commonality that the domain does not have (design-principle 2).

---

## 4. Target architecture

A deliberately **minimal** target: affirm the engine, extract the one misplaced leaf, name a language convention. No new framework abstractions are *introduced*; one is *relocated*.

```
examples/<lang>/   ── canonical shape (AP2): lexer · syntax_kind · grammar
   │                  · cst→ast · projection (convention, not enforced)
   ▼
loom (public facade — unchanged surface)
  pipeline/      Parser[Ast] + Derived cells          ← engine
  incremental/   ImperativeParser                     ← engine
  core/          Edit, Range, Diagnostics, TokenBuffer,
                 ParserContext + combinators, ReuseCursor,
                 recovery, block_reparse              ← engine + author DSL
  projection/    projection_identity (A1, clean leaf);
                 proj_traits trait defs (A2, optional)  ← NEW: consumer layer
  viz/           Dot renderer
   │
   ▼
seam (CstNode/SyntaxNode/EventBuffer + traversal + projection_shape/group)
   │
   ▼
incr (reactive primitives, submodule)
```

**Changes vs current — one proven structural move, one optional, one conventional:**

1. **(AP1) Extract `core/projection_identity.mbt` into a new `loom/src/projection/` package** depending on `seam` + `core`'s data types, never on the engine. This is the move the dependency graph *proves* (verified clean leaf, §3 AP1). Only the facade re-export and the two example imports (`graph-dsl`, `json-settings`) change. It makes the layering inversion structurally impossible to re-introduce: the engine *cannot* depend on projection because projection sits above it.
   - **Note (scope correction):** the `proj_traits` trait *definitions* (`TreeNode`/`Renderable`/`Canonical`) are a **separate, optional** move (A2 in §6), not part of this clean extraction. Unlike `projection_identity`, they are a *broadly-implemented* framework trait — `grep` finds **6 impl files across 3 examples** (`json` ×2, `lambda` ×3, `markdown` ×1) referencing them as `@core.TreeNode`/`@loomcore.Renderable` **directly, not via the facade**. The new boundary rule forbids a `core` re-export, so relocating the defs breaks all 6 sites until repointed. AP1's inversion argument does not cover them; their move is a cohesion judgment with its own counted cost.
2. **(AP2) Adopt a documented canonical language-package layout** and bring `markdown` onto it (split the monolith along its existing file groupings: lexer / parser / IR / export). Convention + reference, not a framework feature.
3. **(AP5) No code change** — record the threshold question for the maintainer (§6 Stage C is a *decision gate*, not an implementation step).

Everything else stays. The engine is not touched.

---

## 5. Dependency and boundary rules

| Rule | Status | Rationale |
|------|--------|-----------|
| `seam` imports nothing above it | holds | Keeps CST model reusable |
| `loom/core` may depend on `seam`, not on `incremental`/`pipeline` | holds | Layer direction |
| `loom/pipeline` may depend on `incremental`, `core`, `incr` | holds | — |
| **`loom/projection` may depend on `core` data types + `seam`; the engine (`core` parser, `incremental`, `pipeline`) MUST NOT depend on `projection`** | **NEW** | Encodes AP1; prevents the inversion from recurring |
| Examples use the public facade, not `@loom/core` internals | holds (visibility) | — |
| Combinators on `ParserContext` stay in `core` | holds (orphan rule) | AP3 — a constraint, not a goal |

**Invariant to add to CI:** a `check-deps.sh` (mirroring `check-docs.sh`) that fails if any engine package imports `loom/projection`, and if any `seam/moon.pkg` imports `loom`/examples.

---

## 6. Migration strategy (staged, reversible)

Each stage ships independently and is individually revertible. Ordered by value-per-risk.

**Stage A1 — Extract `projection_identity` into `loom/projection` (1 PR; ~half a day). Low risk.**
- Create `loom/src/projection/`; `git mv projection_identity.mbt`; add `moon.pkg` importing `seam` + `core`.
- Repoint the facade re-export (`loom/src/loom.mbt`) and the two example imports (`graph-dsl`, `json-settings`).
- **Blast radius (verified):** facade + 2 example files. `projection_identity` references only `@shared_text_change`; the engine references it zero times; it does not depend on `proj_traits`.
- **Stays the same:** every public symbol (re-exported through the facade), all engine code, all tests, every trait impl site.
- **Correctness:** `moon check --deny-warn` + `moon test` per touched module; `find-references` re-confirms no engine consumer; `moon info` → `.mbti` diff shows relocation only; `cd examples/lambda && moon bench --release` shows no regression (lambda doesn't use projection — a deliberate null-check).
- **Reversible:** a `git mv` back if anything surprises.

**Stage A2 — Relocate the `proj_traits` trait defs (optional; separate PR; ~1 day). Medium-low risk, wider edit count.**
- *Decide first whether to do this at all.* AP1 does not prove `proj_traits` is misplaced; the move is a cohesion gain (traits live beside `projection_identity` in the consumer layer) weighed against editing every impl site.
- If done: `git mv proj_traits.mbt` into `loom/projection`; repoint **6 impl files across 3 examples** (`json/src/proj_traits.mbt`, `json/src/proj_traits_canonical.mbt`, `lambda/src/ast/proj_traits.mbt`, `lambda/src/ast/proj_traits_canonical.mbt`, `lambda/src/ast/proj_traits_mechanical.mbt`, `markdown/src/proj_traits.mbt`) from `@core.TreeNode`/`@loomcore.Renderable` to `@projection.*`. A `core` re-export is **not** an option — the new boundary rule (§5) forbids the engine depending on `projection`.
- **Stays the same:** trait semantics; `viz` (it uses its own `DotNode` trait, not these — confirmed).
- **Correctness:** `moon check --deny-warn` + `moon test` for all 3 examples; `.mbti` diff confirms only import-path changes at impl sites.
- **Reversible:** yes, but the 6-site repoint makes it heavier to land/revert than A1; keep it a distinct PR so A1's clean win isn't held hostage to it.

**Stage B — Canonical language layout + markdown split (1–2 PRs; 1–2 days). Medium risk, contained to one example.**
- Write `docs/development/language-package-layout.md` (extract the layout `lambda` already approximates).
- Split `examples/markdown/src` along existing seams (lexer / parser / IR / export). Move-only; no behavior change. Use property/differential tests as the pin (markdown already has `incremental_test`, `mdast_fixture_parity_test`, `commonmark_html_fixture_test`).
- **Stays the same:** markdown's external behavior and the framework. **Correctness:** the existing markdown fixture + incremental suites must be byte-identical green before/after.
- **Risk control:** this is the riskiest stage *only because markdown churns daily*; sequence it for a quiet window and rebase carefully, or defer until the current MarkdownIR work (#355+) settles.

**Stage C — Decision gate for AP5 (no code; a `decisions-needed.md` entry + maintainer call).**
- Present CP3's two-consumer evidence against the 2026-05-28 ADR's stated reasons. If the maintainer promotes: a *new* ADR supersedes (don't edit the immutable one), and the lifecycle skeleton becomes an **optional** helper in `loom/projection`, parameterized over the domain doc type + a parse function — examples opt in, the parser API is untouched (honoring the ADR's invariant). If not: record "language-local stands; revisit at consumer #3."

**Explicitly not staged:** any engine change, the broad `core` split (AP4), and any unification of roles/IR/attachment (the non-problem in §3).

---

## 7. Verification and observability plan

| Invariant | How verified |
|-----------|--------------|
| Acyclic package deps after extraction | new `check-deps.sh`; `moon.pkg` inspection |
| Engine never depends on `projection` | grep engine `moon.pkg` for `loom/projection` → must be empty (CI) |
| Public API unchanged by A1 | `moon info` → `git diff loom/src/**/*.mbti` shows relocation only, no signature change |
| `projection_identity` is a true leaf (A1) | `find-references` on `ProjectionIdentity*`/`align_or_allocate`/`compose_projection*` shows only facade + 2 examples (re-confirm post-move) |
| A2 touches every impl site, no semantics drift | `grep -rln 'impl @\(core\|loomcore\)\.\(TreeNode\|Renderable\|Canonical\)'` = 6 files; `.mbti` diff shows import-path changes only |
| markdown behavior preserved (Stage B) | existing `commonmark_html_fixture` + `mdast_fixture_parity` + `incremental_test` green, unchanged |
| No perf regression | `cd examples/lambda && moon bench --release` and `cd examples/markdown && moon bench --release` before/after |
| ADR lifecycle respected (AP5) | immutable-in-place; promotion = new superseding ADR |

---

## 8. Functional and non-functional risk analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| A1 breaks a hidden `projection_identity` consumer | Low | Compile error | `find-references` inventory run (only facade + 2 examples); facade re-export preserves call sites |
| A2 misses a `proj_traits` impl site | Low–Med | Compile error | The grep enumerates all 6 sites up front; no facade fallback (boundary rule), so the compiler catches any miss immediately |
| Either stage changes the `.mbti` surface inadvertently | Low | API regression | `moon info` diff gate; symbols re-exported (A1) / re-imported not renamed (A2) |
| markdown split (B) collides with in-flight MarkdownIR work | **Medium** | Rebase churn / merge pain | Sequence for a quiet window or defer past #355+; move-only discipline |
| Promoting the attachment helper (C) over-generalizes prematurely | Medium | Speculative abstraction | Gate on maintainer decision; keep it *optional* and language-opt-in; honor the ADR's "parser API unchanged" |
| Treating low-coupling `core` as a split mandate | (avoided) | Wasted multi-day migration | §3 AP4 explicitly demotes this to non-action |

No expected degradation to **correctness** (move-only + fixture pins), **performance** (bench gates; projection isn't on the parse path), **concurrency** (no shared mutable state introduced), **error handling/observability** (diagnostics untouched), **security**, or **API compatibility** (facade preserves the surface).

---

## 9. Trade-offs and alternatives

- **Extract projection vs leave it in `core`.** Chose extract: the dependency graph *proves* it is a misplaced leaf (AP1), and a new boundary rule prevents recurrence. Cost: one more package. Alternative (leave it) keeps the inversion latent — every future reader must re-derive that the engine doesn't use it. Rejected.
- **Narrow extraction vs full `core` split.** Chose narrow. The §2 co-change data shows independent churn = low coupling; a 5-way split buys navigability but not blast-radius reduction, and the task forbids architecture-for-its-own-sake. Re-evaluate only if a real `changed-X-broke-Y` appears.
- **Convention vs codegen for per-language boilerplate (CP1/AP2).** Chose convention + targeted split first. Codegen for typed views (`views.mbt`, 644 LOC) is now past its "4th language" trigger, but it is lambda-specific (markdown uses an IR instead), so a universal generator is not yet justified. Quantify the *shared* boilerplate across ≥3 languages before building tooling.
- **Promote attachment helper now vs gate it (AP5).** Chose gate. An accepted ADR deliberately kept it language-local for a stated reason; reversing it is a decision with a real downside (parser-API surface growth), not a mechanical cleanup. Surface the evidence; let the maintainer rule.

---

## 10. Scope definition

**Included:** extracting `projection_identity` into `loom/projection` (AP1, the proven clean leaf — Stage A1); *optionally* relocating the `proj_traits` trait defs (Stage A2, a separate cohesion judgment scoped at 6 impl sites); a documented language-package layout + the markdown monolith split (AP2); a decision gate for the attachment-lifecycle promotion question (AP5); a `check-deps.sh` boundary guard.

**Explicitly excluded:**
- Parser-engine redesign — no coupling/breakage evidence; correctness verified.
- Broad `core` split (AP4) — low coupling makes it cosmetic.
- Relocating combinators off `ParserContext` (AP3) — orphan-rule-pinned; not a goal.
- Unifying roles / markdown-IR / attachments into one "projection layer" — false commonality (§3 non-problem).
- Facade deletion, `experiments/`, egraph/egglog moves, traversal traits — settled by the 2026-05-08 update; not re-opened.
- `incr` internals, LSP, evaluation/typecheck, parser generation — out of framework scope (ROADMAP §"does NOT include").
- Typed-view codegen — past its trigger but not yet shown to be *shared* across languages.

---

## 11. Constraints and unknowns

**Hard constraints:**
- MoonBit orphan rule pins `ParserContext` methods (combinators) to `core` (AP3).
- `pub` vs `pub(all)`: cross-package construction of relocated projection types must be re-checked after the move (named constructors or `pub(all)` as needed).
- `moon check --deny-warn` in CI; `.mbti` regenerated via `moon info`; ADRs immutable in place.
- Submodule workflow for any `incr` touch (none planned here).

**Unknowns (state them; don't speculate past them):**
- *Whether AP5 should promote* — deferred to the maintainer (Stage C), not resolvable by analysis.
- *The true shared-boilerplate surface across languages* — `views.mbt` is lambda-specific; markdown uses an IR. Quantifying the *common* authoring cost across ≥3 languages needs a dedicated read pass before any tooling decision (CP1). Not done here.
- *Whether `seam`'s `projection_shape`/`projection_group` belong with the new `loom/projection` package* — they live in `seam` for orphan-rule reasons (they impl over `SyntaxNode`). Left in place; flag for revisit if `loom/projection` grows.

**Where understanding stops:** I have not read the full bodies of the parser subsystem (`parser.mbt` 141 LOC + ~8 `parser_*.mbt`, ~1 481 LOC total `[corrected 2026-06-21: was "core/parser.mbt (1 474 LOC)"]`) or `seam/event.mbt` (1 106 LOC); the diagnosis treats the engine as a black box on the strength of its stability evidence (frozen `incremental/`, green differential oracle, independent core churn). That is sufficient to conclude "do not restructure the engine" but **not** sufficient to propose any engine-internal change — and none is proposed.

---

## 12. Recommended next steps

1. **Confirm scope** with the decision-maker: A1 only / A1+B / A1+A2+B / +C-gate. Recommended first bite: **Stage A1** — the dependency-graph-proven leaf, single PR, reversible, zero engine risk.
2. **Stage A1:** create `loom/src/projection/`, `git mv projection_identity.mbt`, repoint facade + two example imports, add `check-deps.sh`. Verify with the §7 gates. Treat A2 (`proj_traits`) as a follow-up decision, not a bundled step.
3. **Before Stage B:** check whether MarkdownIR work (#355+) has settled; if not, defer the markdown split to avoid rebase collisions.
4. **Stage C (anytime):** add a `decisions-needed.md` entry stating CP3's two-consumer evidence vs the 2026-05-28 ADR's rationale, for a maintainer ruling.
5. **Quantify CP1 separately:** a focused pass measuring the *shared* (not lambda-only) authoring boilerplate across lambda/json/markdown before any codegen or scaffold-tooling proposal.

---

## Correction note — 2026-06-21

A HEAD re-measurement (post-review) found the **file-structure census** in this doc was stale. Numbers are corrected in place above with `[corrected 2026-06-21: …]`; this note records the *cause* and the *conclusion-level* corrections.

**Measured at HEAD (`loom/src/core`, `examples/markdown/src`):**

| Doc said | HEAD | 
|----------|------|
| `parser.mbt` 1 474 LOC | **141** (the file); `parser*.mbt` sum = **1 481 / 8 files** |
| combinators in `core/parser.mbt` | in **`core/parser_combinators.mbt`** (+ `parser_context_access.mbt`) |
| `core` 14 299 LOC / 32 files | **6 974 non-test LOC / 25 files** |
| markdown 4 435 LOC / 30-file | **5 008 non-test LOC / 17 non-test files** (single `moon.pkg`) |

**Root cause (evidenced, not inferred).** The `1 474` figure is the **parser-subsystem aggregate (~1 481 LOC across 8 `parser_*.mbt`) mis-attributed to the single file `parser.mbt`**, reflecting a pre-#381 mental model and never re-`wc`'d at HEAD. `git log -- parser.mbt` shows `8fae3b6 refactor(core): split parser implementation by responsibility (#381)`, which is an ancestor of this branch — so `parser.mbt` was *already* split when the doc was written. (A *baseline-inheritance* hypothesis — that the figures were carried verbatim from the 2026-04-19 / 05-08 docs — was **tested and refuted**: `grep` finds neither `1 474` nor `14 299` in those docs. The inheritance mechanism does exist for *other* numbers — `views.mbt 514`→`644` was correctly refreshed from the baseline — just not these.)

**Conclusion-level corrections (stated to corrected form):**
- **AP3 — resolved, not a watch-item.** Combinators were separated from the engine file by #279/#381; `parser.mbt` is 141 LOC. The "engine file is also the DSL surface" tension no longer exists at the file level (orphan rule still keeps the methods in the `core` *package*).
- **§2 co-change table — pre-#381 historical.** It is a `git log` aggregate over 250 commits that span the #381 split; "co-touch `parser.mbt`" measures the monolith era. The *reading* (low intra-`core` coupling → AP4 split is cosmetic) is unaffected; the per-row percentages should be re-measured against current `parser.mbt` (141 LOC) or read as historical.
- **AP2 — holds; markdown grew.** The flat-monolith / no-canonical-shape claim is qualitative and confirmed at HEAD (single `moon.pkg`, lexer+parser+IR+export co-located); only the LOC count moved (4 435 → 5 008), and #381 is core-only so it does not touch markdown.

**Unaffected (census-independent, re-confirmed):** CP1 (with `views.mbt 514→644` correctly refreshed), CP3 (attachment duplication), AP1 (`projection_identity` is an engine-zero-reference leaf), AP5, the dependency/boundary rules, and the import-surface boundary basis (`@core.TokenBuffer` 14× / `LexCursor` 8× match HEAD exactly).
