# E-Graph Module TODOs

## Implementation Progress

- [x] Step 1: Union-Find
- [x] Step 2: EGraph core (add, union, rebuild)
- [x] Step 3: E-Matching (ENodeRepr, Pat, ematch, search, instantiate)
- [x] Step 4: Rewrite Rules (Rewrite, apply_rewrite)
- [x] Step 5: Extraction (CostFn, RecExpr, extract)
- [x] Step 6: Runner (equality saturation loop)
- [x] Step 7: lambda-opt example
- [x] Step 8: E-Class Analysis

## Future Work

### API Design

- [ ] **Pattern helper functions**: Add `var()`, `node()`, `atom()` constructors for programmatic Pat building without s-expression parsing
- [ ] **Labelled arguments for `rewrite()`**: Use `rewrite(name~, lhs~, rhs~)` to prevent parameter transposition
- [ ] **Richer `apply_rewrite` return type**: Consider struct/enum with match count, filtered count, and union count instead of raw `Int`

### Performance

- [ ] **`merge_substs` allocation**: Replace `a_map.copy()` with mutable substitution + backtracking or persistent map with structural sharing
- [ ] **`ematch` array allocations**: Pre-allocate buffers or use stack-based approach instead of fresh `Array[Subst]` per recursion level
- [ ] **`search` visited set**: Evaluate whether `HashSet` dedup is needed if `search` is always called post-rebuild
- [ ] **Benchmark suite**: Add benchmarks for `add` throughput, `rebuild` scaling, `ematch` per rule, saturation time (Step 7)
- [ ] **Extraction: Dijkstra worklist**: Replace full-scan fixed-point with priority-queue approach for O(n log n) extraction
- [ ] **Extraction: lazy map_children**: Avoid materializing canonical nodes until cost improves, reducing N×P allocations
- [ ] **Extraction: array-indexed costs**: Replace `Map[Id, Int]` with `Array[Int?]` for O(1) dense-integer lookup
