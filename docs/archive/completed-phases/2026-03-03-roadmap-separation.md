# Roadmap Separation Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the root `ROADMAP.md` into two focused documents — one for the `dowdiness/loom` parser framework, one for the `examples/lambda` lambda calculus example — and link them from `docs/README.md`.

**Architecture:** Three sequential edits: rewrite root `ROADMAP.md` (framework-only, ~200 lines) → create `examples/lambda/ROADMAP.md` (lambda-specific content extracted from old ROADMAP) → update `docs/README.md` navigation. No code changes. No tests needed. Validate with `bash check-docs.sh` before committing.

**Tech Stack:** Markdown, `bash check-docs.sh` (validates `docs/` index coverage + line limits). Run from repo root (`/path/to/loom/`).

---

### Task 1: Rewrite root `ROADMAP.md` — framework only

**Files:**
- Modify: `ROADMAP.md` (full replacement)

**What to remove from current ROADMAP.md:**
- "Honest Assessment" section (stale — references `parser.mbt:72-227`, `lexer.mbt` paths from early Feb before Phases 0–7 closed those gaps)
- "Grammar Expansion" section (lambda concern)
- "Phase 6: CRDT Exploration" section (lambda/application concern)
- Per-phase verbose detail blocks (Phases 0–7, SyntaxNode-First Layer, NodeInterner, Grammar Abstraction, Loom Extraction, Rabbita, Parser API) — replaced by one-liners with archive links

**What to keep / condense:**
- Header + Goal (rewritten for framework audience)
- Target Architecture diagram + Architectural Principles (unchanged)
- Completed phases as brief one-liners with archive links
- Phase Summary dependency graph (trim Grammar Expansion + CRDT rows)
- Milestones table (trim lambda-specific rows)
- Planned section: only "Typed SyntaxNode views"
- "What This Does NOT Include", "Cross-Cutting Concern", "Success Criteria", "References"

**Step 1: Replace the file with the new framework-only content**

Write the following as the complete new `ROADMAP.md`:

```markdown
# Roadmap: dowdiness/loom — Incremental Parser Framework

**Updated:** 2026-03-03
**Status:** Active — framework stable; next: Typed SyntaxNode views
**Goal:** A reusable, language-agnostic incremental parser framework for MoonBit. Any grammar plugs in via `LanguageSpec[T,K]` and gets green tree (CST), error recovery, subtree reuse, and a reactive pipeline for free.

> Lambda calculus example roadmap: [examples/lambda/ROADMAP.md](examples/lambda/ROADMAP.md)

---

## Target Architecture

```
                        +-----------------------+
                        |     Edit Protocol     |
                        |  (apply, get_tree)    |
                        +-----------+-----------+
                                    |
                        +-----------v-----------+
                        |   Incremental Engine  |
                        |   - Damage tracking   |
                        |   - Reuse decisions   |
                        |   - Orchestration     |
                        +-----------+-----------+
                                    |
                  +-----------------+------------------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |  Incremental Lexer  |            |  Incremental Parser   |
       |  - Token buffer     |            |  - Subtree reuse at   |
       |  - Edit-aware       |            |    grammar boundaries |
       |  - Only re-lex      |            |  - Checkpoint-based   |
       |    damaged region   |            |    validation         |
       +----------+----------+            +-----------+-----------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |    Token Buffer     |            |   Green Tree (CST)    |
       |  - Contiguous array |            |  - Immutable nodes    |
       |  - Position-tracked |            |  - Structural sharing |
       |  - Cheaply sliceable|            |  - Lossless syntax    |
       +---------------------+            +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Red Tree (Facade)   |
                                          |  - Absolute positions |
                                          |  - Parent pointers    |
                                          |  - On-demand          |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Typed AST (Lazy)    |
                                          |  - Semantic analysis  |
                                          |  - Derived from CST   |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Error Recovery      |
                                          |  - Integrated in      |
                                          |    parser loop        |
                                          |  - Sync point based   |
                                          |  - Multiple errors    |
                                          +-----------------------+
```

### Architectural Principles

1. **No dead infrastructure.** Every cache, buffer, and data structure must be read by something during the parse pipeline.
2. **Immutability enables sharing.** Green tree nodes are immutable. When nothing changed, the old node IS the new node — not a copy, the same pointer.
3. **Separation of structure and position.** Green tree nodes store widths; red tree nodes compute absolute positions on demand.
4. **Incremental lexing is the first real win.** Re-tokenizing only the damaged region and splicing gives the parser unchanged tokens for free.
5. **Subtree reuse at grammar boundaries.** Check: kind match + leading token context + trailing token context + no damage overlap. All four must pass. The trailing context check is essential — a node's parse can depend on what follows it.
6. **Error recovery is part of the parser, not around it.** Record error → synchronize to known point → continue parsing.

---

## Completed Work

- **Phase 0: Reckoning** ✅ (2026-02-01) — removed dead cache infrastructure (~581 lines) — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 1: Incremental Lexer** ✅ (2026-02-02) — splice-based `TokenBuffer` re-lexes only damaged region — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 2: Green Tree** ✅ (2026-02-19) — `CstNode`/`SyntaxNode`, `EventBuffer`, `seam/` package — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 3: Error Recovery** ✅ (2026-02-03) — sync-point recovery, `ErrorNode`, up to 50 errors per parse — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 4: Subtree Reuse** ✅ (2026-02-03) — `ReuseCursor` 4-condition protocol, O(depth) per lookup — [notes](docs/archive/completed-phases/phases-0-4.md)
- **Phase 5: Generic Parser Framework** ✅ (2026-02-23) — `ParserContext[T,K]`, `LanguageSpec[T,K]`, `parse_with` — [notes](docs/archive/completed-phases/2026-02-23-generic-parser-impl.md)
- **Phase 6: Generic Incremental Reuse** ✅ (2026-02-24) — `ReuseCursor[T,K]`, `node()`/`wrap_at()` combinators — [notes](docs/archive/completed-phases/2026-02-24-generic-incremental-reuse-design.md)
- **Phase 7: Reactive Pipeline** ✅ (2026-02-25) — `ReactiveParser`: `Signal[String]`→`Memo[CstStage]`→`Memo[AstNode]` — [ADR](docs/decisions/2026-02-27-remove-tokenStage-memo.md)
- **SyntaxNode-First Layer (Phase 1+2)** ✅ (2026-02-25) — `SyntaxToken`, `SyntaxElement`, `.cst` private — [notes](docs/archive/completed-phases/2026-02-25-syntax-node-first-layer.md)
- **NodeInterner** ✅ (2026-02-28) — `Interner` + `NodeInterner`, session-global interners — [notes](docs/archive/completed-phases/2026-02-25-node-interner.md)
- **Grammar Abstraction** ✅ (2026-03-01) — `Grammar[T,K,Ast]`, `new_imperative_parser`/`new_reactive_parser` — [notes](docs/archive/completed-phases/2026-03-01-extract-generic-factories.md)
- **Loom Extraction** ✅ (2026-03-01) — `core/incremental/pipeline/viz` → `dowdiness/loom` sibling module — [notes](docs/archive/completed-phases/2026-03-01-examples-folder.md)
- **Rabbita Monorepo Migration** ✅ (2026-03-02) — submodules absorbed, lambda → `examples/lambda/` — [notes](docs/archive/completed-phases/2026-03-02-rabbita-style-monorepo.md)
- **Parser API Simplification** ✅ (2026-03-02) — `ImperativeParser`/`ReactiveParser`, global interners, `diagnostics()`/`reset()`, CST equality skip — [notes](docs/archive/completed-phases/2026-03-02-parser-api-impl.md)

---

## Planned

### Typed SyntaxNode Views

**Status:** Planned (Phase 3 of SyntaxNode-First Layer)

Typed wrappers — `LambdaExpr(SyntaxNode)`, `AppExpr(SyntaxNode)` — so callers get structured tree access without matching raw `SyntaxKind` enums. `AstNode` becomes JSON-serialization-only. Implementation lives in `examples/lambda/` as the reference; the framework provides the `SyntaxNode` API surface.

---

## Phase Summary

```
Phase 0: Reckoning                  ✅ COMPLETE (2026-02-01)
    |
    +------ Phase 1: Incremental Lexer      ✅ COMPLETE (2026-02-02)
    |
    +------ Phase 2: Green Tree / seam/     ✅ COMPLETE (2026-02-19)
                |
                +------ Phase 3: Error Recovery         ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 4: Subtree Reuse          ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 5: Generic Parser Ctx     ✅ COMPLETE (2026-02-23)
                |           |
                |           +-- Phase 6: Generic Reuse  ✅ COMPLETE (2026-02-24)
                |
                +------ SyntaxNode-First Layer          ✅ COMPLETE (2026-02-25)
                |           Phase 1: SyntaxNode API
                |           Phase 2: .cst private
                |           Phase 3: Typed views        ← PLANNED
                |
                +------ Phase 7: ReactiveParser         ✅ COMPLETE (2026-02-25)
                |
                +------ NodeInterner                    ✅ COMPLETE (2026-02-28)
                |
                +------ Grammar Abstraction             ✅ COMPLETE (2026-03-01)
                |
                +------ Loom Extraction                 ✅ COMPLETE (2026-03-01)
                |
                +------ Rabbita Monorepo Migration      ✅ COMPLETE (2026-03-02)
                |
                +------ Parser API Simplification       ✅ COMPLETE (2026-03-02)
```

---

## Milestones

| Milestone | Status |
|-----------|--------|
| Honest Foundation (Phase 0) | ✅ Complete (2026-02-01) |
| Incremental Lexer (Phase 1) | ✅ Complete (2026-02-02) |
| Green Tree / CST (Phase 2) | ✅ Complete (2026-02-19) |
| Error Recovery (Phase 3) | ✅ Complete (2026-02-03) |
| Subtree Reuse (Phase 4) | ✅ Complete (2026-02-03) |
| Generic Parser Framework (Phase 5) | ✅ Complete (2026-02-23) |
| Generic Incremental Reuse (Phase 6) | ✅ Complete (2026-02-24) |
| Reactive Pipeline (Phase 7) | ✅ Complete (2026-02-25) |
| NodeInterner | ✅ Complete (2026-02-28) |
| Grammar Abstraction | ✅ Complete (2026-03-01) |
| Infrastructure Extraction (dowdiness/loom) | ✅ Complete (2026-03-01) |
| Rabbita Monorepo Migration | ✅ Complete (2026-03-02) |
| Parser API Simplification | ✅ Complete (2026-03-02) |
| Typed SyntaxNode Views | Future — Confidence: High |

---

## What This Roadmap Does NOT Include

1. **Parser generation.** Hand-written recursive descent. Checkpoint-based reuse compensates for lower reuse granularity vs Lezer/tree-sitter.
2. **GLR or Earley parsing.** Unambiguous grammars don't need generalized parsing.
3. **Language server protocol.** An LSP layer sits on top of the CST; out of scope here.
4. **Evaluation / type checking.** This is a parser framework roadmap.
5. **Lambda calculus grammar expansion.** See [examples/lambda/ROADMAP.md](examples/lambda/ROADMAP.md).

---

## Cross-Cutting Concern: Incremental Correctness

**Invariant:** For any edit, incremental parse must produce a tree structurally identical to full reparse.

Verified via differential oracle (random source + random edits → compare incremental vs full reparse result). Property-based fuzzing with sequences of 10–100 random edits catches state accumulation bugs. Status: ✅ verified. New grammars plugged in via `LanguageSpec` must extend the oracle when added.

---

## Success Criteria for "Stabilized"

1. **Correctness:** Incremental parse produces identical trees to full reparse for any edit, verified by property-based testing over millions of random edits.
2. **Performance:** Single-character edits in a 1000-token file complete in under 100 microseconds (not counting initial parse).
3. **Error resilience:** Any input (including random bytes) produces a tree without panicking.
4. **Architecture:** No dead infrastructure. New grammar rules require only parser + syntax kind enum changes.
5. **Test coverage:** >95% line coverage on parser, lexer, tree builder, and incremental engine.
6. **Documentation:** Every public API has doc comments. Architecture decisions documented with rationale.

---

## References

### Architecture Inspiration
- [Roslyn's Red-Green Trees](https://ericlippert.com/2012/06/08/red-green-trees/)
- [rust-analyzer Architecture](https://github.com/rust-lang/rust-analyzer/blob/master/docs/dev/syntax.md)
- [swift-syntax](https://github.com/apple/swift-syntax)

### Incremental Parsing
- Wagner & Graham (1998) - [Efficient and Flexible Incremental Parsing](https://harmonia.cs.berkeley.edu/papers/twagner-parsing.pdf)
- [Lezer](https://lezer.codemirror.net/) — LR-based incremental parsing (inspiration, not template)
- [Tree-sitter](https://tree-sitter.github.io/) — Generated recursive descent with incrementality

### Error Recovery
- [Error Recovery in Recursive Descent Parsers](https://www.cs.tufts.edu/~nr/cs257/archive/donn-seeley/repair.pdf)
- [Panic Mode Recovery](https://en.wikipedia.org/wiki/Panic_mode)

### CRDT and Collaborative Editing
- Gentle et al. (2024) - [eg-walker: Mergeable Tree Structures](https://arxiv.org/abs/2409.14252)
- [diamond-types](https://github.com/josephg/diamond-types) — Rust reference implementation
- [Loro](https://loro.dev) — Production CRDT library; `TextDelta (Retain | Insert | Delete)`
- [Quill Delta format](https://quilljs.com/docs/delta/) — Retain/Insert/Delete with lengths

### MoonBit
- [MoonBit Language Reference](https://www.moonbitlang.com/docs/syntax)
- [MoonBit Core Libraries](https://mooncakes.io/docs/#/moonbitlang/core/)
```

**Step 2: Count lines and verify ≤450**

```bash
wc -l ROADMAP.md
```

Expected: ~220 lines (well under 450 limit).

**Step 3: Commit**

```bash
git add ROADMAP.md
git commit -m "docs: rewrite ROADMAP.md as framework-only (remove lambda concerns)"
```

---

### Task 2: Create `examples/lambda/ROADMAP.md`

**Files:**
- Create: `examples/lambda/ROADMAP.md`

**Step 1: Create the file with lambda-specific content extracted from old ROADMAP**

Write the following as `examples/lambda/ROADMAP.md`:

```markdown
# Roadmap: Lambda Calculus Example (`examples/lambda`)

**Updated:** 2026-03-03
**Status:** Active — Grammar Expansion in progress
**Goal:** A full-featured lambda calculus parser built on `dowdiness/loom` — the reference implementation for plugging a language into the framework, and the test bed for CRDT integration.

> Parser framework roadmap: [ROADMAP.md](../../ROADMAP.md)

---

## Current State

| Component | Status |
|-----------|--------|
| Recursive descent parser | ✅ Correct — `parse()`, `parse_tree()`, `parse_cst()` paths |
| Lexer | ✅ Correct — trivia-inclusive; emits `Whitespace` tokens |
| Error recovery | ✅ Complete — sync-point recovery, `ErrorNode`, diagnostics |
| Subtree reuse | ✅ Complete — via generic `ReuseCursor[T,K]` |
| `let x = e in body` bindings | ✅ Complete (2026-02-28) |
| Type annotations | Planned |
| Multi-expression files | Planned |
| Typed SyntaxNode views | Planned |
| CRDT integration | Research |

---

## Grammar Expansion

### Completed

- **`let` bindings** ✅ (2026-02-28) — `LetExpr` CST node, `Let`/`In` tokens, `parse_let_expr` in grammar — [notes](../../docs/archive/completed-phases/2026-02-28-grammar-expansion-let.md)

### Planned: Type Annotations

Add `: Type` syntax to lambda abstractions and let bindings:

```
λx : Int. x + 1
let f : Int -> Int = λx. x in f 1
```

**Exit criteria:** Type annotations parse correctly; CST round-trips to identical source text; reuse fires across annotated nodes.

### Planned: Multi-Expression Files

Top-level sequences of `let` bindings:

```
let id = λx. x
let const = λx. λy. x
```

**Key outcome:** Independent top-level subtrees make incremental reuse genuinely impactful — editing one binding won't re-parse any other.

**Exit criteria:** Multi-expression files parse; independent top-level subtrees verified by fuzz test; reuse count confirms no cross-boundary re-parse.

---

## Typed SyntaxNode Views

**Status:** Planned (Phase 3 of SyntaxNode-First Layer)

Typed wrappers over `SyntaxNode` — `LambdaExpr(SyntaxNode)`, `AppExpr(SyntaxNode)`, `LetExpr(SyntaxNode)` — so callers get structured tree access without pattern-matching raw `SyntaxKind` enums. `AstNode` becomes JSON-serialization-only.

---

## CRDT Exploration (Research)

**Status:** Research phase.
**Goal:** Integrate the incremental parser with CRDT-based collaborative editing.

**Recommended architecture:** Text-level CRDT + incremental parser on merge. Each peer maintains source text via a text CRDT (Fugue/RGA); after merging remote operations, the incremental parser re-parses the affected region. Avoids tree CRDTs entirely.

### What to Build

1. **Green tree diff utility:** Changed subtrees with positions, using pointer equality for O(1) unchanged-subtree skips.

2. **Text CRDT adapter:** Translate CRDT operations into `Edit`:
   ```
   TextDelta (Retain | Insert | Delete)   ← Loro/Quill Delta format
     ↓ .to_edits()
   Edit { start, old_len, new_len }       ← lengths, not endpoints
     ↓ implements
   pub trait Editable                     ← ImperativeParser accepts T : Editable
   ```
   `Delete(n)` → `old_len = n`, `Insert(s)` → `new_len = s.length()`, `Retain(n)` → advance cursor.

3. **Integration test harness:** Two simulated peers; verify identical text and parse trees after sync.

**Exit criteria:** Green tree diff tested; `TextDelta.to_edits()` values implement `Editable`; two-peer convergence test passing.

---

## Cross-Cutting Concern: Incremental Correctness

**Invariant:** For any edit, incremental parse must produce a tree structurally identical to full reparse.

Verified via `imperative_differential_fuzz_test.mbt` — random source + random edits → compare incremental vs full reparse. Grammar Expansion tasks must extend the oracle when new constructs are added.

---

## Milestones

| Milestone | Status |
|-----------|--------|
| `let` bindings | ✅ Complete (2026-02-28) |
| Type annotations | Future — Confidence: High |
| Multi-expression files | Future — Confidence: High |
| Typed SyntaxNode views | Future — Confidence: High |
| CRDT exploration | Future — Confidence: Low-Medium (research) |
```

**Step 2: Commit**

```bash
git add examples/lambda/ROADMAP.md
git commit -m "docs: add examples/lambda/ROADMAP.md (lambda-specific roadmap)"
```

---

### Task 3: Update `docs/README.md` and validate

**Files:**
- Modify: `docs/README.md`

**Step 1: Add an "Examples" section linking to the lambda ROADMAP**

In `docs/README.md`, add the following section after the "Architecture Decisions" section and before "Active Plans":

```markdown
## Examples

- [../examples/lambda/ROADMAP.md](../examples/lambda/ROADMAP.md) — lambda calculus grammar expansion plans, CRDT exploration
```

**Step 2: Run docs validation**

```bash
bash check-docs.sh
```

Expected output: `All checks passed.`

Note: `check-docs.sh` only checks files under `docs/` for index coverage — `examples/lambda/ROADMAP.md` is outside `docs/` so it won't appear in the coverage check. The link is navigational only.

**Step 3: Commit**

```bash
git add docs/README.md
git commit -m "docs: link examples/lambda/ROADMAP.md from docs/README.md"
```

---

## Verification

After all tasks, run from the repo root:

```bash
bash check-docs.sh                    # expect: All checks passed
wc -l ROADMAP.md                      # expect: ~220 lines
wc -l examples/lambda/ROADMAP.md      # expect: ~100 lines
```

Confirm that `ROADMAP.md` contains no references to `parser.mbt`, `Grammar Expansion`, or `CRDT`:

```bash
grep -n "Grammar Expansion\|CRDT\|parser\.mbt\|lexer\.mbt\|incremental_parser\.mbt" ROADMAP.md
```

Expected: no output.
