# ADR: Add `physical_equal` Fast-Path to CstNode/CstToken Equality

**Date:** 2026-03-14
**Status:** Accepted

## tl;dr

- Context: Parsing 320-deep let chains showed O(n²) scaling. The node interner's equality check (`CstNode::Eq`) recursed into the full subtree for every interned node.
- Decision: Add `physical_equal(self, other)` as the first check in `CstNode::Eq` and `CstToken::Eq`.
- Rationale: Interned children are canonical references. `physical_equal` turns recursive O(subtree) comparisons into O(1), reducing total interning cost from O(n²) to O(n).
- Consequence: 320-let initial parse goes from 3.72ms to 662µs (5.6x). Scaling ratio improves from 12x to 4.8x (near-linear).

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

The parser uses process-global interners (`core_interner`, `core_node_interners` in `loom/src/core/interners.mbt`). The interners accumulate across benchmark iterations and editor parse cycles. On repeated parses:

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

`build_tree_fully_interned` processes events bottom-up:

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
  self.kind == other.kind && self.text == other.text
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
