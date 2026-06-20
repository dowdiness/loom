# Ideal Package Decomposition — 2026-06-20 (first-principles, ungated)

**Status:** Design exploration. Companion to — *not* a replacement for — the [pressure-gated restructuring analysis](2026-06-20-architecture-restructuring.md). That doc asks "what does the *observed pressure* justify?"; this doc deliberately **drops that gate** (per direction) and asks "what is the *structurally ideal* shape, reasoned from first principles, and can MoonBit's `internal/` feature express it?"

**Headline:** Yes — split the engine, and use `internal/` where it earns its keep. The right cut is **a contract/implementation boundary that runs *through* the machinery**, not a flat file-shuffle: the reuse/buffer *protocol* is public authoring contract (a hand-written incremental parser must call it); the *mechanism* behind it is hidden. But verifying *where the mechanism is defined* (not just call counts) sharpens the answer: the heaviest mechanism (event balancing, tree-building, interning) **already lives correctly in `seam`**, the reuse guts (`CursorFrame`) are **irreducibly co-located** with the public protocol in `parser` (splitting them cycles), and `internal/` within loom earns **at most one** package (recovery/reparse, conditional). So the ideal shape is dominated by the **contract decomposition + facade + dependency rules**, with `internal/` a small, honest addition — a stronger result than a four-internal-package roster. All load-bearing assumptions (incl. the MoonBit mechanics) are verified against the repo, not assumed.

---

## 0. Answering the two questions directly

### "Why did the previous analysis reject the core split?"

It rejected it **inside the pressure-gated frame**, and that reasoning was correct *for that frame* but answered a narrower question than you're now asking:

- It measured **core-internal coupling** (co-change between `core` files) and found it *low* — so a split would not reduce *blast radius*. True.
- It therefore concluded "split is cosmetic" **with respect to blast radius**, and the project's own discipline ("don't restructure without demonstrated pressure") closed the case.

Two things that frame missed, surfaced now:

1. **It measured the wrong coupling.** Low coupling *within* `core` is not the issue. The real coupling is **engine → example**, through a leaky public surface: every example imports `dowdiness/loom/core` directly and reaches into machinery — `@core.TokenBuffer` (14×), `ReuseCursor` (8×), `OldTokenCache` (8×), `LexCursor` (8×), `OldToken` (both hand-written `cst_parser.mbt` files). There is **no contract/implementation boundary today**. Refactoring the engine mechanism *can* break languages. That is a real architectural liability the file-level co-change metric never sees.
2. **Blast-radius reduction was the wrong success metric for your goal.** A split also buys **cognitive load**, **enforced boundaries that prevent future leakage**, and **freedom to refactor mechanism without breaking languages**. Those are exactly what `internal/` delivers, and they don't require a "breakage incident" to justify once the pressure-gate is lifted.

So: the rejection was a correct answer to "is a split *pressure-justified for blast radius*?" and the wrong answer to "is a split the *ideal structure*?" With the gate removed, the split is justified — for the boundary and cohesion, not for blast radius.

### "Can we use MoonBit's `internal/` feature?"

Yes, and it is the *correct* tool, verified three ways:

- **It is already the repo idiom.** `event-graph-walker/internal/{branch,oplog,causal_graph,fugue,document,movable_tree,…}` (8 packages) and `incr/incr/cells/internal/{kernel,datalog,pull,push,shared}`. This decomposition follows an established in-repo convention, not a novel pattern.
- **It enables carve-with-hide.** When a future engine refactor wants to split mechanism that is *currently `priv` within one package* into its own package — yet keep it unreachable from examples — `internal/` is the only tool: a plain split would force the carved symbols `pub`. (Verified below: within `loom` today this earns a *narrow* role, because the heaviest mechanism already lives correctly in `seam` and the rest is irreducibly co-located in `parser`. The point is that `internal/` removes the "split forces public" tax whenever a carve *is* warranted.)
- **It does not block type flow through public APIs (verified).** `event-graph-walker/tree` (a public package) exposes `pub fn TreeState::create_node(...) -> @movable_tree.TreeNodeId`, where `@movable_tree` is an `internal/` package. So an internal-defined type may appear in a public signature; only *importing* the internal package is restricted to the module subtree. This means implementation types can thread through public combinators as opaque values examples can't construct or poke at.

---

## 1. First principles for the cut

Three rules generate the whole decomposition:

1. **A package = one vocabulary with one reason to change and one audience.** Edit-model, error-model, lexing-contract, parsing-contract, projection, and reactive-runtime are six distinct vocabularies. They share a tree (`seam`) but change for unrelated reasons.
2. **The public/internal line is the contract/implementation line — and for a *hand-written* parser framework it runs through the machinery, not around it.** A language author writes the recursion and *places the reuse checkpoints*; the framework cannot own checkpoint placement without owning traversal, which is parser generation — explicitly ruled out by the ROADMAP. Therefore the reuse/buffer **protocol** is irreducibly part of the authoring contract. What is *not* contract is the **implementation** that fulfills it.
3. **`internal/` enforces #2 where a `priv` keyword can't.** `priv` hides within one package; `internal/` hides a *whole package* from outside the module while letting sibling packages use it. Use `internal/` only for mechanism that must be *shared across loom packages yet invisible to examples*; keep single-package-private helpers as plain `priv`.

### The verified "tell" for where the line lands

Examples in **production** code:

| Symbol | Defined in | Production example use | Verdict |
|--------|-----------|------------------------|---------|
| `ReuseCursor`, `OldTokenCache`, `OldToken` | `loom/core` | both `cst_parser.mbt` (hand-written parsers) | **contract (public, `parser`)** |
| `TokenBuffer`, `LexCursor` (`.produced`/`.advance_char`/`.set_position`) | `loom/core` | 3–4 lexer files | **contract (public, `lex`)** |
| `LexStep`, `TokenInfo`, `LexResult`, `LexError`, `PrefixLexer`, `ModeLexer` | `loom/core` | lexers across examples | **contract (public, `lex`)** |
| `CstFold` | `seam` | 1 production file | **contract (public, light)** |
| `CursorFrame` | `loom/core` (beside `ReuseCursor`) | **0** | **`priv` in `parser`** (co-located w/ the protocol — *not* a separate pkg) |
| `reparse_block` / `build_physical_path` recovery fns | `loom/core` | **0** (examples use only the `BlockReparseSpec` *type*) | **engine-internal** → `priv` in `parser`, or `loom/internal/recovery` iff cross-package |
| `EventBuffer`, `build_tree*`, `balance_children` | **`seam`** | **0** (only a vendored `btree` dep shadows the name) | **already correctly placed in `seam`**; further hiding = a *seam-module* `internal/` decision, out of loom scope |
| `Interner`/`NodeInterner` | `seam` | **0** in grammars (only `lambda/benchmarks/`) | **`seam`-private / measurement-only** |

The gap between "examples drive `ReuseCursor`/`TokenBuffer`/`OldToken`" and "examples never touch `CursorFrame`/recovery-fns/`EventBuffer`" *is* the boundary. The decisive correction from verifying *definitions* (not call counts): the heaviest mechanism — tree-building/balancing — **is already in `seam`, not `loom/core`**, and the reuse cluster's guts (`CursorFrame`) are **co-located with the public protocol** they serve. So `internal/` earns at most *one* loom package (recovery), not the four a from-memory roster would invent.

---

## 2. Target decomposition

`dowdiness/loom` module, package paths under `loom/src/`. `seam` and `incr` remain separate modules (already well-isolated).

### Public contract packages (importable by examples & downstream)

| Package | Owns | Depends on |
|---------|------|-----------|
| `loom/edit` | `Edit`, `Range`, `TextRange`, `TextDelta`, `Editable`, `diff` — the vocabulary of change | `text_change` |
| `loom/diagnostic` | `Diagnostic`, `DiagnosticSet`, codes/labels/sources/severity, `LineIndex`, `LineCol` | `loom/edit`, `seam` *(verified: `diagnostics.mbt` references `@seam.RawKind` — a diagnostic carries the offending token's kind)* |
| `loom/lex` | `LexStep`, `TokenInfo`, `LexResult`, `LexError`, `PrefixLexer`, `ModeLexer`, `LexCursor`, `TokenBuffer` — lexing contract + incremental token layer | `loom/edit` *(verified seam-free: `token_buffer.mbt`/`lex_cursor.mbt`/`lex_step.mbt` have 0 seam refs — the token layer holds pre-tree tokens, not seam `CstToken`)* |
| `loom/parser` | `ParserContext` + combinators (`node`, `wrap_at`, `separated_list`, `at_adjacent`, …), `LanguageSpec`, `Grammar`, `parse_with`, `ReuseCursor` + `OldTokenCache` + `OldToken` + `CursorFrame`(`priv`) (reuse **protocol** + its guts, co-located), recovery surface + `BlockReparseSpec`, `AstView` | `loom/lex`, `loom/edit`, `loom/diagnostic`, `seam` |
| `loom/incremental` | `ImperativeParser` orchestration, damage tracking (unchanged; thin, sealed) | `loom/parser`, `seam` |
| `loom/pipeline` | `Parser[Ast]` + reactive cells (unchanged) | `loom/incremental`, `incr` |
| `loom/projection` | `projection_identity`, `proj_traits` (`Renderable`/`TreeNode`/`Canonical`), `ProjectionLeaf`, trackers | `seam`, `loom/edit` — **never the engine** |
| `loom/viz` | DOT renderer (unchanged) | `graphviz`, `seam` |
| `loom` (facade) | curated `pub using` re-export of the surface above | all public packages |

### Internal packages (`loom/internal/*` — importable only within `dowdiness/loom/*`)

| Package | Owns | Status |
|---------|------|--------|
| `loom/internal/recovery` *(conditional)* | `reparse_block`, `build_physical_path`, recovery-sync helpers (the functions behind the public `BlockReparseSpec` type) | **Earned only if** these functions are called from more than one loom package (e.g. `incremental`/`pipeline`, not just `parser`). If parser-only, they stay `priv` in `loom/parser` and **no internal package is created.** Decide at migration time with a `find-references` pass. |

That is the *entire* loom-internal roster — at most one package, possibly zero. Two would-be internal packages were rejected after verifying definitions:

- **`treebuild` rejected** — `EventBuffer`/`build_tree*`/`balance_children` are defined in **`seam`** (`seam/event.mbt`), not `loom`. There is nothing in loom to carve. Examples never touch them (verified — the only `build_tree` hits sit in a vendored `btree` dep). Hiding them further is a **separate `seam/internal/` decision** affecting a separately-published module — explicitly *out of scope* here.
- **`reuse` rejected** — `CursorFrame` is defined beside `ReuseCursor`/`OldTokenCache`/`OldToken` in one file; they are mutually recursive. Splitting frames into `loom/internal/reuse` while the protocol stays in `loom/parser` would create a `parser ⇄ internal/reuse` **import cycle** (MoonBit rejects). The cluster is irreducibly co-located → keep it in `loom/parser`, guts `priv`.

> Rule #3 in action: single-package-private helpers stay `priv`. `internal/` is reserved strictly for mechanism that must cross a loom package boundary yet stay invisible to examples — which, after verification, is *narrow*. `Interner`/`NodeInterner` remain in `seam`. The honest result is that loom's mechanism is *already* mostly where it belongs; the ideal shape is dominated by the **contract split + facade**, with `internal/` a small, conditional addition.

### Picture

```
examples/<lang>  ────────────────────────────────┐ (may import only the public ring / facade)
                                                  ▼
  loom (facade)
   ├─ loom/pipeline ── loom/incremental ── loom/parser ──── loom/lex ──→ loom/edit
   │                                          │  │                          ▲
   │                       (CursorFrame, recovery fns priv here;            │
   │                        loom/internal/recovery only if those            │
   │                        fns prove cross-package)                        │
   ├─ loom/projection ──────────────────────┐│  ├──→ loom/diagnostic ──→ loom/edit, seam
   ├─ loom/viz ──→ seam                       ▼▼  └──→ seam
   ├─ loom/diagnostic                       seam (CST: CstNode/SyntaxNode,
   └─ loom/edit                              EventBuffer/build_tree/balance — already module-owned)
   incr (reactive, separate module) ◄── loom/pipeline
   loom/projection ──→ seam, loom/edit  (never the engine)
```

Acyclic. Examples reach the public ring (or the facade); any `loom/internal/*` is unreachable to them by language rule; `loom/projection` cannot see the engine.

---

## 3. Dependency & boundary rules (the invariants)

| Rule | Enforced by |
|------|-------------|
| `loom/internal/*` importable only by `dowdiness/loom/*` | MoonBit `internal/` (language-level) |
| `loom/projection` MUST NOT import `loom/parser`/`incremental`/`pipeline` | `check-deps.sh` (grep `moon.pkg`) |
| `loom/edit`/`loom/diagnostic` MUST NOT import any engine or lex package | `check-deps.sh` |
| `seam` imports nothing from `loom` | `check-deps.sh` |
| Examples MUST NOT import `loom/internal/*` | MoonBit (compile error) |
| No import cycles | `check-deps.sh` |

The prize is the *curated surface*: today an example imports `@core` and reaches everything; after the split it programs against a small, intentional contract (the reuse/buffer protocol + combinators + data types), while the genuinely-internal pieces — recovery (if carved) and, separately, seam's tree-building (if seam hides it) — become *language-unreachable*. The protocol stays public **by design** (it must, for hand-written parsers); what the boundary buys is that implementation *behind* the protocol can be rewritten freely, and examples can no longer accrete new dependencies on mechanism that was only ever public by accident of living in one fat `core`.

---

## 4. Migration strategy (staged, reversible, each shippable)

Ordered so the lowest-risk, highest-clarity moves land first; every stage keeps the public API stable via the facade.

**Stage 0 — Add `check-deps.sh` + the facade discipline (1 PR).** Encode the target rules *before* moving code, so each later stage is verified against them. No code moves yet.

**Stage 1 — Carve the pure-data leaves: `loom/edit`, `loom/diagnostic` (1–2 PRs).** `git mv` the edit/range/delta/diff files and the diagnostic files into new packages; re-export through the facade so `@loom.Edit`/`@loom.Diagnostic` (already how examples reach them, 7×/…) keep working. Lowest risk — pure data, no engine entanglement.

**Stage 2 — Extract `loom/projection` (1 PR).** Exactly Stage A1 of the gated analysis (verified clean leaf). Independent of the engine carve; can land anytime.

**Stage 3 — Split the contract packages: `loom/lex`, `loom/parser` out of `core` (2–3 PRs).** The largest move (`parser.mbt` is 1 474 LOC). Move-only; the reuse cluster (`ReuseCursor`/`OldTokenCache`/`OldToken` + `CursorFrame` as `priv`) stays together in `loom/parser`, and the lexer types move to `loom/lex`. Combinators stay public. Use the existing differential/property suites as the pin. (No `internal/` carve here — the reuse guts are package-`priv`, the tree-building mechanism is already in `seam`.)

**Stage 4 — *Conditional:* `loom/internal/recovery` (0–1 PR).** Run `find-references` on `reparse_block`/`build_physical_path`/recovery-sync. If they are called only from `loom/parser`, leave them `priv` there and **skip this stage**. If `incremental`/`pipeline` call them, carve a `loom/internal/recovery` package — *this* is where `internal/` earns its keep (cross-package mechanism, examples never touch it; verified 0). This is the single place the `internal/` feature applies within loom.

**Stage 5 — Retire `loom/core`.** Once emptied, delete the package; the facade re-exports the new packages so downstream import sites can migrate gradually (or the facade keeps them working indefinitely).

> Separate, *out-of-loom-scope* follow-up: `seam` could move `EventBuffer`/`build_tree*`/`balance_children` into `seam/internal/` (examples don't touch them — verified). That hides seam's tree-building mechanism the same way, but it is a **seam-module** PR with seam's own consumers, not part of this loom decomposition.

Each stage: `moon check --deny-warn` + `moon test` per touched module + `moon info` `.mbti` diff (relocation only) + `check-deps.sh` green + `moon bench --release` no-regression on lambda & markdown.

---

## 5. Trade-offs, alternatives, and honest limits

- **Contract-exposes-protocol vs hide-everything-behind-combinators.** The tempting "ideal" — richer combinators so authors never touch `ReuseCursor`/`TokenBuffer` — taken to completion *is parser generation*, which the ROADMAP deliberately excludes (hand-written recursive descent is a foundational choice). For an arbitrary grammar the author owns the recursion and the checkpoint placement, so the reuse protocol is irreducible contract. **Combinator enrichment (lists/adjacency, already in flight) is a complementary, separate proposal** that *reduces how often* authors touch the raw protocol — it is a judgment, not part of this structural ideal, and is labeled as such. Do not let the lifted pressure-gate turn "more combinators" into speculation-dressed-as-inevitability.
- **Package granularity vs import ergonomics.** Six public packages instead of one `core` means more import lines — fully absorbed by the facade (`@loom.Edit` etc., already the idiom). Cost: a curated facade must be maintained. Benefit: examples program against a small, intentional surface.
- **`projection_shape`/`projection_group` stay in `seam`.** They are `impl`s over `seam`'s `SyntaxNode`; the orphan rule pins them there. Ideally they'd sit in `loom/projection`, but moving them needs newtype wrappers. Left in `seam`; flagged as a known seam/projection straddle, not resolved here.
- **`ImperativeParser` (`loom/incremental`) left intact.** It is thin and sealed (churn 5); folding it into `loom/parser` is optional and unmotivated. Kept as the orchestration layer.
- **The split is mostly relocation, not new mechanism.** Verifying *definitions* (not call counts) shrank the `internal/` story from four invented packages to at most one (`recovery`, conditional): tree-building already lives in `seam`, and the reuse guts are package-`priv` in `parser`. So the ideal shape's real content is the **contract decomposition + the facade + the dependency rules** — not a pile of internal packages. That is a more honest and more achievable result; treat any urge to manufacture more `internal/` packages as the same from-memory error this revision corrected.
- **Cost is real and front-loaded.** This is a multi-PR mechanical migration touching every example's imports eventually. The facade bounds the blast radius (re-exports keep call sites working).

---

## 6. Scope

**Included:** decomposing `loom/core` into the contract packages (`edit`, `diagnostic`, `lex`, `parser`, `projection`); the conditional `loom/internal/recovery` package; the dependency rules + `check-deps.sh`; the facade as the stable public surface.

**Excluded:** `seam`/`incr` internals (separate, well-isolated modules) — including the *optional* `seam/internal/` hiding of `EventBuffer`/`build_tree` (a seam-module decision); the `Interner` (stays in `seam`); parser-engine *algorithm* changes (none — this is structure only); combinator enrichment (separate judgment, §5); parser generation (ROADMAP-excluded and the reason the protocol stays public); the markdown monolith split and AP5 attachment question (covered by the gated analysis).

**Unknowns / verify-at-execution:** whether the recovery functions are cross-package (decides if Stage 4 happens at all — `find-references` answers it); exact `priv`→`pub`-to-module promotions if `loom/internal/recovery` is carved; whether any `core` helper resists a clean lex/parser cut (run `check-deps.sh` after each stage). These are migration-time checks, not design unknowns.
