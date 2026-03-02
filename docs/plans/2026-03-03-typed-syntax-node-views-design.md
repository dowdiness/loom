# Design: Typed SyntaxNode Views

**Date:** 2026-03-03
**Status:** Approved — ready for implementation planning
**Author:** collaborative design session

---

## Goal

Replace the `AstNode`-based tree with a rust-analyzer-style typed view layer: thin newtype wrappers over `SyntaxNode` that give callers typed, semantic access to the CST without any separate tree allocation.

**Before (current):**
```
SyntaxNode → (cst_convert) → AstNode[positions+kind] → (node_to_term) → Term
```
Callers match raw `SyntaxKind` integers and index into `AstNode.children` by position.

**After (target):**
```
SyntaxNode → typed views (LambdaExprView, AppExprView, …)
```
The view layer IS the AST. No separate tree allocation. Navigation is typed and named.

---

## Motivation

- `cst_convert.mbt` matches raw `RawKind` integers and indexes children by position — brittle
- `AstNode` is a general tree with positional children; there's no type safety on which child is "the body" vs "the parameter"
- `AstNode.Eq` ignores positions (custom impl); this pattern is easy to get wrong
- `ReactiveParser` memoizes `Memo[AstNode]` which requires a custom Eq; the rust-analyzer model avoids this entirely by memoizing at the CST level (pointer equality via `NodeInterner`)

---

## Architecture

### Layer Overview

```
seam:     CstNode (immutable, position-free, interned)
          SyntaxNode (ephemeral positioned facade)
          SyntaxToken, SyntaxElement
              ↓ typed view layer
examples/lambda:
          LambdaExprView, AppExprView, BinaryExprView, IfExprView,
          LetExprView, ParenExprView, IntLiteralView, VarRefView
              ↓ evaluation
          Term (pure semantic, no positions)
```

### Memoization

`CstNode` is interned via `NodeInterner`. Two parses that produce the same tree structure produce pointer-equal `CstNode` values. `SyntaxNode.equal()` delegates to `CstNode` structural equality (which is pointer equality for interned nodes). A leading-space edit shifts positions but leaves the interned `CstNode` unchanged → `Memo[SyntaxNode]` correctly skips recomputation. No custom Eq tricks needed.

---

## Changes by Package

### seam (`seam/syntax_node.mbt`)

Two new navigation helpers:

```moonbit
/// Return the nth interior-node child (0-indexed, skipping tokens), or None.
pub fn SyntaxNode::nth_child(self : SyntaxNode, n : Int) -> SyntaxNode?

/// First interior-node child of the given raw kind, or None.
pub fn SyntaxNode::child_of_kind(self : SyntaxNode, kind : RawKind) -> SyntaxNode?
```

Generic JSON serialization:

```moonbit
/// Serialize to generic JSON: { "kind": Int, "start": Int, "end": Int, "children": [...] }
/// Useful for debugging. For semantic JSON, use typed view .to_json() methods.
pub impl ToJson for SyntaxNode with to_json(self) -> Json { ... }
```

### loom/core (`loom/src/core/lib.mbt`)

Minimal typed-view trait:

```moonbit
/// Marker trait for typed SyntaxNode view types.
/// Implement this for every view type in your language package.
/// Convention: also implement `pub fn ViewType::cast(n : SyntaxNode) -> Self?`
/// (cast cannot be in the trait because MoonBit traits require self as first param).
pub trait AstView {
  syntax_node(Self) -> @seam.SyntaxNode
}
```

Exported from `loom/src/loom.mbt`:
```moonbit
pub using @core { trait AstView }
```

### examples/lambda — new file: `src/views.mbt`

Eight typed view types. Each follows this template:

```moonbit
pub struct LambdaExprView { node : @seam.SyntaxNode }

pub fn LambdaExprView::cast(n : @seam.SyntaxNode) -> LambdaExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.LambdaExpr {
    Some({ node: n })
  } else {
    None
  }
}

pub impl @loom.AstView for LambdaExprView with syntax_node(self) { self.node }

/// The bound parameter name (e.g. "x" in λx. body).
pub fn LambdaExprView::param(self : LambdaExprView) -> String {
  self.node
    .find_token(@syntax.IdentToken.to_raw())
    .map(t => t.text())
    .unwrap_or("")
}

/// The body expression (first interior-node child).
pub fn LambdaExprView::body(self : LambdaExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

pub impl ToJson for LambdaExprView with to_json(self) -> Json {
  {
    "kind": "LambdaExpr",
    "param": self.param(),
    "start": self.node.start(),
    "end": self.node.end(),
    "body": self.body().map(n => n.to_json()).unwrap_or(Null),
  }
}
```

Full list of view types:

| Type | Methods |
|------|---------|
| `LambdaExprView` | `param() -> String`, `body() -> SyntaxNode?` |
| `AppExprView` | `func() -> SyntaxNode?`, `arg() -> SyntaxNode?` |
| `BinaryExprView` | `lhs() -> SyntaxNode?`, `rhs() -> SyntaxNode?`, `op() -> Bop?` |
| `IfExprView` | `condition()`, `then_branch()`, `else_branch()` all `-> SyntaxNode?` |
| `LetExprView` | `name() -> String`, `init() -> SyntaxNode?`, `body() -> SyntaxNode?` |
| `ParenExprView` | `inner() -> SyntaxNode?` |
| `IntLiteralView` | `value() -> Int?` |
| `VarRefView` | `name() -> String` |

### examples/lambda — `src/ast/ast.mbt`

**Delete:** `AstNode`, `AstKind`, `AstNode::new`, `AstNode::error`, `print_ast_node`, `node_to_term`
(these relied on the allocated tree pattern)

**Keep:** `Term`, `Bop`, `print_term`
Move `Term` and `Bop` to a simpler file if the `ast/` package becomes empty.

### examples/lambda — `src/cst_convert.mbt`

**Delete entirely.** Replaced by views.

Add a standalone `fn syntax_node_to_term(n : @seam.SyntaxNode) -> @ast.Term` in the root `src/` package that dispatches via view types (replaces the cst→ast→term path).

### examples/lambda — pipeline wiring

`ImperativeParser[Ast]` type parameter:
- **Before:** `Ast = @ast.AstNode`, `to_ast: SyntaxNode -> AstNode` (cst_convert call)
- **After:** `Ast = @seam.SyntaxNode`, `to_ast: SyntaxNode -> SyntaxNode` (identity)

`ReactiveParser` final memo:
- **Before:** `Memo[@ast.AstNode]`
- **After:** `Memo[@seam.SyntaxNode]`, equality via interned `CstNode` pointer equality

### examples/lambda — tests

All tests using `AstNode` assertions updated to use either:
- `SyntaxNode` navigation via views (for structural tests)
- `Term` via `syntax_node_to_term` (for semantic tests)
- `SyntaxNode.to_json()` or view `.to_json()` (for serialization tests)

---

## What Does NOT Change

- `loom/src/` framework API (`ImperativeParser`, `ReactiveParser`, `Grammar`, `Edit`, etc.)
- `seam/` CST primitives (`CstNode`, `SyntaxElement`, `EventBuffer`, interners)
- `incr/` reactive signals
- `loom/src/core/lib.mbt` parser infrastructure (`ParserContext`, `LanguageSpec`, etc.)
- `examples/lambda/src/lexer/`, `src/token/`, `src/syntax/`, `src/parser.mbt`, `src/grammar.mbt`
- Fuzz tests and property-based tests (reuse oracle unaffected)

---

## Success Criteria

1. All 293 existing `examples/lambda` tests pass (updated assertions where needed)
2. `AstNode` is fully deleted — no references remain in non-archive code
3. `cst_convert.mbt` is deleted
4. `LambdaExprView::cast(n)` correctly returns `None` for non-lambda nodes
5. `SyntaxNode.to_json()` and view `.to_json()` both produce valid JSON
6. `Memo[SyntaxNode]` correctly skips recomputation when the CST is unchanged (verified by reactive parser test with a whitespace-only edit)
7. `moon check && moon test` clean across all packages

---

## References

- [rust-analyzer syntax layer](https://github.com/rust-lang/rust-analyzer/blob/master/docs/dev/syntax.md)
- [Roslyn Red-Green Trees](https://ericlippert.com/2012/06/08/red-green-trees/)
- [ROADMAP.md — Typed SyntaxNode Views](../../ROADMAP.md#typed-syntaxnode-views)
- [docs/architecture/seam-model.md](../architecture/seam-model.md)
