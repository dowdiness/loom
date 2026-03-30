# Port Closure Methods + Finder to CstElement (#57)

**Status:** Complete
**Issue:** #57

## Goal

Port the proven traversal methods from `cst-transform/` research module to seam's `CstElement`, giving downstream parsers a standard traversal toolkit.

## API Surface

7 closure methods + 1 trait:

```moonbit
pub fn[R] CstElement::transform(self, on_token: (CstToken) -> R, on_node: (RawKind, Array[R]) -> R) -> R
pub fn[R] CstElement::fold(self, on_token: (CstToken) -> R, combine: (R, R) -> R, empty: R) -> R
pub fn[R] CstElement::transform_fold(self, on_token: (CstToken) -> R, init: (RawKind) -> R, on_child: (RawKind, R, R) -> R) -> R
pub fn CstElement::each(self, f: (CstElement) -> Bool) -> Bool
pub fn CstElement::iter(self) -> Iter[CstElement]
pub fn CstElement::map(self, f: (CstElement) -> CstElement) -> CstElement

pub(open) trait Finder { check(Self, CstElement) -> Bool }
pub fn[F : Finder] CstElement::find(self, f: F) -> CstElement?
```

## Design Decisions

**Callback style:** `on_token` receives `CstToken` (not destructured `RawKind, String`). More idiomatic for seam; callers access `.kind` and `.text`. Asymmetry with `on_node: (RawKind, Array[R])` is intentional since `on_node` receives transformed children, not a `CstNode`.

**`map` reconstruction:** After recursively mapping children, constructs `CstNode::new(node.kind, mapped_children)` without optional kind classifiers (trivia_kind, error_kind, incomplete_kind default to None). Callers needing accurate metadata can pass those optionals. Matches `with_replaced_child` precedent.

**Excluded:** `transform_cps`, `transform_view` (report showed no win). Trait-based folds (`Folder`, `TransformFolder`, `Walker`, `MutVisitor`) are #58/#59.

## Translation Rules

| cst-transform | seam |
|---------------|------|
| `Leaf(kind, text)` | `Token(token)` — pass `token` to callback |
| `Branch(kind, children)` | `Node(node)` — use `node.kind`, `node.children` |
| `GreenNode` in signatures | `CstElement` |
| `TokenKind` / `SyntaxKind` | `RawKind` (both) |

## File Layout

| File | Content |
|------|---------|
| `seam/cst_traverse.mbt` | 7 closure methods + `Finder` trait + `find` |
| `seam/cst_traverse_test.mbt` | Blackbox tests |

## Acceptance Criteria

1. All 7 methods + Finder trait compile: `cd seam && moon check`
2. Tests pass: `cd seam && moon test`
3. Interface updated: `cd seam && moon info`
4. No existing tests broken
5. API visible in `pkg.generated.mbti`

## Performance Reference

From cst-transform benchmarks (87K node tree, wasm-gc --release):

| Method | Overhead vs hand-written |
|--------|------------------------|
| `transform` | 1.10x |
| `fold` | 1.35x |
| `each` | 1.25x |
| `transform_fold` | 1.44x |
