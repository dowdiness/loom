# CST Transform Library — Feasibility Report

## Summary

**Recommendation: Adopt.** The library provides two API tiers:

1. **Trait-based (zero cost):** `Folder` / `TransformFolder` / `Finder` traits with single-element tuple struct newtypes achieve **1.0x** — identical to hand-written recursion.
2. **Closure-based (ergonomic):** `transform`, `fold`, `map`, `each`, `iter` with 1.10x–1.35x overhead. Best for general-purpose CST operations.

## Test Results

36 tests + 26 benchmarks, all passing.

## Benchmark Results

Tree: `generate_large_cst(depth=8, branching=4)` ≈ 87,381 nodes.
Target: wasm-gc, `--release` mode.

### All approaches compared (node count)

| Approach | Time | vs hand-written |
|----------|------|-----------------|
| **Trait TransformFolder (tuple struct)** | **289 µs** | **0.98x** |
| Hand-written recursion | 294 µs | 1.00x |
| **Trait Folder (tuple struct)** | **296 µs** | **1.01x** |
| Closure `fold` (Int) | 396 µs | 1.35x |
| Closure `transform_fold` | 424 µs | 1.44x |
| Trait Folder (named struct + `#valtype`) | 731 µs | 2.49x |
| Closure `transform` (Array[Int]) | 876 µs | 2.98x |

### All approaches compared (find first ident, early termination)

| Approach | Time | vs hand-written |
|----------|------|-----------------|
| **Trait Finder (tuple struct)** | **0.04 µs** | **1.00x** |
| Hand-written recursion | 0.04 µs | 1.00x |
| Closure `each` | 0.05 µs | 1.25x |
| `iter` + `find_first` | 0.25 µs | 6.25x |

### Closure-based benchmark matrix

| Benchmark | Hand-written | transform | fold | each | transform_fold |
|-----------|-------------|-----------|------|------|----------------|
| **to_source** | 2.84 ms | 3.08 ms (1.10x) | — | — | — |
| **collect idents** | 3.82 ms | 4.42 ms (1.16x) | 6.06 ms (1.59x) | — | — |
| **find first ident** | 0.04 µs | — | — | **0.05 µs (1.25x)** | — |
| **node count** | 294 µs | 876 µs (2.98x) | 396 µs (1.35x) | — | **424 µs (1.44x)** |
| **full traversal** | — | — | — | **626 µs** | — |
| **map identity** | — | — | — | — | 1.10 ms |

## Key Discovery: Zero-Cost Abstractions in MoonBit

Single-element tuple structs are **guaranteed unboxed at runtime**. Combined with trait static dispatch (monomorphization + direct calls), this produces code identical to hand-written recursion:

```moonbit
// Newtype — guaranteed unboxed: NodeCount IS Int at runtime
pub(all) struct NodeCount(Int)

// Defunctionalized algebra — static dispatch, no indirect calls
pub impl Folder for NodeCount with fold_token(_kind, _text) { NodeCount(1) }
pub impl Folder for NodeCount with fold_combine(self, other) { NodeCount(self.0 + other.0) }
pub impl Folder for NodeCount with fold_empty() { NodeCount(0) }

// Usage — 1.0x performance
let count : NodeCount = tree.accept_fold()
```

### Why this works / why other approaches don't

| Struct type | Runtime representation | Per-call overhead |
|-------------|----------------------|-------------------|
| `struct T(Int)` (tuple, 1 element) | Raw `Int` (unboxed) | Zero — raw addition |
| `struct T { val: Int }` (named) | Object with `.val` field | Heap allocation per call |
| `struct T { val: Int }` + `#valtype` | Still object on wasm-gc | Same heap allocation |
| Closure `(a, b) => a + b` | Indirect `call_ref` | ~1.25x from indirect dispatch |

### Compiler analysis (from JS output)

| Optimization | Applied? |
|-------------|----------|
| **Monomorphization** | YES — separate function per concrete type |
| **Trait static dispatch** | YES — direct function call, no vtable |
| **Tuple struct unboxing (1 element)** | YES — eliminated at compile time |
| **Closure inlining** | NO — closures remain as indirect function pointers |
| **Named struct unboxing** | NO — even with `#valtype` on wasm-gc |
| **Trait method body inlining** | NO — method call exists but operates on raw primitives |

## API Surface

### Traits (1.0x — for hot paths)

| Trait | Method | Use case |
|-------|--------|----------|
| `Folder` | `accept_fold` | Monoid fold over leaves (text_len, token_count, hash) |
| `TransformFolder` | `accept_transform_fold` | Fold with branch kind access (node_count, has_errors) |
| `Finder` | `find` | DFS search with early termination (find_token, find_error) |
| `Walker` | `accept_walk` | DFS walk with early termination (generic visitor) |

**Folder vs TransformFolder semantics:**
- `Folder`: branches contribute `fold_empty()` — only counts/accumulates leaves
- `TransformFolder`: branches contribute `tf_init(kind)` — can count branches too

### Methods (1.10x–1.44x — for general use)

| Method | Use case |
|--------|----------|
| `transform(on_token, on_node)` | Bottom-up with Array[R] of child results |
| `fold(on_token, combine, empty)` | Monoid accumulation without Array |
| `transform_fold(on_token, init, on_child)` | Fused transform+fold, no Array |
| `transform_cps(on_token, on_children)` | CPS variant, streaming children |
| `map(f)` | GreenNode → GreenNode structural rewrite |
| `each(f)` | Callback DFS with early termination |
| `iter()` | Lazy `Iter[GreenNode]` for stdlib composition |

### Decision guide

```text
Need zero-cost numeric fold (hot path)?  → Trait Folder/TransformFolder + tuple struct
Need zero-cost search (hot path)?        → Trait Finder + tuple struct
Need child results as Array?             → transform
Need scalar accumulation (value types)?  → fold or transform_fold (with kind)
Need GreenNode → GreenNode?              → map
Need lazy composition (.filter/.take)?   → iter
Need early termination (general)?        → each
```

**Warning:** `fold`'s `empty` parameter is shared by reference across recursive calls. Use only immutable/value-type accumulators (Int, String). For mutable accumulators (Array), use `transform` instead.

## Integration Plan for seam/

### Step 1: Port methods to `CstElement` / `CstNode` / `CstToken`

Add the same methods to seam's real CST types. The patterns transfer directly — replace `GreenNode::Leaf`/`Branch` matches with `CstElement::Token`/`Node` matches:

```moonbit
// In seam/
pub fn[R] CstElement::transform(self, on_token, on_node) -> R { ... }
pub fn[R] CstElement::fold(self, on_token, combine, empty) -> R { ... }
pub fn CstElement::each(self, f) -> Bool { ... }
pub fn CstElement::iter(self) -> Iter[CstElement] { ... }
pub fn CstElement::map(self, f) -> CstElement { ... }
```

### Step 2: Add trait-based folds for CstNode metadata

Replace hand-written loops in `CstNode::new()` (`seam/cst_node.mbt:170-224`) with `Folder` trait impls:

| Property | Current | After |
|----------|---------|-------|
| `text_len` | Hand-written loop summing child lengths | `TextLen(Int)` + `Folder` impl |
| `token_count` | Loop with trivia filter | `TokenCount(Int)` + `Folder` impl (skip trivia in `fold_token`) |
| `hash` | FNV-1a accumulation loop | `HashAccum(Int)` + `Folder` impl |
| `has_any_error` | Loop with kind matching | `HasError(Bool)` + `Finder` impl |

All at **1.0x** via tuple struct unboxing. The constructor becomes:

```moonbit
pub fn CstNode::new(kind, children, trivia_kind?, error_kind?, incomplete_kind?) -> CstNode {
  let text_len : TextLen = children.accept_fold()   // 1.0x
  let token_count : TokCount = children.accept_fold() // 1.0x
  let hash : HashVal = children.accept_fold()         // 1.0x
  let has_error = children.find(ErrorFinder(error_kind, incomplete_kind)).is_some()
  { kind, children, text_len: text_len.0, hash: hash.0, token_count: token_count.0, has_any_error: has_error }
}
```

### Step 3: Extract `walk_children_flat` into public `each`

Replace the private `walk_children_flat` helper in `seam/syntax_node.mbt:193-223` (duplicated across 6 methods) with a public `CstNode::each` that handles RepeatGroup transparency.

### Step 4: Simplify SyntaxNode queries with `find`

| Current function | Location | Replace with |
|-----------------|----------|-------------|
| `find_token(kind)` | `syntax_node.mbt:321-352` | `Finder` trait or `each` |
| `has_errors()` | `cst_node.mbt:343-361` | `Finder` trait |
| `find_at(offset)` | `syntax_node.mbt:578-611` | `find` with offset predicate |

### Step 5: Use `map` for tree rewriting

| Current function | Location | Replace with |
|-----------------|----------|-------------|
| `rebuild_subtree()` | `event.mbt:288-300` | `CstElement::map` |
| `re_intern_tokens_only()` | `event.mbt:314-329` | `CstElement::map` |
| `re_intern_subtree()` | `event.mbt:346-369` | `CstElement::map` |

### Step 6: Provide standard traversals for language authors

Lambda and JSON examples currently hand-write `for child in node.children()` loops. With the standard API, downstream parsers get:

```moonbit
// Any language — source text reconstruction
let source = root_element.transform(
  (_kind, text) => text,
  (_kind, children) => children.join(""),
)

// Any language — find first error
let error = root_element.find(ErrorFinder(error_kind))

// Any language — collect all tokens of kind
let idents = root_element.fold(
  (kind, text) => if kind == ident_kind { [text] } else { [] },
  (a, b) => { a.append(b); a }, // safe: fold creates fresh arrays
  [],
)
```

### What NOT to change

- **`CstFold` (memoized catamorphism in loom/)** — already excellent. The memoization layer is orthogonal. Keep it.
- **`balance_children`** — grammar-specific state machine, not a generic fold.
- **`splice_tree`** — path-based structural surgery, not a traversal.
- **`CstNode::new()` constructor** — could use traits for metadata, but the current hand-written loop computes 4 properties in a single pass. Replacing with 4 separate `accept_fold` calls would traverse the children 4 times. Only replace if profiling shows the single-pass advantage is negligible, or if a multi-property `Folder` newtype is introduced (e.g., `struct Metadata(Int, Int, Int, Bool)`).

## File Structure

```text
cst-transform/
  moon.mod.json
  REPORT.md
  src/
    green_node.mbt          — Types (GreenNode, TokenKind, SyntaxKind) + 7 closure-based methods
    traits.mbt              — 4 traits (Folder, TransformFolder, Finder, Walker) + accept methods + concrete impls
    green_node_wbtest.mbt   — 36 tests
    bench_wbtest.mbt        — 26 benchmarks + hand-written baselines
```
