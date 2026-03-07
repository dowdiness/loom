# E-Graph Design Concerns

Deferred decisions and trade-offs encountered during implementation. Each entry records the concern, the current choice, alternatives considered, and when to revisit.

---

## 1. Stringly-Typed Pattern API

**Concern**: `rewrite("name", "(Add ?x (Num:0))", "?x")` uses runtime-parsed strings. Typos are caught at runtime, not compile time. Three positional `String` parameters are easy to transpose.

**Current choice**: S-expression strings — standard in e-graph literature (egg, egglog), concise, familiar.

**Alternatives**:
- Direct `Pat` construction: `Node("Add", None, [Var("x"), ...])` — verbose but no parsing
- Helper functions: `node("Add", [var("x"), atom("Num", "0")])` — readable, no parsing
- Labelled arguments: `rewrite(name~, lhs~, rhs~)` — prevents transposition

**Why deferred**: Tag strings ("Add", "Num") are inherently strings because `Pat` is language-independent. Full type safety would require patterns parameterized by `L`, losing language-independence. The convenience/safety trade-off is acceptable at this stage.

**Revisit when**: Users report pattern typo bugs, or the API surface grows beyond simple arithmetic rules.

---

## 2. ENodeRepr vs Eq for Pattern Matching

**Concern**: Could we use the `Eq` trait instead of `ENodeRepr` for e-matching?

**Current choice**: `ENodeRepr` decomposes nodes into `(tag, payload)` for cross-type comparison with `Pat`.

**Why necessary**: `Eq` compares `L == L` (same type). E-matching compares `Pat` (language-independent) against `L` (language-specific) — different types. Cannot construct an `L` from a pattern without first knowing the children, which is what ematch is recursively discovering.

**Decision**: Not a deferred decision — `ENodeRepr` is architecturally required. Recorded here to explain the rationale.

---

## 3. Map[K, Unit] vs HashSet

**Concern**: Early code used `Map[K, Unit]` as a poor-man's set.

**Current choice**: Migrated to `@hashset.HashSet` — proper semantics, no wasted `Unit` values.

**Decision**: Resolved. No further action needed.

---

## 4. merge_substs Allocation Strategy

**Concern**: `merge_substs` calls `a_map.copy()` on every invocation in the ematch inner loop. For patterns with many variables × many matches, this creates O(|vars| × |combinations|) map copies.

**Current choice**: Copy-based merge — correct, simple, easy to reason about.

**Alternatives**:
- Mutable substitution with backtracking (undo log) — zero-copy, but complex control flow
- Persistent/immutable map with structural sharing — O(log n) per insert, shared prefixes
- Array-backed flat map for small substitutions — patterns typically have <10 variables, so linear scan may beat hash overhead

**Why deferred**: Correctness-first. The current implementation is clear and tested. Premature optimization without benchmark data risks added complexity for uncertain gain.

**Revisit when**: Step 7 benchmarks show ematch as a bottleneck, or when pattern variable counts exceed ~5.

---

## 5. Rebuild Fixed-Point Efficiency

**Concern**: `rebuild` clears `pending` at the start of each iteration and always performs a full memo rebuild, even on the final pass when no new congruences are found. This means one extra full pass over all e-classes.

**Current choice**: Simple fixed-point loop — correct and easy to verify.

**Alternatives**:
- Check `to_union.is_empty()` before applying and break early
- Track dirty e-classes instead of rescanning all classes
- Use a worklist of affected e-classes (egg's approach)

**Why deferred**: The extra pass cost is proportional to e-graph size, not a multiplicative factor. For research-scale e-graphs this is negligible.

**Revisit when**: Benchmarks show rebuild as a bottleneck for large e-graphs (>10k nodes).

---

## 6. search() Visited Set Necessity

**Concern**: `search` uses a `HashSet[Id]` to deduplicate canonical Ids. After `rebuild`, class keys should already be canonical — the visited set may be redundant.

**Current choice**: Keep the visited set — defensive correctness. The `classes` map may contain stale keys pointing to the same canonical Id if `search` is called without a preceding `rebuild`.

**Alternatives**:
- Remove the set and document that `search` requires a preceding `rebuild`
- Clean up stale keys during `rebuild` (remove old key, insert canonical key)

**Why deferred**: The HashSet cost is O(|classes|) — small relative to the ematch cost. Removing it saves a minor constant factor but introduces a subtle correctness precondition.

**Revisit when**: API contract is formalized (Step 6 Runner always calls rebuild before search).

---

## 7. Rewrite Condition Coupling

**Concern**: `condition : ((Subst) -> Bool)?` couples the rewrite rule to the concrete `Subst` type. If `Subst` representation changes, all condition lambdas break.

**Current choice**: Direct function type — simple, sufficient for current needs.

**Alternatives**:
- Wrap in a `Condition` trait or newtype
- Pass the e-graph to the condition for richer queries: `(EGraph[L], Subst) -> Bool`

**Why deferred**: `Subst` is a stable public type unlikely to change representation. The e-graph-aware condition variant is needed for Step 8 (e-class analysis) — address it then.

**Revisit when**: Step 8 (E-Class Analysis) requires conditions that inspect e-class data.

---

## 8. apply_rewrite Return Type

**Concern**: `apply_rewrite` returns `Int` (number of new unions). Callers cannot distinguish "no matches" from "matches but condition filtered all" from "matches but already equivalent."

**Current choice**: Raw `Int` — sufficient for the equality saturation loop (Step 6) which only cares about `applied == 0` for saturation detection.

**Alternatives**:
- `struct ApplyResult { matches: Int, filtered: Int, applied: Int }`
- `enum ApplyResult { NoMatches | AllFiltered | Applied(Int) }`

**Why deferred**: Over-engineering for current usage. Step 6 (Runner) will clarify what diagnostics are actually needed.

**Revisit when**: Step 6 Runner implementation, or when debugging rewrite rule behavior becomes painful.

---

## 9. Extraction Algorithm: Fixed-Point vs Worklist

**Concern**: `extract()` uses a naive fixed-point loop that scans all e-classes and all nodes on every pass. For acyclic e-graphs a single topological-order pass suffices. For cyclic e-graphs, a worklist/priority-queue (Dijkstra-style) approach would visit each e-class at most once in order of ascending cost.

**Current choice**: Full-scan fixed-point — simple, correct, easy to verify.

**Alternatives**:
- Dijkstra-style worklist: process e-classes in ascending cost order, O(n log n)
- Topological sort for acyclic case + fixed-point fallback for cyclic

**Why deferred**: The naive approach is O(iterations × nodes). For research-scale e-graphs this is acceptable. The extra complexity of a priority queue is not justified without benchmark data.

**Revisit when**: Step 7 benchmarks show extraction as a bottleneck, or e-graphs exceed ~10k nodes.

---

## 10. Extraction: map_children Allocation Per Node Per Iteration

**Concern**: In the `extract` fixed-point loop, `node.map_children(fn(child) { self.find(child) })` creates a new e-node on every call, even when the cost doesn't improve. With N nodes and P passes, this creates N×P throwaway allocations.

**Current choice**: Materialize canonical node for every evaluation — simple, matches the `rebuild` pattern.

**Alternatives**:
- Compute cost using `node.child(i)` with inline `self.find()`, only call `map_children` when updating `best_node`
- Cache canonical forms from a prior `rebuild` pass

**Why deferred**: For small e-graphs the allocation overhead is negligible. Avoiding `map_children` requires restructuring the cost function to accept raw children with a find-wrapping lookup, which complicates the `CostFn` interface.

**Revisit when**: Step 7 benchmarks show extraction allocation as a bottleneck.

---

## 11. Extraction: Map vs Array-Indexed Costs

**Concern**: `best_cost : Map[Id, Int]` and `best_node : Map[Id, L]` use hash-map lookups in the inner loop. Since `Id` values are dense integers from the Union-Find (0..n), array indexing (`Array[Int?]`, `Array[L?]`) would give O(1) access without hashing overhead.

**Current choice**: `Map[Id, Int]` — simple, no need to pre-size arrays.

**Alternatives**:
- `Array[Int?]` sized to `self.uf.size()` — O(1) lookup, no hash overhead
- Parallel arrays `Array[Int]` + `Array[L?]` with sentinel value for unset costs

**Why deferred**: Map overhead is small relative to `map_children` allocation cost. Array approach requires handling the "unset" case differently (sentinel vs Option).

**Revisit when**: After resolving concerns #10 and #9, if extraction remains a bottleneck.

---

## 12. Extraction: max_cost Sentinel as Silent Failure

**Concern**: `max_cost = 1_000_000_000` is used as both "not yet computed" during fixed-point and as the return value when the root has no best cost. Callers cannot distinguish "extraction succeeded with an expensive expression" from "extraction failed entirely."

**Current choice**: Return `max_cost` silently — works because all reachable e-classes will have a finite cost after the fixed-point.

**Alternatives**:
- Return `(Int, RecExpr[L])?` to make failure explicit
- `abort()` if root is unreachable (matching `reconstruct`'s behavior for missing nodes)

**Why deferred**: In practice, `extract` is always called on a root that was previously added to the e-graph, so the root will always have a best cost. The silent failure case is unreachable in correct usage.

**Revisit when**: `extract` is exposed as a public API, or when error reporting becomes important.

---

## 13. reconstruct Parameter Sprawl

**Concern**: `reconstruct` takes 5 parameters (`best_node`, `eclass_id`, `rec_nodes`, `id_to_idx`, `egraph`), three of which (`best_node`, `rec_nodes`, `id_to_idx`) are accumulated state that always travel together.

**Current choice**: Standalone function with explicit parameters — private helper, acceptable for now.

**Alternatives**:
- Bundle into `struct RecExprBuilder[L] { best_node, rec_nodes, id_to_idx, egraph }` with a `build(eclass_id)` method
- Make `reconstruct` a method on `EGraph` that takes the builder state

**Why deferred**: 5 parameters is acceptable for a private recursive helper called from one site. Bundling would add a struct definition for a single use.

**Revisit when**: `reconstruct` is reused from multiple call sites, or the parameter list grows further.
