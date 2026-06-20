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

1. **`ParserContext` is a rich execution layer** — ~45 public primitives
   including per-node reuse (`try_reuse_repeat_group`, `set_reuse_cursor`,
   `checkpoint`/`mark`/`restore`), node-building (`node`, `wrap_at`,
   `node_with_recovery`, `emit_token`), cursor (`at`, `at_adjacent`, `peek*`),
   and recovery (`skip_until_balanced`, `emit_error_placeholder`,
   `report_expected`). Combinators live in `loom/src/core/parser_combinators.mbt`
   (`separated_list`, …). **Reuse is already per-node.**
2. **lambda's actual parser is `examples/lambda/src/cst_parser.mbt` = 814 lines**
   of hand-written recursive descent; its `grammar.mbt` is 31 lines. This 814-line
   artifact is what a grammar-as-data interpreter would replace.
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
   first-class acceptance tier** (#232): `accepted_memo` gates acceptance by
   *revision identity* for non-`Eq` values carrying a `Revision`. #233 fixed a
   silent-freshness bug in the watched fold under dynamic diamond dependencies.
   **loom does not consume `AcceptedDerived` yet** (it hand-rolls last-good in
   `projection_identity.mbt`).

## 4. Recommendation

### 4.1 The literal question, answered precisely

- **loomgen plumbing codegen = a real target. Commit to it.** Proven pattern,
  ~1,200 lines/language of mechanical glue, inspectable output, behaviour
  verified by existing tests. *Committing to loomgen as a target is separate from
  its build order:* per §4.4 its build waits for the spike-derived IR contract so
  its annotation schema converges toward the grammar IR rather than diverging.
- **Grammar-as-data interpreter (replacing the 814-line hand parser) = a
  hypothesis, not yet a target.** It graduates to a target only after the spike
  (§5) validates it for loom's projectional case.

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
   a subset of the eventual grammar IR, so the dual-source period is
   *convergent*, not divergent.
4. The interpreter, if it graduates, is a **facade over the verified
   `ParserContext` primitives + a new Pratt sub-engine** — not a from-scratch
   reuse engine. **Interpret-now / emit-later** stay two backends over one IR
   (monogram's proof), the emitter deferred behind a benchmark.

## 5. The de-risk spike

### 5.1 What it must establish

That grammar-as-data parser **B** is a drop-in for hand parser **A** on lambda,
with no downstream churn — validated end-to-end through the projectional layer,
not just precedence (monogram already proved precedence; loom's novel risk is
projection/identity).

### 5.2 The oracle — and the reduction that simplifies it

Codex flagged the load-bearing risk as: a grammar IR can pass parser parity yet
**churn stable IDs / authoring caches** by changing placeholder placement,
transparent spans, error-node ownership, or list grouping.

**Reduction (the key first-principles move):** Term, projection leaves, stable
IDs, and last-good are **all pure functions of the CST** — the fold is
deterministic, `realign_projection_identities` is a pure function of the leaf
sequence, and the leaf sequence is extracted from the CST. Therefore **the CST
is the master invariant**: if B produces a structurally identical CST to A
(`tree_diff`-empty), every *CST-derived* downstream property is identical by
construction. The four churn cases Codex named are all CST-*shape* facts, so they
are all caught by CST comparison. (Diagnostics are *not* purely CST-derived in
loom — the existing oracle checks them separately — so D2 below checks them too.)

The oracle has two dimensions:

- **D1 — internal consistency (reuse existing infra).** Run
  `assert_incremental_edit_matches_full_parse` on parser B. Proves B is itself
  incrementally correct (B-incremental == B-fresh). Zero new code.
- **D2 — cross-implementation equivalence (the new oracle).** Run the same edit
  sequence through A and B; assert `@core.tree_diff(A_cst, B_cst)` is empty
  **and** `A_diagnostics.equal(B_diagnostics)` at **every step.** Because of the
  reduction, CST + diagnostics parity is the entire check — no need to run
  `AcceptedDerived`, the tracker, or the reactive graph inside the spike.
  (Precision the eventual spec must pin: the leaf comparison must compare exactly
  the fields `ProjectionIdentityTracker` matches on.)

### 5.3 The central design fork — the equivalence bar

- **(i) Structurally identical to A** (`tree_diff`-empty CST + equal diagnostics)
  → drop-in, zero downstream churn, but B must replicate A's exact
  recovery/wrapping quirks. Hardest; safest migration.
- **(ii) Internally-consistent-but-different** → B may produce a different valid
  CST; accept a one-time global re-baseline at switchover (a version migration),
  require D1 thereafter. Easier; one-time churn cost.

**Decision: the spike *targets* (i) and treats every divergence as a finding.**
Not because (i) is the final migration bar, but because it is the most
informative experiment — if B hits byte-identity on lambda, every weaker
property follows for free; if it cannot, the precise divergence shows exactly
where grammar-as-data's model parts ways from hand-RD, which is what the spike
exists to learn. The (i)-vs-(ii) *migration* decision is then made **with** that
evidence, not before it.

### 5.4 Migration verdict: `projection_identity` → `AcceptedDerived`

**Neither a precondition nor a parallel track — an independent, deferred one.**
The spike tests *upstream* of `projection_identity`, so the `AcceptedDerived`
migration does not gate it. And "migrate `projection_identity` →
`AcceptedDerived`" is really "*promote last-good from a pure caller-driven helper
into the reactive pipeline as an `AcceptedDerived` cell*" — an architectural
change to the pipeline. Do not churn pipeline architecture for a parser
direction that is not yet validated. Sequence it after the spike, independently.
(When it does happen, the spike must exercise the dynamic/diamond dependency
case, since that path was only stabilised at incr 0.9.0 via #233.)

### 5.5 Scope

lambda, a minimal grammar-IR slice chosen to hit the churn-prone cases:

- a node-with-children (`Let` / `Abs`),
- a `separated_list` (list grouping),
- a Pratt operator (`App` / `Bop` precedence),
- a deliberate error / incomplete input (placeholder + error-node ownership).

Small enough to hand-author the grammar value; broad enough that byte-identity
means something.

## 6. ROADMAP non-goal #1 — revisit, evidence-gated

Non-goal #1: "Parser generation. Hand-written recursive descent. Checkpoint-based
reuse compensates for lower reuse granularity vs Lezer/tree-sitter."

Its protected reasons, and their status:

1. **Manual reuse checkpoints** → *dissolved.* Reuse is already per-node in
   `ParserContext`; a rule frame is a checkpoint (finding 1).
2. **Precedence / left-recursion** → *dissolved.* Pratt-as-data (monogram).
3. **Hot-path control, recovery shape, and CST compatibility kept transparent
   and debuggable** (Codex finding 4 — the unstated third reason) → *preserved
   constraint.* Grammar-as-data must not sacrifice this. The spike's byte-identity
   target (§5.3) is precisely the guard for it.

Revisiting the non-goal is justified, but the revisit is gated on the spike's
evidence, not on this argument.

## 7. Codex review record (2026-06-20)

Verdict: "Mostly valid, but underweights semantic/projection parity and
overstates how much the ROADMAP rationale has dissolved. Approve the spike-first
framing — but do not build loomgen in parallel until the spike has produced a
concrete minimal IR contract." Corrections folded into this doc:

- The existing oracle checks CST + diagnostics only → §5.2 D2 added.
- Do not build loomgen in parallel → §4.4 step 2 (derive contract first).
- Generated CST shape is an implicit public identity/stability contract → §5.2
  reduction + §5.3 byte-identity target.
- The facade can still regress reuse if rule frames do not align with
  `node`/`wrap_at`/`separated_list`/repeat-group boundaries → tracked in §8.
- The third unstated ROADMAP reason → §6 item 3.

## 8. Open risks / what would invalidate this direction

- **Interpreter hot-path performance.** Walking a grammar IR per token may
  regress loom's tuned incremental hot path vs hand-RD. Gate the emitter behind
  a benchmark; the spike should measure, not assume.
- **Frame-to-reuse-boundary alignment.** The facade calls the right primitives
  but can still regress reuse if grammar rule frames do not align exactly with
  `node` / `wrap_at` / `separated_list` / repeat-group boundaries.
- **Projectional escape-hatch sprawl.** If lambda (and especially the
  projectional languages) need so much language-specific logic that the grammar
  cannot stay declarative, grammar-as-data is the wrong model. The spike's
  byte-identity divergences are the early signal.
- **incr freshness.** `AcceptedDerived` / `BackdateEq` shipped only at 0.9.0
  (#232) with a freshness fix at #233; any migration onto it leans on new code.

## 9. Decision status & next step

No decision is committed. The recommended next action is to take the **spike**
(§5) into the writing-plans skill to produce a concrete execution plan:
hand-author the minimal lambda grammar IR slice (§5.5), build the D2
cross-implementation oracle (§5.2), run it to byte-identity (§5.3), and record
the divergences as the evidence that decides (i)-vs-(ii) and the
grammar-as-data-vs-status-quo call.

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
