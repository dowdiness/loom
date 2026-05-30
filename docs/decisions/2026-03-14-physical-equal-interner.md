# ADR: Add `physical_equal` Fast-Path to CstNode/CstToken Equality

**Date:** 2026-03-14
**Status:** Accepted

## tl;dr

- Context: Parsing 320-deep let chains showed O(n²) scaling. The node interner's equality check (`CstNode::Eq`) recursed into the full subtree for every interned node.
- Decision: Add `physical_equal(self, other)` as the first check in `CstNode::Eq` and `CstToken::Eq`.
- Rationale: Interned children are canonical references. `physical_equal` turns recursive O(subtree) comparisons into O(1), reducing total interning cost from O(n²) to O(n).
- Consequence: 320-let initial parse went from 3.72ms to 662µs (5.6x) while the generic parser used global node/token interners. Scaling ratio improved from 12x to 4.8x (near-linear).

## 2026-05-30 update

Issue #61 changed `CstToken` to store source spans and moved the generic parser off process-global node/token interners, because global interners would retain historic source buffers when canonical nodes contain span-backed tokens. Parser-owned reuse now rebuilds reused token spans against the current source buffer so old full source strings are not retained. The `physical_equal` fast path remains correct and useful for explicit `build_tree_interned` / `build_tree_fully_interned` callers and for interned subtrees.

## 2026-05-30 #187 update

Parser-owned reuse now emits `EventBuffer::push_parser_reuse_node_rebased_unchecked` after `ReuseCursor` has validated the old subtree against the current token stream. This skips the checked `push_parser_reuse_node_rebased` text-match pass but still rebuilds fresh `CstToken`s and `CstNode`s with spans into the current source, so it does not direct-splice stale nodes or retain old source buffers.

Benchmark gate (`seam/event_bench_wbtest.mbt`): matching-source `push_parser_reuse_node_rebased` measured ~140µs on wasm-gc and ~199µs on JS for a 50×100-token reuse tree; the parser-owned unchecked path measured ~104µs on wasm-gc and ~125µs on JS. Since source-span rebasing must allocate current-source tokens and ancestors, generic parser clients must not rely on stable `physical_equal(new_cst, old_cst)` across parses. Downstream change detection should use structural equality or explicit projection/domain identity.

## 2026-05-30 #186 update

Seam now exposes backing-source and parser-owned rebase capabilities under explicit unstable names before stabilization: `CstToken::unsafe_backing_source`, `EventBuffer::push_parser_reuse_node_rebased`, and `EventBuffer::push_parser_reuse_node_rebased_unchecked`. The older `CstToken::source` and `push_reuse_node_at*` names are deprecated compatibility aliases. See [ADR: Harden seam Source-Span Token and Parser Reuse APIs](2026-05-30-seam-source-span-api-hardening.md).

## The problem

The CRDT editor generates deeply nested let chains:

```
let x0 = 0 in let x1 = 0 in ... let x319 = T in x319
```

This forms a right-recursive CST where each `LetExpr` wraps the rest of the chain as its body child. Benchmarks showed superlinear scaling:

| Size | Initial parse time | Scaling |
|------|--------------------|---------|
| 80 lets | 310 µs | — |
| 320 lets | 3.72 ms | 12x for 4x input |

For truly linear parsing, 4x input should yield ~4x time.

## Root cause analysis

At the time of this ADR, the parser used process-global interners (`core_interner`, `core_node_interners` in `loom/src/core/interners.mbt`). The interners accumulated across benchmark iterations and editor parse cycles. On repeated parses:

1. `build_tree_fully_interned` constructs each node bottom-up and calls `NodeInterner::intern_node(node)`.
2. `intern_node` does `HashMap.get(node)` which calls `CstNode::Hash` (O(1), cached) then `CstNode::Eq` when a hash-bucket match is found.
3. `CstNode::Eq` compared `hash` → `kind` → `children.length()` → each child via `CstElement::Eq`.
4. `CstElement::Eq` for `Node(a), Node(b)` recursed into `CstNode::Eq` again.

For a right-recursive tree at depth n:

```
LetExpr(depth=0)            ← Eq walks all n levels
  └─ LetExpr(depth=1)       ← Eq walks n-1 levels
       └─ LetExpr(depth=2)  ← Eq walks n-2 levels
            └─ ...
```

- Equality cost at depth d: O(n - d)
- Total: O(n) + O(n-1) + ... + O(1) = **O(n²)**

## Why children are canonical references

For explicit `build_tree_fully_interned` callers (and for the generic parser before the 2026-05-30 source-span-token change), events are processed bottom-up:

1. Tokens are interned first → canonical `CstToken` references.
2. Inner nodes are interned before their parents → canonical `CstNode` references.
3. When a parent node is constructed, its `children` array contains only canonical references.

When `CstNode::Eq` compares a freshly built node against its stored counterpart in the interner, the children on *both sides* are the same canonical heap objects. `physical_equal` exploits this.

## The fix

Add `physical_equal(self, other)` as the first check in three places:

```moonbit
// CstToken::Eq
pub impl Eq for CstToken with equal(self, other) {
  if physical_equal(self, other) { return true }  // ← NEW
  if self.hash != other.hash { return false }
  self.kind == other.kind && self.text() == other.text()
}

// CstNode::Eq
pub impl Eq for CstNode with equal(self, other) {
  if physical_equal(self, other) { return true }  // ← NEW
  if self.hash != other.hash { return false }
  // ... existing structural comparison
}
```

With this change, the child-by-child comparison in `CstNode::Eq` terminates at each child in O(1) (since both sides hold the same canonical reference). Per-node cost becomes O(children_count), which is a grammar constant. Total: **O(n)**.

## Measured results

```
| Benchmark (initial parse) | Before  | After  | Speedup |
|---------------------------|---------|--------|---------|
| 80 lets                   | 310 µs  | 137 µs | 2.3x    |
| 320 lets                  | 3.72 ms | 662 µs | 5.6x    |
| 320/80 scaling ratio      | 12x     | 4.8x   | —       |
```

The 4.8x ratio for 4x input is near-linear (the residual is constant-factor overhead from allocation and cache effects, not algorithmic).

## Where this matters beyond benchmarks

The same O(n²) → O(n) improvement applies to real editor usage:

- **`ImperativeParser::accept_tree`** compares `old_cst == new_cst` to skip AST rebuild. For an unchanged document, this was O(n²) on deeply nested trees.
- **Successive edits** rebuild spine nodes and re-intern them. The interner compares against previously stored nodes. With `physical_equal`, unchanged subtrees short-circuit immediately.

## Files changed

| File | Change |
|------|--------|
| `seam/cst_node.mbt` | `physical_equal` in `CstToken::Eq`, `CstNode::Eq` |
| `seam/node_interner.mbt` | Updated doc: equality cost, `physical_equal` invariant |
| `loom/src/core/interners.mbt` | Updated doc: accumulation and equality cost |
| `examples/lambda/src/benchmarks/let_chain_benchmark.mbt` | Added scaling analysis |

## Alternatives considered

1. **Clear interners per parse session.** Would eliminate cross-iteration accumulation but lose the deduplication benefit for incremental parsing. The interner's purpose is that structurally unchanged subtrees share memory across edits.

2. **Per-parser interners instead of process-global.** Would isolate benchmark iterations but break subtree sharing across successive edits within the same parser. Also wouldn't help `accept_tree`'s `old_cst == new_cst` comparison.

3. **Hash-only equality (skip structural check).** Risk of silent corruption on hash collisions. The FNV-based hash is 32-bit; collision probability grows with interner size.

`physical_equal` is the minimal, zero-risk fix that preserves all existing semantics while eliminating the quadratic pathology.
