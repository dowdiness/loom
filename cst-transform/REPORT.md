# CST Transform Library — Feasibility Report

## Summary

**Recommendation: Adopt.** The library provides three API tiers:

1. **Trait + tuple struct (1.0x):** `Folder` / `TransformFolder` / `Finder` with single-element tuple struct newtypes. Identical to hand-written recursion.
2. **MutVisitor (1.66x for 3 props):** Allocate accumulator once, mutate in place. Best for multi-property metadata computation in a single pass.
3. **Closure methods (1.10x–1.35x):** `transform`, `fold`, `map`, `each`, `iter`. Best for general-purpose CST operations.

## What We Learned

### 1. MoonBit has zero-cost abstractions — but only through a specific pattern

**Trait + single-element tuple struct = hand-written performance.** The compiler unboxes the newtype (`NodeCount(Int)` IS `Int` at runtime) and statically dispatches trait methods (direct calls, no vtable). Combined, this eliminates all abstraction overhead.

```moonbit
struct NodeCount(Int)  // unboxed at runtime
pub impl Folder for NodeCount with fold_combine(self, other) {
  NodeCount(self.0 + other.0)  // compiles to raw Int addition
}
```

### 2. Allocation is the dominant cost, not dispatch

| Overhead source | Impact | Evidence |
|----------------|--------|---------|
| Struct allocation per node | **3–4x** | Named struct `{ val: Int }` allocates on every `fold_combine` |
| `Array[R]` per branch | **~3x** | `transform` allocates Array for trivial Int work |
| Multi-element tuple struct | **~4x** | `#valtype CstMeta(Int, Int, Int)` still allocates `{ _0, _1, _2 }` per node |
| Indirect closure dispatch | **~1.25x** | `call_ref` for closures — noticeable but small |
| Trait static dispatch | **0x** | Direct function call, same as hand-written |

We expected indirect calls to be the bottleneck. They aren't. **Heap allocation per node is 3–4x more expensive than indirect dispatch.**

### 3. The compiler does monomorphization but NOT inlining

| Optimization | Applied? | Impact |
|-------------|----------|--------|
| **Monomorphization** | YES | Separate function per concrete type (`transformGiE`, `transformGsE`) |
| **Trait static dispatch** | YES | Direct function call, no vtable lookup |
| **Single-element tuple struct unboxing** | YES | `NodeCount(Int)` eliminated — raw `Int` at runtime |
| **Closure inlining** | NO | `(a, b) => a + b` remains an indirect `call_ref` |
| **Named struct unboxing** | NO | Even with `#valtype` on wasm-gc target |
| **Multi-element struct unboxing** | NO | `#valtype CstMeta(Int, Int, Int)` still allocates |
| **Trait method body inlining** | NO | `fold_combine(a, b)` is a separate function call |

Knowing this lets you predict the performance of any abstraction without benchmarking.

### 4. Mutable visitor beats functional fold for multi-property computation

| Approach | Time | Per-node alloc | Traversals |
|----------|------|---------------|-----------|
| Hand-written (1 prop) | 240 µs | 0 | 1 |
| **MutVisitor (3 props, 1 pass)** | **399 µs** | **0** | **1** |
| 3× TransformFolder (3 props) | ~768 µs | 0 | 3 |
| #valtype CstMeta (3 props, 1 pass) | 1040 µs | 1 object | 1 |

MutVisitor's per-property cost (133µs) is lower than hand-written per-property cost (240µs) because the tree traversal is shared. **This is the right pattern for `CstNode::new()` integration.**

### 5. The right abstraction depends on the use case

| Use case | Winner | Overhead | Why |
|----------|--------|----------|-----|
| Single scalar (count, sum, hash) | Trait `Folder` + tuple struct | **1.0x** | Unboxed + static dispatch |
| Search/find | Trait `Finder` + tuple struct | **1.0x** | No result to allocate |
| Multi-property metadata | `MutVisitor` + mutable struct | **1.66x** | One alloc, N mutations, 1 traversal |
| String/AST building | Closure `transform` | **1.10x** | Real work dominates |
| Array collection | Closure `transform` | **1.16x** | Array alloc is real work |
| Ad-hoc queries | Closure `each`/`fold` | **1.25x–1.35x** | Ergonomics matter more |

No single pattern covers everything. The library needs all of them.

### 6. `for..in` with loop variables produces identical code to `let mut`

```moonbit
// Functional style
for child in children; acc = 0 { continue acc + f(child) } nobreak { acc }

// Imperative style
let mut acc = 0; for child in children { acc = acc + f(child) }; acc
```

Same compiled output. Use whichever reads better.

### 7. What MoonBit's compiler team could improve

Three optimizations that would simplify the API to a single pattern:

1. **Closure inlining** — inline `(a, b) => a + b` at call sites. Eliminates the 1.25x floor for all closure-based methods.
2. **Multi-element struct unboxing** — make `#valtype` work on wasm-gc. Eliminates the 4x overhead for multi-property functional folds.
3. **Trait method body inlining** — inline `fold_combine` into `accept_fold`. Would let named structs achieve 1.0x without the tuple struct workaround.

Any one of these would make the trait tier unnecessary for most use cases.

## Benchmark Results

Tree: `generate_large_cst(depth=8, branching=4)` ≈ 87,381 nodes.
Target: wasm-gc, `--release` mode.

### Single-property fold — all approaches

| Approach | Time | vs hand-written |
|----------|------|-----------------|
| **Trait TransformFolder (tuple struct)** | **289 µs** | **0.98x** |
| Hand-written recursion | 294 µs | 1.00x |
| **Trait Folder (tuple struct)** | **296 µs** | **1.01x** |
| Closure `fold` (Int) | 396 µs | 1.35x |
| Closure `transform_fold` | 424 µs | 1.44x |
| Trait Folder (named struct + `#valtype`) | 731 µs | 2.49x |
| Closure `transform` (Array[Int]) | 876 µs | 2.98x |

### Early-termination search — all approaches

| Approach | Time | vs hand-written |
|----------|------|-----------------|
| **Trait Finder (tuple struct)** | **0.04 µs** | **1.00x** |
| Hand-written recursion | 0.04 µs | 1.00x |
| Closure `each` | 0.05 µs | 1.25x |
| `iter` + `find_first` | 0.25 µs | 6.25x |

### Multi-property fold — all approaches

| Approach | Time | Properties | vs hand-written (1 prop) |
|----------|------|-----------|--------------------------|
| Hand-written (1 prop) | 240 µs | 1 | 1.00x |
| **MutVisitor** | **399 µs** | **3** | **1.66x (0.55x per prop)** |
| 3× TransformFolder | ~768 µs | 3 | 3.20x (1.07x per prop) |
| #valtype CstMeta | 1040 µs | 3 | 4.33x (1.44x per prop) |

### Closure-based method benchmarks

| Benchmark | Hand-written | transform | fold | each | transform_fold |
|-----------|-------------|-----------|------|------|----------------|
| **to_source** | 2.84 ms | 3.08 ms (1.10x) | — | — | — |
| **collect idents** | 3.82 ms | 4.42 ms (1.16x) | 6.06 ms (1.59x) | — | — |
| **find first ident** | 0.04 µs | — | — | 0.05 µs (1.25x) | — |
| **node count** | 294 µs | 876 µs (2.98x) | 396 µs (1.35x) | — | 424 µs (1.44x) |
| **full traversal** | — | — | — | 626 µs | — |

## API Surface

### Traits (zero-cost for hot paths)

| Trait | Method | Semantics |
|-------|--------|-----------|
| `Folder` | `accept_fold` | Monoid fold over leaves; branches contribute `fold_empty()` |
| `TransformFolder` | `accept_transform_fold` | Fold with branch kind; branches contribute `tf_init(kind)` |
| `Finder` | `find` | DFS search, returns first match |
| `Walker` | `accept_walk` | DFS walk with early termination |
| `MutVisitor` | `accept_visitor` | Imperative DFS, mutates visitor in place |

### Methods (ergonomic for general use)

| Method | Use case |
|--------|----------|
| `transform(on_token, on_node)` | Bottom-up, child results as `Array[R]` |
| `fold(on_token, combine, empty)` | Monoid accumulation, no Array |
| `transform_fold(on_token, init, on_child)` | Fused transform+fold, no Array |
| `transform_cps(on_token, on_children)` | CPS variant, streaming children |
| `map(f)` | GreenNode → GreenNode rewrite |
| `each(f)` | Callback DFS with early termination |
| `iter()` | Lazy `Iter[GreenNode]` for stdlib composition |

### Decision guide

```text
Need zero-cost scalar fold (hot path)?      → Trait Folder/TransformFolder + tuple struct
Need zero-cost search (hot path)?           → Trait Finder + tuple struct
Need multi-property metadata (hot path)?    → MutVisitor + mutable struct
Need child results as Array?                → transform
Need scalar accumulation (general)?         → fold or transform_fold
Need GreenNode → GreenNode?                 → map
Need lazy composition (.filter/.take)?      → iter
Need early termination (general)?           → each
```

**Warning:** `fold`'s `empty` parameter is shared by reference across recursive calls. Use only immutable/value-type accumulators (Int, String). For mutable accumulators (Array), use `transform` instead.

## Integration Plan for seam/

### Step 1: Port closure methods to `CstElement`

```moonbit
pub fn[R] CstElement::transform(self, on_token, on_node) -> R { ... }
pub fn[R] CstElement::fold(self, on_token, combine, empty) -> R { ... }
pub fn CstElement::each(self, f) -> Bool { ... }
pub fn CstElement::iter(self) -> Iter[CstElement] { ... }
pub fn CstElement::map(self, f) -> CstElement { ... }
```

### Step 2: Use MutVisitor for `CstNode::new()` metadata

Replace the hand-written loop with a single-pass `MutVisitor`:

```moonbit
pub(all) struct CstNodeMeta {
  mut text_len : Int
  mut hash : Int
  mut token_count : Int
  mut has_any_error : Bool
}

pub impl MutVisitor for CstNodeMeta with visit_token(self, kind, text) {
  self.text_len = self.text_len + text.length()
  self.hash = combine_hash(self.hash, token_hash(kind, text))
  if not(is_trivia(kind)) { self.token_count = self.token_count + 1 }
}

pub impl MutVisitor for CstNodeMeta with visit_branch(self, kind) {
  if is_error(kind) { self.has_any_error = true }
}
```

This computes all 4 properties in one traversal at ~1.66x per-property — faster than 4 separate `accept_fold` passes (~3.2x) and competitive with hand-written.

### Step 3: Add trait-based folds for individual queries

| Property | Pattern | Use case |
|----------|---------|----------|
| `TextLen(Int)` | `Folder` | `text_len` recomputation after edit |
| `HasError(Bool)` | `Finder` | `has_errors()` check |
| `TokenCount(Int)` | `Folder` | Damage tracking |

### Step 4: Simplify SyntaxNode queries

| Current | Replace with |
|---------|-------------|
| `walk_children_flat()` (private, 6 callers) | Public `CstNode::each` |
| `find_token(kind)` | `Finder` trait or `each` |
| `has_errors()` | `Finder` trait |
| `rebuild_subtree()` | `CstElement::map` |
| `re_intern_tokens_only()` | `CstElement::map` |

### Step 5: Standard traversals for language authors

Downstream parsers (lambda, json) get a standard toolkit instead of hand-writing `for child in node.children()` loops.

### What NOT to change

- **`CstFold` (memoized catamorphism)** — orthogonal to traversal; keep the memoization layer
- **`balance_children`** — grammar-specific state machine
- **`splice_tree`** — path-based structural surgery

## Owned/View Type Separation — Analysis

### What we tested

We implemented `transform_view`: a shared `Array[R]` stack with `ArrayView[R]` slices to avoid per-branch `Array[R]` allocation.

**Result: slower than plain `transform`** (1.01ms vs 853µs for node count). In wasm-gc, small array allocations are cheap (nursery bump allocator). The view approach adds overhead from stack management, bounds-checked `ArrayView` indexing, and worse cache locality.

### Where seam ALREADY uses owned/view separation

seam's two-tree model IS this pattern:

| | Owned ("Array") | View ("ArrayView") |
|--|----------------|-------------------|
| **seam** | `CstNode` — immutable, position-independent, structurally shared | `SyntaxNode` — ephemeral positioned facade, created on demand |
| **Purpose** | Survives across edits, shared via structural hashing | Provides offset/parent context for one-time queries |

This is the red-green tree pattern from Roslyn/rust-analyzer. The "view" (`SyntaxNode`) is a lightweight wrapper `(CstNode, offset, parent?)` — no heap allocation for the tree structure itself.

### Where views WOULD help next: token text as source spans

Currently every `CstToken` copies its text:

```moonbit
// Current: owned string copy per token
pub(all) struct CstToken {
  kind : RawKind
  text : String      // ← heap-allocated copy of source substring
  hash : Int
}
```

With source-span views, tokens become zero-copy references into the source:

```moonbit
// Proposed: view into source text
pub(all) struct CstToken {
  kind : RawKind
  source : String    // shared reference to full source text
  start : Int
  end : Int          // text = source[start:end] — zero copy
  hash : Int
}
```

This is how rust-analyzer works — every token is a `TextRange(start, end)` into the source buffer. Benefits:

- **Zero string copying during lexing** — tokens just record their span
- **Less GC pressure** — one source string shared by all tokens instead of N string copies
- **Faster incremental re-lex** — changed span is a range comparison, not string equality

This requires lexer-level integration (the lexer must thread the source string through), so it's a seam-level change, not something this research module can prototype.

### Where views would NOT help

- **Children arrays** — `transform_view` benchmark proved this. GC allocation of small arrays is nearly free in wasm-gc. The nursery allocator bumps a pointer; the view's bounds checking + offset arithmetic costs more.
- **Incremental subtree reuse** — seam's `ReuseCursor` relies on identity-based sharing of `CstNode` subtrees. A flat arena representation would break this because subtrees can't be independently shared across edits.
- **Flat arena tree** — contiguous storage would improve cache locality for full traversals, but is incompatible with seam's incremental reuse model where subtrees survive across edits via structural sharing.

### Summary: GC runtime cost model differs from manual-memory languages

| Optimization | Manual-memory (Rust/C++) | GC runtime (wasm-gc) |
|-------------|-------------------------|---------------------|
| Avoid small allocations | High value — malloc/free is expensive | Low value — nursery bump is ~free |
| Use views/slices | High value — avoids copies | Mixed — bounds checking adds overhead |
| Flat arena layout | High value — cache locality + zero fragmentation | Low value — GC compaction already reduces fragmentation |
| String interning | Medium — avoids duplicate allocations | High — seam already does this via `Interner` |
| Source-span tokens | High — zero copy | **High — same benefit, biggest remaining opportunity** |

The key insight: in wasm-gc, **allocation is cheap but indirection is not free**. Optimize for fewer indirections (unboxed tuple structs, mutable visitors), not fewer allocations (views, arenas).

## File Structure

```text
cst-transform/
  moon.mod.json
  REPORT.md
  src/
    green_node.mbt          — Types + 7 closure-based methods
    traits.mbt              — 5 traits + accept methods + concrete impls
    green_node_wbtest.mbt   — 38 tests
    bench_wbtest.mbt        — 27 benchmarks
```
