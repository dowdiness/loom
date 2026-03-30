# CST Transform Library — Feasibility Report

## Summary

**Recommendation: Conditionally adopt.** The library functions `transform`, `fold`, and `map` are viable for most CST use cases. `iter` has high overhead for early-termination patterns. `fold` has a safety footgun with mutable `empty` values that must be documented.

## Test Results

| Test Suite | Count | Status |
|------------|-------|--------|
| transform tests | 5 | All pass |
| fold tests | 4 | All pass |
| map tests | 3 | All pass |
| iter tests | 4 | All pass |
| Practical examples (Task 3) | 6 | All pass |
| API design tests | 4 | All pass |
| CPS variant tests | 4 | All pass |
| **Total** | **32** | **All pass** |

## Benchmark Results

Tree: `generate_large_cst(depth=8, branching=4)` ≈ 87,381 nodes (65,536 leaves + 21,845 internal).
Target: wasm-gc, `--release` mode.

### 1. to_source (String reconstruction)

| Variant | Time | Ratio vs hand-written |
|---------|------|----------------------|
| Hand-written | 2.89 ms | 1.00x |
| `transform` | 3.29 ms | **1.14x** |
| `transform_cps` | 3.23 ms | **1.12x** |

**Verdict: PASS.** String operations dominate; Array[String] allocation for children is negligible relative to StringBuilder work.

### 2. Identifier collection (Array[String])

| Variant | Time | Ratio vs hand-written |
|---------|------|----------------------|
| Hand-written | 4.00 ms | 1.00x |
| `transform` | 4.96 ms | **1.24x** |
| `fold` (non-mutating combine) | 6.54 ms | **1.64x** |

**Verdict: PASS.** Both within 2x. `transform` is faster than `fold` for Array collection because `transform` allocates one Array per node while `fold`'s non-mutating combine copies arrays at every combine step (O(n²) total).

### 3. Early termination (find first Ident)

| Variant | Time | Ratio vs hand-written |
|---------|------|----------------------|
| Hand-written recursive | 0.04 µs | 1.00x |
| `iter` + `find_first` | 0.24 µs | **6.0x** |

**Verdict: FAIL (6.0x).** The stack-based `Iter` implementation allocates an `Array` as an explicit stack and wraps each step in a closure. For this extreme case (first leaf of a deep tree), the overhead is visible. However, both are sub-microsecond; the absolute cost is negligible for real workloads.

### 4. Node count (trivial per-node Int work)

| Variant | Time | Ratio vs hand-written |
|---------|------|----------------------|
| Hand-written | 375 µs | 1.00x |
| `fold` (Int) | 403 µs | **1.07x** |
| `transform_cps` | 879 µs | **2.35x** |
| `transform` | 930 µs | **2.48x** |

**Verdict: `fold` PASS, `transform`/CPS FAIL for trivial Int ops.** When per-node work is minimal (just `+1`), `transform`'s Array[R] allocation per branch dominates. `fold` avoids this and is near-optimal. CPS saves only ~5% vs `transform` — closure allocation replaces array allocation with similar cost.

### 5. fold vs transform for token count (Int)

| Variant | Time | Ratio |
|---------|------|-------|
| `fold` (Int) | 403 µs | 1.0x |
| `transform` (Array[Int]) | 1.04 ms | 2.58x |
| `transform_cps` (closure) | 1.16 ms | 2.88x |

`fold` is the clear winner for pure accumulation. The Array[Int] allocation in `transform` and closure allocation in CPS are both wasteful when children results don't need to be collected.

### 6. Map identity

| Variant | Time |
|---------|------|
| `map` (identity) | 1.19 ms |

No green-node sharing optimization — `map` always reconstructs the tree even when `f` returns the input unchanged. A structural-equality check could short-circuit this but would add overhead to the common (non-identity) case.

## CPS Variant Assessment

**Verdict: Not recommended as primary API.**

`transform_cps` provides only marginal improvement (~5%) over `transform` for Int operations, and is actually slower for token counting (1.16ms vs 1.04ms). The callback-based API is also harder to use:

```moonbit
// transform — straightforward
transform(node, on_token, fn(kind, children) { ... children[0] ... })

// transform_cps — requires manual accumulation
transform_cps(node, on_token, fn(kind, each_child) {
  let mut acc = ...
  each_child(fn(r) { acc = f(acc, r) })
  acc
})
```

For the rare case where per-node work is trivial and Array allocation matters, `fold` already provides the zero-allocation path. Providing both `transform` and `fold` covers the design space; CPS adds complexity without a clear performance win.

## API Design Findings

### Type Inference

MoonBit correctly infers `R` for both `transform` and `fold` from callback return types. No explicit type annotations needed at call sites in normal usage. When callbacks return polymorphic types (e.g., empty `Array`), an annotation like `([] : Array[String])` is needed — this is expected MoonBit behavior.

### Closure Capture

Closures in `on_token`/`on_node`/`combine` correctly capture outer variables. No type errors or lifetime issues observed.

### Composability

- `transform` result → `iter` → `find_first`: works naturally
- `map` → `to_source`: works naturally
- `Result[R, E]` in callbacks: early return with `Err` propagates correctly through `transform`
- Nested transforms: work as expected

### fold + mutable empty: FOOTGUN

**Critical finding:** `fold`'s `empty` parameter is shared by reference across all recursive calls. If `combine` mutates its arguments (e.g., `fn(a, b) { a.append(b); a }` for `Array`), the shared `empty` array gets corrupted, producing exponentially wrong results.

**Mitigation options:**
1. **Document clearly** that `combine` must be non-mutating for reference types
2. Change `empty` to a factory `() -> R` (breaks ergonomics for value types)
3. Restrict `fold` to `R : Copy` (MoonBit doesn't have this trait)

**Recommendation:** Option 1 (documentation) is sufficient. The `fold` function is designed for monoidal accumulation with value types (Int, String). For Array collection, `transform` is the correct tool.

## Criteria Evaluation

| Criterion | Result |
|-----------|--------|
| 4 functions pass all tests | **YES** (32/32) |
| Performance ≤ 2.0x vs hand-written | **PARTIAL** — `transform` 1.14x, `fold` 1.07x-1.64x (PASS). `iter` 6.0x (FAIL, but absolute cost negligible). `transform` for Int: 2.48x (FAIL, use `fold` instead). |
| Type inference works naturally | **YES** |
| `transform` vs `fold` distinction clear | **YES** — `transform` when you need child results as a collection; `fold` when accumulating a single value |

## Recommendation

**Adopt `transform`, `fold`, and `map`. Reconsider `iter`.**

- **`transform`**: Excellent for String/AST operations (1.12x-1.24x overhead). Use when the per-node work is non-trivial or you need individual child results.
- **`fold`**: Near-optimal for numeric accumulation (1.07x). Use when combining children into a single scalar value.
- **`map`**: Clean API for GreenNode→GreenNode transformations. No performance baseline needed (no equivalent hand-written pattern is simpler).
- **`iter`**: The 6x overhead for early termination is a concern. Consider providing a recursive `find_first` helper instead, or document that `iter` is best for full traversals, not early-exit searches.
- **`transform_cps`**: Not recommended for public API. The ~5% improvement doesn't justify the ergonomic cost.

For integration with `seam/`, the functions would operate on `CstElement`/`CstNode`/`CstToken` instead of the simplified `GreenNode`. The core pattern (match leaf/branch, recurse, combine) transfers directly.
