# Memoized CST Fold — Design Document

**Date:** March 8, 2026
**Status:** Complete
**Scope:** `loom/src/`, `loom/src/core/`, `loom/src/pipeline/`, `seam/`, `examples/lambda/`

## Goal

Add a framework-owned memoized catamorphism (`CstFold[Ast]`) over CstNode, so that CST → AST conversion is incremental — unchanged subtrees reuse cached Ast results at O(1) per subtree.

## Motivation

### The Damage Information Cliff

Loom has three incremental stages for construction (anamorphism):

| Stage | Mechanism | Cost |
|-------|-----------|------|
| Lex | TokenBuffer retokenizes damage region | O(damaged tokens) |
| Parse | ReuseCursor skips unchanged subtrees | O(depth + damaged nodes) |
| **Fold** | **None — full re-conversion every time** | **O(tree size)** |

After a 1-character edit, the lexer retokenizes ~3 tokens and the parser rebuilds ~5 nodes. Then `to_ast` re-converts the entire tree. The fold is the bottleneck.

### Why the Framework Must Own It

Currently `Grammar.to_ast : (SyntaxNode) -> Ast` is a monolithic function where the language author owns both the per-node logic and the recursion. The framework can't memoize what it can't see.

By separating the **algebra** (per-node logic, language-author-owned) from the **recursion** (tree walk + memoization, framework-owned), the framework gains control over caching without changing what the language author writes.

## Design

### Core Primitive: `CstFold[Ast]`

```
pub struct CstFold[Ast] {
  algebra : (SyntaxNode, (SyntaxNode) -> Ast) -> Ast
  cache : Map[Int, Ast]           // CstNode.hash -> fold result
  stats : FoldStats
}

pub struct FoldStats {
  reused : Int          // cache hits (subtrees skipped)
  recomputed : Int      // cache misses (algebra called)
  unvisited : Int       // node-children the algebra didn't recurse into
}
```

### Algebra Signature

The language author provides:

```
fold_node : (SyntaxNode, (SyntaxNode) -> Ast) -> Ast
```

- First parameter: the current node (for kind-matching, typed views, leaf text access)
- Second parameter: framework-provided `recurse` function (handles memoization)
- Returns: the Ast value for this node

The language author calls `recurse` on child nodes instead of recursing manually. Typed views (LambdaExprView, etc.) work unchanged.

### Fold Algorithm

Top-down traversal with cache check, framework-verified child visitation:

```
fold(node):
  if cache.has(node.cst.hash):
    stats.reused += 1
    return cache[node.cst.hash]

  visited : Set[SyntaxNode] = {}
  recurse = fn(child) {
    visited.add(child)
    fold(child)
  }

  result = algebra(node, recurse)
  cache[node.cst.hash] = result
  stats.recomputed += 1

  // Verification: fold unvisited node-children for cache warming
  for child in node.node_children():
    if child not in visited:
      stats.unvisited += 1
      fold(child)

  return result
```

Key properties:

- **Top-down**: cache check at each node before recursing. Unchanged subtrees are skipped at O(1).
- **Hash-keyed**: CstNode structural hash is the cache key. Position-independent by construction — satisfies context-freedom law.
- **Verified**: framework tracks which children the algebra visited. Unvisited node-children are still folded (cache warming), ensuring future edits in those subtrees hit warm cache.
- **Mark-and-sweep eviction**: after each fold, entries whose hash doesn't appear in the new tree are evicted to prevent unbounded cache growth.

### Cache Key: CstNode Structural Hash

CstNode already computes a structural content hash from `(kind, children, text)`. This hash is:

- **Position-independent**: same subtree at different positions has the same hash
- **Content-sensitive**: any structural change produces a different hash
- **O(1) comparison**: integer equality

This makes the fold result context-free by construction: the cache maps structure to meaning, not position to meaning. Structurally identical subtrees (e.g., `λx.x` appearing twice) share a single cache entry.

### Integration with ReactiveParser

`CstFold` replaces bare `to_ast` inside the reactive pipeline:

```
BEFORE:
  Signal[String] -> Memo[CstStage] -> Memo[Ast]
                                       ^ calls to_ast(root) from scratch

AFTER:
  Signal[String] -> Memo[CstStage] -> Memo[Ast]
                                       ^ calls CstFold.fold(root)
                                         cache persists across invocations
```

The `CstFold` instance lives inside `ReactiveParser` alongside `cst_memo` and `term_memo`. When `term_memo` recomputes, it uses the fold (with cache from the previous run).

Backdating continues to work: if the fold produces the same Ast as before (via `Eq` on Ast), downstream memos don't recompute.

### Grammar Interface Change

```
BEFORE:
  pub struct Grammar[T, K, Ast] {
    ...
    to_ast : (SyntaxNode) -> Ast
    ...
  }

AFTER:
  pub struct Grammar[T, K, Ast] {
    ...
    fold_node : (SyntaxNode, (SyntaxNode) -> Ast) -> Ast
    ...
  }
```

### Three Composed Layers of Incrementality

After this change, a single character edit flows through:

| Layer | What reruns | What's skipped |
|-------|-------------|----------------|
| Lex | ~3 tokens retokenized | All tokens outside damage region |
| Parse | ~5 CstNodes rebuilt | All subtrees passing ReuseCursor's 4-condition check |
| **Fold** | **~5 algebra calls (rebuilt nodes + ancestors to root)** | **All subtrees with cached hash** |

Total cost for a typical edit: **O(depth)** across all three layers, not O(tree size).

## Anamorphism Discipline Compliance

The fold output (Raw Ast) satisfies the four laws:

| Law | Status | Mechanism |
|-----|--------|-----------|
| Completeness | Pass | SyntaxNode provides full access to all tokens, text, trivia |
| Context-freedom | Pass by construction | Cache key = structural hash (position-independent) |
| Uniform errors | Pass | ErrorNode flows through algebra; language author maps to error variant |
| Transparency | Pass | Ast is what the algebra returns; framework adds no hidden state |

## Scope Boundary

This design handles **structural conversion** (CST → Raw AST) — a pure, context-free catamorphism.

**Not in scope:**
- Context-dependent semantic analysis (name resolution, type checking) — these need top-down context that breaks hash-keyed caching. They remain separate passes, potentially using incr primitives.
- Cross-tree dependency tracking (Salsa-style queries) — an incr concern.
- Bidirectional editing (AST → text projection) — a separate problem.

## Migration Example (Lambda Calculus)

The diff is mechanical — replace manual recursion with `recurse`:

```
BEFORE:
  fn view_to_term(node) {
    match node.kind() {
      LambdaExpr => {
        let body = view.body().map(view_to_term)   // manual recursion
        ...

AFTER:
  fn lambda_algebra(node, recurse) {
    match node.kind() {
      LambdaExpr => {
        let body = view.body().map(recurse)         // framework-provided
        ...
```

Everything else — typed views, error handling, pattern matching — stays identical.

## References

- [Incremental Hylomorphism](../architecture/Incremental-Hylomorphism.md) — theoretical foundations (sections 2, 7)
- [Anamorphism Discipline Guide](../architecture/anamorphism-discipline.md) — four laws, boundary audit
- [Position-Independent Tokens](./2026-03-06-position-independent-tokens.md) — related: making tokens cacheable
- ADR 2026-02-27: Remove TokenStage Memo — explains why token-level memo was vacuous
