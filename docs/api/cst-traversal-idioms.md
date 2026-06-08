# CST Traversal Idioms — when to use which

loom has **three** ways to walk a CST. They are not interchangeable; choosing
the wrong one is the most common traversal mistake. This guide says which to
reach for and why. See [../architecture/seam-model.md](../architecture/seam-model.md)
for the underlying `CstNode` (immutable, position-independent) / `SyntaxNode`
(positioned facade) two-tree model.

## TL;DR

| You need… | Use | Lives in |
|-----------|-----|----------|
| Source offsets and/or the language's typed kinds (AST lowering, diagnostics, rename, queries) | **`SyntaxNode` + `direct_*` queries** | `seam/syntax_node.mbt` |
| CST→AST lowering with incremental reuse across edits | **`CstFold`** (memoized positioned catamorphism) | `loom/src/core/cst_fold.mbt` |
| An offset-free structural value over the immutable tree (rare) | **`CstElement` combinators** (`transform` / `fold` / `map` / `Finder`) | `seam/cst_traverse.mbt` |

**Default to the first two.** The third is rarely the right answer (see below).

## 1. Positioned typed queries — `SyntaxNode` + `direct_*`

The idiom for almost all consumer code. `SyntaxNode` carries source offsets and
its `direct_child_of_kind` / `direct_token_of_kind` / `direct_elements_iter` /
`child_of_kind` helpers let you navigate by the language's typed kinds. Use this
whenever you need *where* something is in the source, or want to match on typed
syntax kinds — i.e. AST construction, diagnostics, rename, projection.

```moonbit
match node.direct_token_of_kind(HeadingMarkerToken.to_raw()) {
  Some(marker) => ...   // positioned, typed
  None => ...
}
```

## 2. `CstFold` — memoized positioned catamorphism

For CST→AST lowering that should reuse work across edits. You provide an
*algebra* `(SyntaxNode, recurse) -> Ast`; `CstFold` owns the tree walk and a
cache keyed on `CstNode.hash` (the structural, position-independent content
hash), so **unchanged subtrees are O(1) on cache hit** even after an edit shifts
their absolute position. This is how the `lambda` / `markdown` / `json` examples
lower their trees.

```moonbit
let cst_fold = CstFold::new(grammar.fold_node)   // algebra: (SyntaxNode, recurse) -> Ast
let ast = cst_fold.fold(syntax_root)
```

`CstFold` is where loom's incremental-reuse contract reaches semantics: the green
tree's structural hash drives both syntax reuse and fold-result reuse.

## 3. Position-independent `CstElement` combinators — rarely the answer

`seam/cst_traverse.mbt` exposes `transform`, `transform_fold`, `fold`, `map`,
`each`, `iter`, and the `Folder` / `TransformFolder` / `Finder` traits. They walk
the **position-independent** `CstNode` and hand back `RawKind`, not the language's
typed kind, and no offsets.

Prefer them only for a value that is genuinely offset-free *and* not already
served by `CstFold`. In practice that is a short list:

- **CST→source unparse** (reconstructing text from token text + structure —
  offsets are output, not input). Currently the only honest niche, and uncovered.
- Offset-free structural validation / search in tests (`Finder`, `fold`-to-Bool).

Do **not** reach for them for:

- **AST lowering** — needs offsets + typed kinds → use idiom 1 / 2.
- **Memoized structural attributes** — `CstFold`'s hash-keyed cache already does
  this; a separate fold+memo layer re-implements it (see issue #269).
- **Rendering that includes positions** — e.g. `SyntaxNode::to_json` emits
  `start`/`end`; that is positioned work → idiom 1.

> `each` / `iter` (generic depth-first traversal) are the exception within idiom 3
> — they see real use. It is the *catamorphism* sub-family (`transform` / `fold` /
> `Folder`) that has zero production consumers; see #269 for the keep-at-low-
> priority verdict.

## The principle

Position-independence is a property of the **data layer** (interning, structural
hashing, subtree reuse) and the **incremental engine** (`CstFold`'s hash cache,
and `@incr` downstream), *not* a user-facing traversal API. This matches
rust-analyzer: position-independence lives in rowan's green tree and salsa's query
cache, never in exposed green-tree folds. When you find yourself wanting a
position-independent fold, first check whether `CstFold` (idiom 2) already gives
you the reuse you were after.
