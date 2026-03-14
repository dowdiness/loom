# Grammar Design for Incremental Computation

How grammar structure affects incremental parsing performance. Use this guide when designing or refactoring grammars that will be parsed incrementally.

**Related:**
- [incremental-overhead.md](incremental-overhead.md) — waste elimination opportunities in the reuse protocol
- [ADR: physical_equal interner](../decisions/2026-03-14-physical-equal-interner.md) — O(n²) → O(n) fix for nested trees

---

## Core Principle

**Incremental parsing wins when edits invalidate a small fraction of the CST.**

The incremental parser's `ReuseCursor` reuses subtrees that:
1. Match structurally (same `NodeKind`)
2. Pass leading/trailing token context checks
3. Do not overlap the damage range

Grammar shape determines how many nodes overlap a given edit. The ideal grammar produces trees where a single-character edit damages O(1) nodes, not O(n).

---

## Grammar Shapes: Good → Bad

### 1. Flat Siblings (Best)

```
SourceFile
├── LetDef("x", 0)
├── LetDef("y", 1)
├── LetDef("z", 2)
└── Expr(z)
```

**Example grammar:** `source_file → LetDef* Expr`

**Why it works:** Each `LetDef` is a sibling. Editing one LetDef damages only that node; all other siblings are outside the damage range and reusable in O(1) via `physical_equal`. For n definitions with a single edit, n-1 subtrees are reused.

**Incremental cost:** O(1) damaged nodes per edit. This is the optimal structure.

### 2. Left-Recursive / Iterative (Good for tail edits)

```
    Add
   /   \
  Add   3
 /   \
1     2
```

**Example grammar:** `expr → expr '+' term | term`

**Why it works for tail edits:** Appending `+ 4` at the end creates a new root `Add` node but the entire left subtree (`Add(Add(1,2),3)`) is outside the damage range and reusable as a single unit.

**Why it's bad for head edits:** Changing `1` to `9` at the start damages the leftmost leaf, but every ancestor up the left spine wraps that leaf. All spine nodes overlap the damage range.

**Incremental cost:** O(1) for tail edits, O(depth) for head edits.

### 3. Balanced Trees (Acceptable)

```
      Add
     /   \
   Add   Add
  / \   / \
 1   2 3   4
```

**Example:** Expression trees balanced by precedence levels.

**Why it works:** Any single edit damages at most O(log n) spine nodes (the path from the edited leaf to the root). Sibling subtrees at each level are reusable.

**Incremental cost:** O(log n) damaged nodes per edit.

### 4. Right-Recursive with Tail Edits (Worst)

```
LetExpr
├── name: x0
├── init: 0
└── body: LetExpr          ← spans to end
         ├── name: x1
         ├── init: 0
         └── body: LetExpr  ← spans to end
                   └── ...
```

**Example grammar:** `let_expr → 'let' ID '=' expr 'in' let_expr | expr`

**Why it fails:** Every `LetExpr` node's text span extends to the end of the input. A single-character edit at the tail (changing the final literal) overlaps the damage range of **every spine node**. The incremental parser must re-execute the grammar for all n levels, gaining nothing over full reparse while paying reuse-protocol overhead (cursor management, `collect_old_tokens`, trailing context checks).

**Incremental cost:** O(n) damaged nodes per edit — same as full reparse, plus overhead.

---

## Decision Matrix

| Grammar Shape | Tail Edit | Head Edit | Middle Edit | Recommended? |
|---------------|-----------|-----------|-------------|-------------|
| Flat siblings | O(1) | O(1) | O(1) | Yes |
| Left-recursive | O(1) | O(depth) | O(depth) | Yes for append-heavy |
| Balanced | O(log n) | O(log n) | O(log n) | Acceptable |
| Right-recursive | O(n) | O(1) | O(n) | Avoid |

---

## Practical Guidelines

### Prefer flat structure for statement-level constructs

Instead of nesting let-expressions as a right-recursive chain, parse them as flat siblings:

```
// Bad: right-recursive
let_expr → 'let' ID '=' expr 'in' let_expr

// Good: flat siblings
source_file → let_def* expr
let_def     → 'let' ID '=' expr 'in'
```

Both produce the same semantic AST (`Let(x, init, body)`). The difference is purely in CST structure.

### Use left-recursion for binary operators

Binary operators are naturally left-recursive in most grammars. This is already the right shape — editing the rightmost operand (the most common case during typing) reuses the entire left subtree.

### When right-recursion is unavoidable

Some constructs are inherently right-recursive (e.g., function types `A → B → C`). Options:

1. **Accept it** if nesting depth is bounded (e.g., type annotations rarely exceed 5-10 levels).
2. **Fall back to full reparse** when detected. If incremental overhead exceeds savings, skipping the reuse protocol is faster.
3. **Flatten in the CST** even if the semantic structure is recursive. Parse `A → B → C` as `arrow_type → type ('→' type)*` and reconstruct right-associativity in the CST→AST fold.

### Measure, don't guess

Use `get_last_reuse_count()` to check how many subtrees the incremental parser actually reuses. If reuse count is near zero, the grammar shape may not be incremental-friendly for that edit pattern.

---

## Loom-Specific Notes

- **`source_file_grammar`** (flat `LetDef*`) is the incremental-optimized grammar for the lambda calculus editor. Use it instead of `lambda_grammar` (right-recursive `let_expr`) when incremental performance matters.
- **`physical_equal` in `CstNode::Eq`** is critical for efficient reuse. Without it, even reusable subtrees pay O(subtree) equality cost during interning. See the [ADR](../decisions/2026-03-14-physical-equal-interner.md).
- **Overhead sources** (token buffer copy, upfront CST walk, event round-trip) add constant-factor cost per reuse attempt. These matter most when reuse yields trivial savings (small leaf nodes). See [incremental-overhead.md](incremental-overhead.md).
