# Roadmap: Lambda Calculus Example (`examples/lambda`)

**Updated:** 2026-03-05
**Status:** Active — Grammar Expansion complete; next: Type Annotations
**Goal:** A full-featured lambda calculus parser built on `dowdiness/loom` — the reference implementation for plugging a language into the framework, and the test bed for CRDT integration.

> Parser framework roadmap: [ROADMAP.md](../../ROADMAP.md)

---

## Current State

| Component | Status |
|-----------|--------|
| Recursive descent parser | ✅ Correct — `parse()`, `parse_source_file_term()`, `parse_cst()` paths |
| Lexer | ✅ Correct — trivia-inclusive; emits `Whitespace` tokens |
| Error recovery | ✅ Complete — sync-point recovery, `ErrorNode`, diagnostics |
| Subtree reuse | ✅ Complete — via generic `ReuseCursor[T,K]` |
| `let x = e in body` bindings | ✅ Complete (2026-02-28) |
| `Term::Error(String)` variant | ✅ Complete (2026-03-05) |
| Multi-expression files | ✅ Complete (2026-03-05) |
| Type annotations | Planned |
| Typed SyntaxNode views | ✅ Complete (2026-03-03) |
| CRDT integration | ✅ Complete (2026-03-03) |

---

## Grammar Expansion

### Completed

- **`let` bindings** ✅ (2026-02-28) — `LetExpr` CST node, `Let`/`In` tokens, `parse_let_expr` in grammar — [notes](../../docs/archive/completed-phases/2026-02-28-grammar-expansion-let.md)
- **Multi-expression files** ✅ (2026-03-05) — `parse_source_file`/`parse_source_file_term`; `LetDef`/`SourceFile` CST nodes; top-level `let` sequences right-folded into nested `Let` terms; independent subtree reuse verified by fuzz test — [design](../../docs/archive/completed-phases/2026-03-04-multi-expression-files-design.md) · [impl](../../docs/archive/completed-phases/2026-03-04-multi-expression-files.md)

### Planned: Type Annotations

Add `: Type` syntax to lambda abstractions and let bindings:

```
λx : Int. x + 1
let f : Int -> Int = λx. x in f 1
```

**Exit criteria:** Type annotations parse correctly; CST round-trips to identical source text; editing only the type annotation of `λx : Int. x + 1` leaves the body node reused (reuse count > 0, body node unchanged).

---

## Typed SyntaxNode Views ✅ Complete (2026-03-03)

**Status:** Complete — [design](../../docs/archive/completed-phases/2026-03-03-typed-syntax-node-views-design.md) · [impl](../../docs/archive/completed-phases/2026-03-03-typed-syntax-node-views.md)

Typed wrappers over `SyntaxNode` — `LambdaExprView`, `AppExprView`, `LetExprView`, etc. — give callers structured tree access without pattern-matching raw `SyntaxKind` enums. `syntax_node_to_term` replaces the old `AstNode`-based path. The `AstView` trait is exported from `loom/core` for other grammars to follow the same pattern.

---

## CRDT Exploration ✅ Complete (2026-03-03)

**Status:** Complete (2026-03-03).
**Goal:** Integrate the incremental parser with CRDT-based collaborative editing.

**Recommended architecture:** Text-level CRDT + incremental parser on merge. Each peer maintains source text via a text CRDT (Fugue/RGA); after merging remote operations, the incremental parser re-parses the affected region. Avoids tree CRDTs entirely.

### What Was Built

1. ✅ **Green tree diff utility:** `tree_diff(old, new) -> Array[Edit]` in `loom/src/core/diff.mbt` — uses `CstNode.hash` as O(1) skip key for unchanged subtrees.

2. ✅ **Text CRDT adapter:** `text_to_delta(old, new) -> Array[TextDelta]` in `loom/src/core/delta.mbt` — translates string pairs to minimal Retain/Delete/Insert sequences; `to_edits()` converts these to `Edit` structs for the parser.

3. ✅ **Integration test harness:** `crdt_peer_test.mbt` (two simulated peers), `crdt_egw_test.mbt` (real event-graph-walker CRDT) — both verify identical text and parse trees after sync.

**Exit criteria met:** Green tree diff tested; `text_to_delta` + `to_edits` round-trip verified; two-peer convergence tests passing with both simulated and real CRDT ops.

---

## Cross-Cutting Concern: Incremental Correctness

**Invariant:** For any edit, incremental parse must produce a tree structurally identical to full reparse.

Verified via `imperative_differential_fuzz_test.mbt` — random source + random edits → compare incremental vs full reparse. Grammar Expansion tasks must extend the oracle when new constructs are added.

---

## Milestones

| Milestone | Status |
|-----------|--------|
| `let` bindings | ✅ Complete (2026-02-28) |
| Multi-expression files | ✅ Complete (2026-03-05) |
| `Term::Error` variant | ✅ Complete (2026-03-05) |
| Typed SyntaxNode views | ✅ Complete (2026-03-03) |
| CRDT exploration | ✅ Complete (2026-03-03) |
| Type annotations | Future — Confidence: High |
