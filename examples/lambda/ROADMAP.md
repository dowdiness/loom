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
