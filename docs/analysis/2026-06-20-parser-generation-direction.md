# Parser-generation direction for loom — recommendation + de-risk spike

**Status:** Design / recommendation (no decision committed). The only thing this
doc commits to is running the de-risk **spike** (§5); everything downstream of
the spike is evidence-gated.

**Date:** 2026-06-20

**Question being answered:** How should loom evolve to be "morm-style
parser-generation-friendly," given that ROADMAP non-goal #1 currently excludes
parser generation in favour of hand-written recursive descent?

---

## 1. Scope

The request "make loom morm-style parser-generation-friendly" decomposes into
**two layers** that must be answered separately:

- **Layer 1 — projection/integration plumbing.** The mechanical glue every
  language re-writes (`SyntaxKind`, views, fold, print, reconcile, projection
  conversion). Already designed as **loomgen** (morm-style codegen), approved
  2026-03-20, never built. (Design lives in the parent canopy repo:
  `docs/design/07-loomgen-design.md`.)
- **Layer 2 — the parser/grammar itself.** The hand-written recursive-descent
  parser that drives loom's incremental machinery. This is the layer ROADMAP
  non-goal #1 protects.

The two layers have very different risk profiles and must not be conflated.

## 2. References analysed

- **morm** (`oboard/morm`, MoonBit ORM). Annotate real types → read source via
  `moonbitlang/parser` → emit `.g.mbt` via `pre-build`. No runtime reflection;
  escape hatches everywhere. The proven pattern loomgen copies.
- **loomgen** (approved, unbuilt). morm applied to loom. Source of truth =
  annotated `Token` + `Term` enums → ~1,100–1,200 lines of generated plumbing.
  Design doc line 305: it explicitly does **not** generate the parser
  (`LanguageSpec`/`Grammar`/`parse_root`/`tokenize` stay hand-written).
- **monogram** (`johnsoncodehk/monogram`, TS). Grammar-as-data. An ergonomic
  authoring API lowers to a normalised `RuleExpr` IR. Precedence is **data**
  (Pratt: `left`/`right`/`none` + `op`/`prefix`/`postfix`), so there are no
  left-recursive rules. The grammar is **both interpreted and emitted**, kept
  equivalent by a parity gate. It is incremental with a formal "total parsing"
  contract: after any edit, tree + errors are **byte-identical to a fresh
  parse** (`TOTAL-PARSING.md`). Rule = frame = reuse window.

**Synthesis.** monogram is an existence proof that grammar-as-data can be
incremental *and* dissolve the two reasons loom's non-goal cites: (1) precedence
is data (Pratt, no left recursion); (2) reuse checkpoints are automatic because
every named rule is a frame and therefore a reuse window.

## 3. Verified findings (loom, live-checked 2026-06-20)

1. **`ParserContext` is a rich execution layer** — ≈43 public methods (`.mbti`
   count) including per-node reuse (`try_reuse_repeat_group`, `set_reuse_cursor`,
   `checkpoint`/`mark`/`restore`), node-building (`node`, `wrap_at`,
   `node_with_recovery`, `emit_token`), cursor (`at`, `at_adjacent`, `peek*`),
   and recovery (`skip_until_balanced`, `emit_error_placeholder`,
   `report_expected`). Combinators live in `loom/src/core/parser_combinators.mbt`
   (`separated_list`, …). **Reuse is already per-node.**
2. **The bulk of lambda's hand-written recursive descent is
   `examples/lambda/src/cst_parser.mbt` = 814 lines** (with smaller parser-related
   siblings: `parser.mbt` 32, `typed_parser.mbt` 74); its `grammar.mbt` is 31
   lines. `cst_parser.mbt` is the CST-producing RD artifact a grammar-as-data
   interpreter would replace — "*the* parser" is shorthand for this bulk, not a
   claim that it is the only parser file.
3. **Plumbing is ~1,200 lines per language today** (`views.mbt` 644 +
   `syntax_kind.mbt` 195 + `proj_traits*` ~200 + `dot_node.mbt` 123 + parts of
   `term_convert`/`cst_convert`). The loomgen estimate still holds, arguably grew.
4. **The existing differential oracle** (`loom/src/test_support.mbt:11`,
   `assert_incremental_edit_matches_full_parse`) compares
   `incremental.syntax.cst_node()` vs `full_cst` via `@core.tree_diff` plus
   `diagnostics.equal` — i.e. **CST + diagnostics, same-parser
   incremental-vs-fresh.** Deliberately syntax-only so AST folding cannot mask
   CST/diagnostic divergence. It does **not** check Term, projection identity,
   reconcile, or last-good.
5. **`loom/src/core/projection_identity.mbt` has zero `@incr.` call sites.** It is
   a **pure, beside-the-graph** helper (`ProjectionIdentityTracker[Id]`,
   `realign_projection_identities(baseline, next_leaves, edit)`,
   `commit_success`), driven imperatively by consumers (canopy, moondsp).
6. **The pipeline (`loom/src/pipeline/parser.mbt`) uses plain `@incr.Derived`**
   for source/syntax/ast/diagnostics — **not** `AcceptedDerived` — and last-good
   is not wired into it.
7. **incr 0.9.0 shipped `AcceptedDerived[V, E]`** — an engine-level last-good
   primitive: an `Err(e)` candidate **retains** the prior accepted value while
   the current channel still reports the error. **`BackdateEq` is now a
   first-class acceptance tier** (`#232` — verified via the incr git-log commit
   subject `24a87b0`; note the `[0.9.0]` CHANGELOG itself cites only `#233`):
   `accepted_memo` gates acceptance by *revision identity* for non-`Eq` values
   carrying a `Revision`. `#233` fixed a silent-freshness bug in the watched fold
   under dynamic diamond dependencies.
   **loom does not consume `AcceptedDerived` yet** (it hand-rolls last-good in
   `projection_identity.mbt`).

## 4. Recommendation

### 4.1 The literal question, answered precisely

- **loomgen plumbing codegen = a real target. Commit to it** — *with two
  conditions from the now-completed Layer-1 pass (§4.5):* fix the **L1-A** RawKind
  registry/idempotency bug in the loomgen design, and **re-baseline** the
  ≈1,200-line payoff on current (not textbook) lambda, since judgment-heavy views
  (L1-B) resist codegen. Proven pattern, inspectable output, behaviour verified by
  existing tests — but the structural majority being mechanical is now a *measured*
  claim with named exceptions, not an assumption. *Committing to loomgen as a target is separate from
  its build order:* per §4.4 its build waits for the spike-derived IR contract so
  its annotation schema converges toward the grammar IR rather than diverging.
- **Grammar-as-data interpreter (replacing the 814-line hand parser) = a
  hypothesis, not yet a target.** It graduates to a target only after the spike
  (§5) validates it for loom's projectional case.

*Why the asymmetric treatment (Principle 1 — problem first).* loomgen attacks a
sharp, present pain: ≈1,200 lines of mechanical glue per language. B's motivation
is real but softer — it is the keystone of the single-source ideal (§4.2) that
eliminates the dual-source debt, and it lowers new-language authoring cost — but
no current capability is *blocked* by hand-written RD the way plumbing is blocked
by boilerplate. That thinner, less-certain payoff is precisely why B is
spike-gated while loomgen is committed: you de-risk a direction before investing
when its motive is feasibility-plus-elegance rather than acute pain.

Unpacking B's motive into its three legs — **robust**, **easier to author**,
**reusable across languages** — they have *different* evidential status. *Robust*
is already backed: the recovery machinery (`node_with_recovery`,
`skip_until_balanced`, `emit_error_placeholder`, diagnostics, per-node reuse)
lives on `ParserContext`, and the §4.4-step-4 facade inherits it wholesale — "a
robust parser for free" rests on verified API surface. *Easier-to-author* and
*reusable* are **not** backed by anything yet; they are the legs the spike's
ergonomics gate (§5.6) must measure, because they — not safety — are the actual
reason to want B.

### 4.2 The first-principles ideal

**One annotated grammar value as the single source of truth**, carrying both
**syntax** (tokens, rules, precedence) and **projection semantics** (leaf /
transparent / error-term / placeholder / print-fold templates), from which the
AST/Term type, the parser, and all plumbing are **derived**. This fuses monogram
(grammar → parser + types) with morm/loomgen (annotations → plumbing).

### 4.3 The source-of-truth fork (the one real first-principles tension)

- loomgen-as-designed makes the annotated **Term enum** the source and derives
  plumbing *from the AST type* (AST → plumbing).
- The ideal makes the **grammar** the source and derives the AST *from the
  grammar* (grammar → AST → plumbing).

These are **opposite arrows.** Running both yields **two sources of truth** that
must be kept in agreement = dual-source debt. The grammar is the more
fundamental artifact (the AST shape is a *consequence* of grammar structure), so
the ideal points the arrow grammar-first.

### 4.4 Recommended path: C → derive minimal IR contract → A

1. **(C) Spike-gated decision first** (§5). Buy the decisive information before
   committing build order, because the source-of-truth fork hinges on whether
   grammar-as-data survives loom's projectional layer — an empirical question.
2. **Derive a minimal IR contract from the spike.** Do **not** ship loomgen's
   annotation schema before the grammar IR proves its projection semantics, or
   the "forward-compatible subset" becomes legacy schema you must preserve
   (Codex finding 2).
3. **(A) Build loomgen against that contract.** Its annotation schema designed as
   a subset of the eventual grammar IR, so the dual-source period is *intended* to
   converge rather than diverge. Convergence is **contingent on the IR-first
   sequencing of step 2** — it is not guaranteed by subset-design alone: a
   spike-evolved IR can still drift the "subset," and step 2 (do not ship the
   schema before the IR proves its projection semantics) is the only guard that
   keeps the subset tracking the IR rather than fossilising against it.
4. The interpreter, if it graduates, is a **facade over the verified
   `ParserContext` primitives + a new Pratt sub-engine** — not a from-scratch
   reuse engine. **Interpret-now / emit-later** stay two backends over one IR
   (monogram's proof), the emitter deferred behind a benchmark.

### 4.5 Layer-1 (loomgen) adversarial pass — verdict

Done 2026-06-20, reading the loomgen design + real `syntax_kind.mbt` + `views.mbt`
(≈640 lines). **loomgen survives as a target, but with one correctness bug in its
design and one payoff caveat — and Layer 1 carries the *same* load-bearing risk as
Layer 2.** (This pass closes the §8 review-asymmetry: the committed target is no
longer unreviewed.)

**L1-A — correctness bug: RawKind numbering is a stability registry, not a
mechanical sequence.** `syntax_kind.mbt`'s `to_raw` is append-only with preserved
gaps: `FnKeyword => 43` and `FatArrowToken => 44` are appended despite their
mid-enum positions; raw `24` and `26` are skipped (`LetKeyword 23 → EqToken 25 →
LetDef 27`); comments hand-annotate "NEW:" / "(raw 37)". Raw values are an
**identity contract** (CstNode interning/reuse compare them). But the loomgen
design (`07-loomgen-design.md:381`) promises "*Stable ordering, sequential
`to_raw` integers, never reads `.g.mbt` as input*." These collide: a sequential
regenerator renumbers existing kinds on any `Term`-enum edit, breaking RawKind
identity — actively undoing the hand-discipline the gaps/comments encode.
Preserving identity requires a persistent kind→raw registry — a legitimate
**second source of truth** the annotation schema lacks and the "never reads
`.g.mbt`" rule forbids. A latent bug in the loomgen design, independent of the
parser-gen direction. **Highest-priority follow-up: fix it in the loomgen design
doc.**

**L1-B — escape-hatch growth, symmetric to Layer 2's sprawl.** views.mbt is
mechanical for the textbook core (`AppExpr`, `BinaryExpr`, `IfExpr`, `ParenExpr`,
`VarRef`, `IntLiteral` — all `child(n)`/`cast`/`AstView`). But every feature
*beyond* the core grew judgment a closed DSL cannot express:
`LambdaExprView::params()` (custom filter + single-token fallback, `:78`),
`body()`/`LetDefView::init()` (exclusion predicates "first child that is *not*
ParamList/TypeAnnot", `:91`/`:483`), and `TypeAnnotView::to_type()` +
`cst_to_type()` (recursive semantic lowering CST→`@typecheck.Type`, importing
`@typecheck` — a dependency the design's views.g.mbt import table excludes,
`:621`/`:629`). The design admits ~500 hand-crafted lines
(`07-loomgen-design.md:541`); the verified finding is that this residue **grows
with language maturity and concentrates the hardest judgment** (semantic
lowering), so "~1,200 → ~50 annotations" is a textbook-core figure, not the
steady-state. **Re-baseline the payoff on current lambda before relying on it.**

**Synthesis — the real B2 payoff.** Layer 1 and Layer 2 are not "committed-safe vs
hypothesis-risky"; they are the *same bet at two layers* — *can the declarative
model cover real, evolving languages, or does judgment leak into escape hatches?*
views.mbt is Layer 1's escape-hatch sprawl, the mirror of §8's Layer 2 sprawl. So
the escape-hatch budget (§5.6 **E2**) must be measured across **both** layers, and
§4.4's "one IR, derive contract first" is reinforced.

**morm shape (Codex Q3) — half-right.** The *annotation→codegen mechanism* is
morm-proven, but morm's *domain shape* is not loom's: morm maps flat `Record`
structs (field→column); loom maps recursive `Variant` enums with projection/
identity layers and a RawKind registry that have no morm equivalent. The design
concedes this (`07-loomgen-design.md:421`: "new ground … written from scratch
rather than adapted from morm").

## 5. The de-risk spike

### 5.1 What it must establish

That grammar-as-data parser **B** is a drop-in for hand parser **A** on lambda,
with no downstream churn — validated end-to-end through the projectional layer,
not just precedence (monogram already proved precedence; loom's novel risk is
projection/identity).

**Scope caveat (what the spike does *not* retire).** A lambda-only spike retires
the *mechanism* risk (can grammar-as-data drive loom's reuse machinery?) and the
*oracle-methodology* risk (can we even detect churn?). It does **not** retire the
§8 escape-hatch-sprawl risk, which lives in the genuinely projectional/CRDT
languages, not in lambda. The premise that lambda's projectional behaviour
predicts theirs is *asserted, not proven*; a second, more projectional language
is a required follow-up gate before B graduates from hypothesis to target.

**Two distinct jobs — do not conflate them.** D1/D2 (§5.2) prove **safety** (B is
a drop-in for A with no downstream churn). But B's *motivation* is **ergonomics**
(§4.1: easier authoring + reuse), an orthogonal axis safety does not touch. The
spike must therefore *also* measure ergonomics (§5.6); a spike that proves only
safety leaves the actual reason-to-want-B unvalidated.

### 5.2 The oracle

Codex flagged the load-bearing risk as: a grammar IR can pass parser parity yet
**churn stable IDs / authoring caches** by changing placeholder placement,
transparent spans, error-node ownership, or list grouping.

**Where churn can enter (root-cause framing — corrected after round-2 review).**
The Term fold is deterministic and the projection-leaf sequence is extracted from
the CST, so a *changed CST shape* is the only place new divergence can originate.
**But stable IDs are *not* a pure function of the CST.**
`realign_projection_identities(baseline, next_source, next_leaves, allocate,
edit?)` (`loom/src/core/projection_identity.mbt:631`) and
`ProjectionStringIdAllocator` — which carries `used`/`counters` state and
seeds-then-skips prior-baseline IDs (`:531`, `:576`) — make the ID mapping
**path-dependent** on the baseline, the accumulated allocator state, and the edit
history. Identical CSTs yield identical IDs *only when* the baseline, allocator
seeding, and edit sequence are also identical — which the spike can hold fixed
across A and B, but must not assume away.

So CST parity is **necessary** for no-churn and is the only origin of divergence,
but it is **not** a license to skip the downstream check: the spike verifies the
downstream property empirically rather than by an inductive argument with subtle
preconditions. Three checks, all running the same edit sequence through A and B:

- **D1 — internal consistency (reuse existing infra).** Run
  `assert_incremental_edit_matches_full_parse` on parser B. Proves B is itself
  incrementally correct (B-incremental == B-fresh). Zero new code.
- **D2a — CST + diagnostics parity.** Assert `@core.tree_diff(A_cst, B_cst)` is
  empty (structural identity, *up to hash collisions* — `loom/src/core/diff.mbt`)
  **and** `A_diagnostics.equal(B_diagnostics)` at **every step.** Catches the
  root-cause divergence (the four churn cases are all CST-shape facts).
- **D2b — stable-ID parity (do *not* skip).** Drive the *existing pure*
  `ProjectionIdentityTracker` + `ProjectionStringIdAllocator` for both A and B,
  identically seeded from the same initial baseline, over the same edit sequence;
  assert the emitted stable-ID sequence is identical at every step. This is what
  actually proves "no last-good / authoring-cache churn," because IDs are
  path-dependent and `tree_diff` does not compare the `ProjectionLeaf` fields the
  tracker matches on. D2b uses the existing pure helper — it does **not** require
  the `AcceptedDerived` migration (§5.4).

**The precise invariant (do not weaken it).** Stable IDs and last-good are pure
functions of the *(CST/leaf sequence, edit sequence, source sequence)* — not of
any single CST. (`realign_projection_identities` takes `next_source` and falls
back to a source diff when no `edit` is supplied; and `ProjectionIdentityTracker`
**composes** pending edits across malformed intermediate inputs via
`compose_projection_identity_edits`, so last-good depends on the composed edit
history *across invalid states*, not just the latest tree.) D2's step-by-step
shared inputs (same source + edit sequence, same seeding fed to both A and B) are
exactly what reproduce that function identically. So D2 must stay
**step-by-step**: collapsing it to a single final-CST snapshot comparison would
silently lose history-dependent divergence — an ID churn that manifests only
across the edit path (especially across malformed intermediates), not in the
final tree.

### 5.3 The central design fork — the equivalence bar

- **(i) Structurally identical to A** (`tree_diff`-empty CST + equal diagnostics)
  → drop-in, zero downstream churn, but B must replicate A's exact
  recovery/wrapping quirks. Hardest; safest migration.
- **(ii) Internally-consistent-but-different** → B may produce a different valid
  CST; accept a one-time global re-baseline at switchover (a version migration),
  require D1 thereafter. Easier; one-time churn cost.

**Decision: the spike *targets* (i) and treats every divergence as a finding.**
Not because (i) is the final migration bar, but because it is the most
informative experiment — if B hits structural + ID parity on lambda, every
weaker property follows for free; if it cannot, the precise divergence shows exactly
where grammar-as-data's model parts ways from hand-RD, which is what the spike
exists to learn. The (i)-vs-(ii) *migration* decision is then made **with** that
evidence, not before it.

**Stop condition (must be set in the execution plan — §9).** "All divergences are
findings" needs a terminus, or the (i)-target chase never ends. The plan must
define a threshold separating *grammar-as-data is the wrong model for loom* from
*B merely hasn't replicated A's quirks yet* — e.g. if a divergence is a
faithfully-reproducible recovery/wrapping quirk, the model is sound and the
residual work is replication; if any divergence is a structural shape loom's
reuse/identity layer **cannot** express, stop and report unsuitable.

### 5.4 Migration verdict: `projection_identity` → `AcceptedDerived`

**Neither a precondition nor a parallel track — an independent, deferred one.**
The spike *does* run `projection_identity` (D2b), but it runs the **existing pure
helper**, which does not require the `AcceptedDerived` migration. The migration
would only change *where* last-good lives — "*promote it from a pure
caller-driven helper into the reactive pipeline as an `AcceptedDerived` cell*", an
architectural change to the pipeline — not the leaf→ID mapping D2b checks. So the
migration does not gate the spike. Do not churn pipeline architecture for a parser
direction that is not yet validated; sequence it after the spike, independently.
(When it does happen, exercise the dynamic/diamond dependency case, since that
path was only stabilised at incr 0.9.0 via #233.)

### 5.5 Scope

lambda, a minimal grammar-IR slice chosen to hit the churn-prone cases:

- a node-with-children (`Let` / `Abs`),
- a `separated_list` (list grouping),
- a Pratt operator (`App` / `Bop` precedence),
- a deliberate error / incomplete input (placeholder + error-node ownership).

Small enough to hand-author the grammar value; broad enough that structural + ID
parity means something.

**Representativeness limit (review-flagged).** lambda exercises projection
identity but is *not* one of the genuinely projectional/CRDT languages; passing on
lambda validates the mechanism and the oracle, not the §8 sprawl risk. Treat a
second, more projectional language as a required follow-up gate — the spike's
green light is "the approach is viable and measurable," not "the approach
survives loom's hardest case."

### 5.6 Ergonomics: the motivation axis (safety ≠ ergonomics)

D1/D2 prove **safety**; they say nothing about B's actual motivation (§4.1:
easier authoring + cross-language reuse). The spike as scoped in §5.5
hand-authors a grammar for an *already-solved* language to chase structural + ID
parity — so it cannot tell whether writing that grammar was *cheaper* than the
814-line hand parser, or whether it *reuses* across languages. Worse, escape-hatch
sprawl (§8) is exactly what makes grammar-as-data *safe but pointless*: if the
grammar needs a pile of language-specific imperative code, a grammar facade over
it is hand-writing with extra steps — "easy" evaporates while D2 still passes.

So the spike must **measure ergonomics**, not only safety:

- **E1 — authoring cost.** The lambda grammar value's size/complexity vs the
  814-line hand parser. Does it materially reduce authoring effort?
- **E2 — escape-hatch count.** How much language-specific imperative code the
  grammar needed. A high count means "easy" evaporated — grammar-as-data is not
  worth it even if D2 passes. (Per §4.5, apply E2 to **loomgen's plumbing too** —
  views.mbt's judgment residue is Layer 1's escape-hatch budget; same bet, same
  metric, measured across both layers.)
- **E3 — reuse (ideally).** A *second* small grammar, to measure cross-language
  reuse — the claim lambda alone cannot test.

**The GO decision needs safety AND ergonomics.** B graduates only if it is a safe
drop-in (D1/D2) *and* materially cheaper to author (E1/E2). A safe-but-not-cheaper
result is a **"no"** — the motivation was ergonomics, so ergonomics is the success
metric, not a footnote.

**Shared vehicle, separate gates (do not fuse them).** E3 (reuse) and the §5.5
projectional-language follow-up share *one test vehicle* — a second, harder
language — and it is efficient to run them on that one vehicle at once. But they
are **distinct measurements on distinct axes**: safety-sprawl via `tree_diff`
(D2a), ergonomics-sprawl via escape-hatch count / authoring cost (E2/E1), reuse
via the second grammar's marginal cost (E3). Calling them "the same experiment"
risks dissolving the conjunctive gate ("safety AND ergonomics") into one holistic
pass/fail — which is exactly the safety≠ergonomics axis-conflation this section
warns against. Keep it: **one vehicle, three measurements, an explicit AND.**

## 6. ROADMAP non-goal #1 — revisit, evidence-gated

Non-goal #1: "Parser generation. Hand-written recursive descent. Checkpoint-based
reuse compensates for lower reuse granularity vs Lezer/tree-sitter."

Its protected reasons, and their status:

1. **Manual reuse checkpoints** → *dissolved.* Reuse is already per-node in
   `ParserContext`; a rule frame is a checkpoint (finding 1).
2. **Precedence / left-recursion** → *dissolved.* Pratt-as-data (monogram).
3. **Hot-path control, recovery shape, and CST compatibility kept transparent
   and debuggable** (Codex finding 4 — the unstated third reason) → *preserved
   constraint.* Grammar-as-data must not sacrifice this. The spike's
   structural-identity + ID-parity target (§5.2–5.3) is precisely the guard for it.

Revisiting the non-goal is justified, but the revisit is gated on the spike's
evidence, not on this argument.

## 7. Codex review record (2026-06-20)

Verdict: "Mostly valid, but underweights semantic/projection parity and
overstates how much the ROADMAP rationale has dissolved. Approve the spike-first
framing — but do not build loomgen in parallel until the spike has produced a
concrete minimal IR contract." Round-1 corrections folded into this doc:

- The existing oracle checks CST + diagnostics only → §5.2 D2a added.
- Do not build loomgen in parallel → §4.4 step 2 (derive contract first).
- Generated CST shape is an implicit public identity/stability contract → §5.2 +
  §5.3 structural-identity target.
- The facade can still regress reuse if rule frames do not align with
  `node`/`wrap_at`/`separated_list`/repeat-group boundaries → tracked in §8.
- The third unstated ROADMAP reason → §6 item 3.

**Round-2 review (of this written doc).** Codex verified the claims against source
and found the §5.2 "reduction" overstated: it claimed stable IDs are a *pure
function of the CST* and that the spike need *not* run the tracker. Verified
false — `realign_projection_identities` takes `(baseline, next_source,
next_leaves, allocate, edit?)` and `ProjectionStringIdAllocator` carries
`used`/`counters` state and seeds-then-skips prior-baseline IDs, so IDs are
**path-dependent**. Fixes folded in: §5.2 now adds **D2b** (run the existing pure
tracker/allocator for both A and B and assert ID parity), §5.4 reworded ("runs
the existing pure helper", not "upstream of"), and "byte-identity" replaced with
"structural identity (`tree_diff`, up to hash collisions) + ID parity" throughout.
(Round-2 also noted the `incr/` submodule is unpopulated in the review worktree;
the incr 0.9.0 claims were verified earlier in the populated main checkout —
`incr/incr/cells/accepted_derived.mbt`, `incr/CHANGELOG.md`.)

**Round-3 review (design-principles based).** An independent review against the
project's design principles (reading the pre-round-2 version) judged the argument
methodologically sound and flagged five weaknesses. W1 — the §5.2 "pure function
of the CST" claim — was the *same* flaw Codex round-2 had already caught and
fixed; the independent convergence confirms it was real, and the review's sharper
formulation (IDs are a pure function of the *(CST sequence, edit sequence)*; do
not collapse D2 to a final snapshot) was folded into §5.2. W2 (a lambda-only
spike cannot retire the projectional-sprawl risk) → §5.1/§5.5 scope caveats + a
follow-up gate. W3 (no stop condition) → §5.3 stop-condition requirement. W4
("convergent" asserted) → §4.4 step 3 softened to contingent-on-IR-first. W5
(Principle 1 — B's motivation is thinner than its feasibility) → §4.1 asymmetry
rationale. The review correctly stressed the whole recommendation rests on §3;
those findings were independently re-verified live this session (ParserContext
primitives, lambda 814 lines, `projection_identity` zero `@incr`, incr 0.9.0
`AcceptedDerived`, oracle scope) — the ≈1,200-line figure remains an estimate,
and "reuse is per-node" (finding 1) is verified at the primitive level and is
itself re-exercised by the spike's D1/D2b.

**Round-4 review (source-confirmed, design-principles based).** The reviewer read
the actual source (`projection_identity.mbt`, `test_support.mbt`,
`pipeline/parser.mbt`, lambda `grammar.mbt`, `core/pkg.generated.mbti`) and
**confirmed findings 1, 4, 5, 6 as fact** (finding 2's 814-line count re-confirmed
here; finding 7 / incr 0.9.0 remains verified-by-me in the main checkout, not by
the reviewer). The W1 invariant was upgraded from "speculation" to fact against
the real signature, with a new detail —
`ProjectionIdentityTracker.compose_projection_identity_edits` composes pending
edits across malformed intermediates — folded into §5.2 (invariant now over
*(CST/leaf, edit, source)* sequences). **New, highest-value point: safety ≠
ergonomics.** D1/D2 prove B is a *safe* drop-in, but B's motivation (easier
authoring + reuse) is an orthogonal axis the spike did not measure — and lambda
(the easiest, fewest-escape-hatch case) cannot validate it. Folded in: §4.1
motivation triage (robust = API-backed; easy/reusable = unproven), §5.1
safety-vs-ergonomics framing, new §5.6 ergonomics gate (E1/E2/E3 + "GO needs
safety AND ergonomics"), §8 sprawl-attacks-motivation note, §9 ergonomics
deliverable. Also softened the "*the* parser" singularization in finding 2.

**Round-5 review (meta — review of the assessment).** The reviewer re-verified
finding 7 in the populated main checkout and caught a precision slip: the doc
cited `#232` for the `BackdateEq` tier, but the `[0.9.0]` CHANGELOG cites only
`#233`. Resolved — `#232` is real (git-log commit `24a87b0`) but
CHANGELOG-unconfirmed; provenance now noted in finding 7. Three structural catches
on the *assessment*, folded in: (A) "the ergonomics gate and the
projectional-language follow-up are the same experiment" risked dissolving the
conjunctive gate → reframed as **shared vehicle, separate gates** (§5.6). (B)
"converged" was overstated — the best catch arriving in the *last* round is weak
evidence for convergence, and all rounds targeted Layer 2 while the *committed*
target (loomgen / Layer 1) had no adversarial pass → §4.1 commitment softened, §8
review-asymmetry risk added, "converged" retracted pending a Layer-1 pass. (C)
"Principle 1 catch, not Principle 4" was a false binary (the catch came *from*
Principle-4 activity and *exposed* a Principle-1 problem) → conceded. Attribution
corrected: the ergonomics axis was **co-generated** — the "easier-to-author"
motive was supplied earlier in-conversation; the reviewer supplied "the spike
does not measure it."

**Round-6 — the Layer-1 (loomgen) adversarial pass itself** (the action B2
demanded), driven by the reviewer against real source and re-verified here. Result
recorded as §4.5: **L1-A** (RawKind stability-registry vs the design's
sequential/idempotent promise — a correctness bug, confirmed against
`syntax_kind.mbt`'s appended `43`/`44` + skipped `24`/`26` and design line 381),
**L1-B** (views.mbt judgment grows with maturity — confirmed against `params()`
fallback, `body()`/`init()` exclusion predicates, `to_type`/`cst_to_type`
importing `@typecheck`, design line 541), the "same bet at two layers" synthesis,
and the morm half-right point (design line 421). §4.1/§8 updated to reflect the
pass is done; the "converged" retraction was empirically vindicated — hitting the
committed layer surfaced a design-promise-violating bug that four Layer-2 rounds
never would have.

## 8. Open risks / what would invalidate this direction

- **Interpreter hot-path performance.** Walking a grammar IR per token may
  regress loom's tuned incremental hot path vs hand-RD. Gate the emitter behind
  a benchmark; the spike should measure, not assume.
- **Frame-to-reuse-boundary alignment.** The facade calls the right primitives
  but can still regress reuse if grammar rule frames do not align exactly with
  `node` / `wrap_at` / `separated_list` / repeat-group boundaries.
- **Projectional escape-hatch sprawl.** If lambda (and especially the
  projectional languages) need so much language-specific logic that the grammar
  cannot stay declarative, grammar-as-data is the wrong model — *safe but
  pointless*, because the sprawl destroys the ergonomics that motivate B. This
  attacks the motivation axis, not safety; the direct measurement is **E2**
  (escape-hatch count, §5.6), with structural/ID divergences as a secondary
  signal. Note there is a *performance* gate (interpreter benchmark, above) but
  the *ergonomics* gate (§5.6) is the one this risk lands on.
- **incr freshness.** `AcceptedDerived` / `BackdateEq` shipped only at 0.9.0
  (`#232`) with a freshness fix at `#233`; any migration onto it leans on new code.
- **Layer 1 / loomgen review-asymmetry — now CLOSED (§4.5).** The committed target
  was unreviewed through four Layer-2 rounds; the Layer-1 pass (§4.5) closed it and
  found **L1-A** (RawKind registry vs the design's sequential/idempotent promise —
  a correctness bug) and confirmed **L1-B** (views.mbt judgment grows with language
  maturity). The residual risks live on as: (L1-A) the loomgen design must add a
  persistent kind→raw registry, and (L1-B) the escape-hatch budget (§5.6 E2) must
  be measured for loomgen too, not only grammar-as-data — they are the *same bet*.

## 9. Decision status & next step

No decision is committed. The recommended next action is to take the **spike**
(§5) into the writing-plans skill to produce a concrete execution plan:
hand-author the minimal lambda grammar IR slice (§5.5), build the
cross-implementation oracle (§5.2: D2a CST/diagnostics + D2b stable-ID parity),
run it to structural + ID parity (§5.3), and record the divergences as the
evidence that decides (i)-vs-(ii) and the grammar-as-data-vs-status-quo call. The
plan must also (a) define the spike's **stop condition** (§5.3), (b) name the
**projectional-language follow-up gate** (§5.5), and (c) include the **ergonomics
measurement** (§5.6: E1 authoring cost, E2 escape-hatch count, E3 reuse) so the GO
decision tests ergonomics — B's actual motivation — and not only safety. The
lambda spike's green light means "viable and measurable," not "survives loom's
hardest case."

## 10. Related

- `docs/analysis/2026-06-20-ideal-package-decomposition.md` — sibling
  investigation (package boundaries).
- `docs/decisions/2026-05-28-authoring-last-good-semantic-projection.md` —
  last-good projection ADR.
- `docs/decisions/2026-05-29-stable-semantic-projection-identity.md` — the
  leaf-level stable-identity helper the reduction (§5.2) relies on.
- `docs/decisions/2026-06-13-parsercontext-method-only-boundary.md` — the
  method-only `ParserContext` boundary the facade would build on.
- parent canopy `docs/design/07-loomgen-design.md` — the unbuilt loomgen design.
