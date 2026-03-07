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

---

## 14. Runner: node_limit Counts UF Slots, Not Live E-Classes

**Concern**: `EGraph::size()` returns `self.uf.size()` — the total number of Union-Find slots ever created. This counter grows monotonically (unions merge classes but never remove slots). The field name `node_limit` suggests a cap on e-nodes or e-classes, but it actually limits UF entries, which over-counts after merges.

**Current choice**: Use UF slot count — matches egg's `Runner` behavior and is cheap (O(1) lookup).

**Alternatives**:
- Track live e-class count separately (decrement on merge, increment on add)
- Use `self.classes.size()` (number of entries in the classes map) — more accurate but stale keys may inflate it
- Rename to `slot_limit` or `entry_limit` for clarity

**Why deferred**: The over-counting is conservative (stops earlier, not later), so it is safe. Egg uses the same approach. The difference only matters for very large e-graphs with many merges.

**Revisit when**: Users observe premature `NodeLimit` stops, or when e-graph size reporting is needed for diagnostics.

---

## 15. Runner: Unused `roots` Field

**Concern**: `Runner.roots` is accepted in the constructor and stored but never read by `Runner::run`. Tests pass `roots=` values that have no observable effect.

**Current choice**: Keep the field — planned for post-saturation convenience (e.g., `runner.extract_best(cost_fn)` that extracts from all roots).

**Alternatives**:
- Remove until needed (YAGNI)
- Wire up immediately: add `Runner::extract` that delegates to `EGraph::extract` for each root

**Why deferred**: The field costs nothing to carry and documents intent. Wiring it up requires deciding the extraction API shape, which is a Step 7 concern.

**Revisit when**: Step 7 (lambda-opt example) needs post-saturation extraction from the Runner.

---

## 16. Runner: Unused `Rewrite.name` Field

**Concern**: `Rewrite.name` is set in the `rewrite()` constructor but never read — not in `apply_rewrite`, not in `Runner::run`, not in any error or log message.

**Current choice**: Keep the field — standard in e-graph implementations for debugging, tracing, and diagnostics.

**Alternatives**:
- Remove until needed
- Use in `StopReason` (e.g., `Saturated { iterations: Int }`) or trace logging

**Why deferred**: The field is conventional in egg and egglog. It will be useful when adding iteration logging or rule-level statistics in Step 7/8.

**Revisit when**: Adding debug/trace output, or rule-level performance reporting.

---

## 17. Runner: TimeLimit Omitted (No Wall-Clock API)

**Concern**: The implementation plan included `TimeLimit` as a `StopReason` variant and `time_limit : Int64` on `Runner`. This was omitted because MoonBit's standard library does not expose a cross-platform monotonic clock.

**What TimeLimit would solve**:
- **Runaway saturation**: some rule sets (associativity + commutativity + distributivity) cause exponential e-graph growth. `NodeLimit` caps memory, but computation could spin for minutes before reaching it. `TimeLimit` guarantees the runner returns within a bounded duration.
- **Interactive/real-time use**: if the optimizer runs inside an editor or compiler, you want "best result within 100ms" rather than "perfect result eventually."

**Why omitted**: Implementing `TimeLimit` requires a monotonic clock (e.g., `System.nanoTime()`, `performance.now()`). MoonBit has no cross-platform clock API — it would need platform-specific FFI (`@wasm.performance_now()` for JS target, OS syscalls for native).

**Current mitigation**: `IterLimit` + `NodeLimit` together bound both computation and memory without needing a clock. Sufficient for research/educational use.

**Revisit when**: MoonBit adds a standard clock API, or when the e-graph is used in a latency-sensitive context (editor plugin, compiler pass).

---

## 18. Capability Traits for EGraph / AnalyzedEGraph

**Concern**: `EGraph[L]` and `AnalyzedEGraph[L, D]` share many operations (`find`, `union`, `rebuild`, `search`, `apply_matches`, `size`). Could capability traits (e.g., `Searchable`, `Rebuildable`, `EGraphCore`) abstract over them?

**Feasibility**: Six of eight shared methods use only concrete types (`Id`, `Pat`, `Subst`, `Rewrite`, `Int`) and are trait-compatible. Two methods (`add(Self, L) -> Id`, `extract(Self, Id, CostFn[L]) -> (Int, RecExpr[L])`) involve the generic `L` and **cannot** become traits in MoonBit (no type parameters on traits).

**Current choice**: No traits — direct methods on each type.

**Why deferred**:
- Only 2 implementors, and `AnalyzedEGraph` delegates to its inner `EGraph` (one-liner wrappers)
- `Runner` cannot be fully generic because it calls `add` (needs `L`), which the trait can't express
- Falls under the "Phantom Generality" anti-pattern: the trait would be correct but wouldn't reduce code or enable new compositions
- ~~A deeper gap exists: `AnalyzedEGraph::apply_matches` delegates to `EGraph`, so analysis hooks (`modify`) don't fire during rewriting.~~ **Resolved**: `AnalyzedEGraph` now has its own `instantiate` and `apply_matches` that route through `self.add`/`self.union`, ensuring analysis hooks fire.

**Revisit when**:
- A third e-graph variant appears (e.g., `InstrumentedEGraph` for benchmarking)
- `Runner` needs to work polymorphically with both `EGraph` and `AnalyzedEGraph`

---

## 19. AnalyzedEGraph::union Double `find`

**Concern**: `AnalyzedEGraph::union(a, b)` calls `self.find(a)` and `self.find(b)` to look up analysis data, then calls `self.egraph.union(a, b)` which internally calls `find(a)` and `find(b)` again — four redundant `find` calls total.

**Current choice**: Accept the double `find` — correct, simple, matches the `EGraph::union` API.

**Why deferred**: After path compression, subsequent `find` calls on the same Id are O(1). The constant factor is small and not worth an API change (e.g., adding an internal `union_roots` variant that skips re-find).

**Revisit when**: Profiling shows `union` as a bottleneck in analysis-heavy workloads.

---

## 20. AnalyzedEGraph::add Closure Allocation

**Concern**: `AnalyzedEGraph::add` creates a closure `fn(child) { self.get_data(child) }` on every call, passed to `analysis.make`. Each closure captures `self`. In a tight loop adding many nodes, this creates per-call garbage.

**Current choice**: Accept the closure — inherent to the callback-based `Analysis` design. The alternative would require restructuring `make` to accept the `AnalyzedEGraph` directly instead of a lookup function, coupling the analysis record to the e-graph type.

**Why deferred**: The allocation cost is small relative to hash-map operations in `add`. MoonBit's closure allocation strategy (stack vs heap) determines actual impact — without benchmarks, optimizing prematurely risks added complexity for uncertain gain.

**Revisit when**: Benchmarks show `add` throughput as a bottleneck, or MoonBit gains method references that avoid closure allocation.

---

## 21. Analysis `merge` Commutativity Not Enforced

**Concern**: `Analysis.merge` is documented as "Must be commutative" but this is not enforced. The constant-folding test implementations use `match (a, b) { (Some(x), _) => Some(x); ... }` which always picks `a` when both are `Some` — not truly commutative when `x != y`.

**Current choice**: Documentation-only contract. For constant folding, merged classes always have equal constant values (if both are `Some`), so the non-commutative path is unreachable in correct usage.

**Alternatives**:
- Add a debug assertion: `if x != y { abort("merge conflict") }`
- Use `min`/`max` for a truly commutative merge
- Add a `verify_merge` debug hook that checks `merge(a,b) == merge(b,a)`

**Why deferred**: The contract is correct for all current analyses. Enforcing commutativity would add runtime cost or require a testing framework for analysis properties.

**Revisit when**: Users define custom analyses where merge order matters, or when adding property-based testing for analysis correctness.

---

## 22. Runner Does Not Integrate with AnalyzedEGraph

**Concern**: `Runner[L]` holds an `EGraph[L]` and calls `self.egraph.search/apply_matches/rebuild` directly. There is no way to use `Runner` with an `AnalyzedEGraph[L, D]` — users must manually implement the equality saturation loop to get analysis-aware rewriting.

**Current choice**: No `AnalyzedRunner` — users call `AnalyzedEGraph::search/apply_matches/rebuild` manually.

**Alternatives**:
- `AnalyzedRunner[L, D]` that holds an `AnalyzedEGraph[L, D]` and implements the same loop
- Make `Runner` generic over an e-graph-like interface (blocked by concern #18 — capability traits)
- Add a `run` method directly on `AnalyzedEGraph` that takes rules and limits

**Why deferred**: The manual loop is straightforward (5-10 lines). Adding `AnalyzedRunner` would duplicate `Runner::run` logic. The right solution depends on whether capability traits (concern #18) become worthwhile.

**Revisit when**: Users need equality saturation with analysis, or when capability traits are introduced.

---

## 23. `recompute_data` Relaxation Pass Count is O(n)

**Concern**: `recompute_data` runs `pass_count = class_ids.length()` relaxation passes to propagate new child facts through parent nodes. For a chain of depth `d`, only `d` passes are needed. The current approach runs `n` passes (number of e-classes) even if convergence happens in 2.

**Current choice**: Use `n` passes — correct, simple, guarantees convergence for any e-graph topology.

**Alternatives**:
- Track whether any data changed during a pass and break early (fixed-point detection)
- Use a worklist/priority-queue ordered by topological depth
- Compute topological order once and do a single bottom-up pass (only works for acyclic e-graphs)

**Why deferred**: For research-scale e-graphs, the O(n^2) cost is acceptable. Early termination would add a comparison check per e-class per pass, requiring `D : Eq` — an additional trait bound not currently needed.

**Revisit when**: Benchmarks show `rebuild` as a bottleneck, or when e-graphs exceed ~1k classes.

---

## 24. Pat::parse Error Reporting

**Concern**: `Pat::parse` now rejects trailing input, empty operators, and invalid tokens with descriptive error messages. However, error messages do not include position information (character offset), making it harder to locate errors in long pattern strings.

**Current choice**: Simple string error messages — sufficient for short s-expression patterns.

**Alternatives**:
- Include character offset in error messages: `"expected operator name at position 5"`
- Return a structured error type with position, expected, and found fields

**Why deferred**: Pattern strings are typically short (< 50 chars). Position info adds parsing complexity for marginal benefit.

**Revisit when**: Pattern strings become long or are generated programmatically, making error localization important.

---

## 25. `canonical_class_ids` Duplicates `search` Visited-Set Pattern

**Concern**: `AnalyzedEGraph::canonical_class_ids()` and `EGraph::search()` both iterate `self.classes`, canonicalize each Id via `find()`, and deduplicate using a `HashSet`. A shared helper like `EGraph::canonical_ids() -> Array[Id]` could serve both.

**Current choice**: Keep them separate — they operate on different types (`EGraph` vs `AnalyzedEGraph`) and `search` does more than just collect Ids (it runs ematch per class).

**Why deferred**: Extracting to `EGraph` would require exposing it as a method, but it's only needed by `AnalyzedEGraph` (same package, so access is fine either way). The duplication is 8 lines of straightforward iteration — not enough to justify a new method on the core type.

**Revisit when**: A third call site appears, or `EGraph::rebuild` adopts the same pattern (currently it uses a different cleanup strategy).

---

## 26. `recompute_data` Map-Swap Per Pass

**Concern**: `recompute_data` allocates a fresh `next_data` map per relaxation pass, populates it, clears `self.data`, and copies entries back. Combined with the O(n) pass count (concern #23), this creates O(n) temporary map allocations and O(n^2) total entry copies.

**Current choice**: Accept the allocation — the map-swap ensures each pass reads from the previous pass's stable snapshot, avoiding read-after-write hazards from in-place updates.

**Alternatives**:
- In-place update with a "changed" flag (enables early termination too, but risks read-after-write within a pass)
- Two pre-allocated maps with pointer swap (avoids allocation, but MoonBit struct fields aren't reassignable)
- Single map with generation counters

**Why deferred**: Tied to the relaxation approach (concern #23). Fixing the O(n) pass count via early termination would proportionally reduce the map-swap cost, making it negligible. Solving the pass count is higher priority.

**Revisit when**: Concern #23 is addressed (early termination), and map allocation remains a measurable cost afterward.
