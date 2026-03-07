# Parser Benchmarks

Performance benchmarks for the incremental parser implementation.

**Last measured:** 2026-03-06 (`moon bench --release`)

## Running Benchmarks

```bash
# Run all parser benchmarks (recommended, from repo root)
(cd examples/lambda && moon bench --release)

# Run all tests (non-benchmark tests only, from repo root)
moon test --package parser
```

**Note:** Use `moon bench` to run performance benchmarks. The `moon test` command runs functional tests only.

## Regression Guard

`bench-check.sh` compares a live benchmark run against a saved baseline and fails (exit 1) if any benchmark regresses more than 15%.

```bash
# Check for regressions (from repo root)
bash bench-check.sh

# Accept new performance as the baseline
bash bench-check.sh --update
```

The baseline is stored in `docs/performance/bench-baseline.tsv` (tab-separated: `name\tmean_ns`). Commit it after running `--update` so the CI boundary moves forward intentionally:

```bash
bash bench-check.sh --update
git add docs/performance/bench-baseline.tsv
git commit -m "perf: update bench baseline"
```

## Benchmark Categories

### 1. Basic Operations (`benchmark.mbt`)

**Full Parse Benchmarks:**
- Simple expression: `42`
- Lambda: `λx.x`
- Nested lambdas: `λf.λx.f (f x)`
- Arithmetic: `1 + 2 - 3 + 4`
- Complex: `λf.λx.if f x then x + 1 else x - 1`

**Incremental Parser:**
- Initial parse
- Small edits
- Multiple sequential edits
- Replacement edits

**CRDT Operations:**
- AST → CRDT conversion
- CRDT → source reconstruction

**Error Recovery:**
- Valid input parsing
- Error handling overhead

### 2. Scaling & Performance (`performance_benchmark.mbt`)

**Parse Scaling:**
- Small input (5 tokens)
- Medium input (15 tokens)
- Large input (30+ tokens)

**Incremental vs Full Reparse:**
- Edit at start
- Edit at end
- Edit in middle

**Sequential Edit Patterns:**
- Realistic typing simulation
- Backspace/delete simulation

**Damage Tracking:**
- Localized damage
- Widespread damage

**Worst/Best Cases:**
- Full document edit (worst)
- Cosmetic changes only (best)

### 3. Phase 1: Incremental Lexer (`performance_benchmark.mbt`)

Benchmarks for `TokenBuffer` incremental tokenization on a 110-token input
(`"1 + 2 + 3 + ... + 55"`: 55 integers + 54 plus operators + EOF).

**Full Tokenization (baseline):**
- `tokenize()` on 110-token source
- `tokenize()` on edited 110-token source

**Incremental Tokenization (TokenBuffer.update):**
- Edit at start: replace `1` with `99`
- Edit in middle: replace `28` with `99`
- Edit at end: replace `55` with `99`

### 4. Phase 7: ParserDb Signal/Memo Pipeline (`parserdb_benchmark.mbt`)

Benchmarks for the Salsa-style `Signal → Memo → Memo → Memo` incremental pipeline.
Measures pipeline construction, warm-path overhead, and backdating effectiveness.

**Pipeline stages:**
- `source_text: Signal[String]` → `tokens: Memo[TokenStage]` → `cst: Memo[CstStage]` → `term: Memo[AstNode]`

**Scenarios:**
- Cold: full construction + first evaluation
- Warm: repeated `term()` with no source change (Memo staleness-check only)
- Signal no-op: `set_source(same)` — `String::Eq` short-circuits before any Memo runs
- Full recompute: `set_source(new)` — all three Memos recompute from scratch
- Undo/redo cycle: alternate between two sources
- Diagnostics: malformed input error path

### 5. NodeInterner (`cst_benchmark.mbt`)

Benchmarks for `NodeInterner` hash-consing overhead and deduplication benefit.

**Microbenchmarks:**
- `intern_node` cold miss (HashMap insert)
- `intern_node` warm hit (HashMap lookup)

**Tree building comparison (`x + x` — two identical VarRef subtrees):**
- `build_tree` (no interning, baseline)
- `build_tree_interned` (token only, warm)
- `build_tree_fully_interned` (token + node, cold / warm)

**End-to-end parse comparison (`λf.λx.f (f x)`):**
- `parse_cst_recover` with no interning / token only / fully interned

### 6. Phase 4: Checkpoint-Based Subtree Reuse (`performance_benchmark.mbt`)

Benchmarks for `ReuseCursor` subtree reuse during incremental parsing.
When reparsing after an edit, unchanged subtrees outside the damaged range
are reused from the previous parse tree.

**Damage Tracking:**
- Localized damage (single token edit)
- Widespread damage (edit affects entire expression)

**Edit Position Impact:**
- Edit at start, middle, end of expression
- Best case: cosmetic change outside all subtrees
- Worst case: full invalidation requiring complete reparse

**Sequential Edits:**
- Typing simulation (character insertion)
- Backspace simulation (character deletion)

## Benchmark Results

### NodeInterner Performance Impact

*Measured 2026-02-28, `moon bench --release`*

**Tree building overhead (`x + x` event stream):**

| Builder | Mean | vs baseline |
|---------|------|-------------|
| `build_tree` (no interning) | 0.20 µs | baseline |
| `build_tree_interned` (token only, warm) | 0.26 µs | +30% |
| `build_tree_fully_interned` (warm) | 0.42 µs | +110% |
| `build_tree_fully_interned` (cold) | 0.49 µs | +145% |

**End-to-end parse overhead (`λf.λx.f (f x)`):**

| Mode | Mean | vs baseline |
|------|------|-------------|
| No interning | 2.08 µs | baseline |
| Token interned only | 2.28 µs | +10% |
| Fully interned (token + node) | 2.90 µs | +39% |

**`intern_node` microbenchmark:**

| Path | Mean |
|------|------|
| Cold miss (HashMap insert) | 0.07 µs |
| Warm hit (HashMap lookup) | 0.05 µs |

**Key observations:**
- Node interning adds ~0.8 µs overhead on a 15-token parse (2.08 → 2.90 µs)
- The cost is per-`FinishNode` HashMap lookup (~0.05 µs warm hit)
- Payoff is structural sharing across incremental edits: identical subtrees are pointer-equal, enabling O(1) `Memo` backdating in `ParserDb`
- With grammar expansion (let bindings), more subtrees will be shareable

### Heavy Benchmarks: Realistic IDE Session Simulation

*Measured 2026-02-28, `moon bench --release`*

**Tier 1 — Large document initial parse:**

| Input | Tokens | Mean |
|-------|--------|------|
| Nested lambdas + if-then-else (~200 tokens) | ~200 | 66.34 µs |
| Wide arithmetic `1 + 2 + ... + 100` | ~200 | 82.75 µs |
| Nested application depth 50 `f (f (f ...))` | ~200 | 60.05 µs |
| Large document CST only (fully interned) | ~200 | 72.49 µs |

**Tier 2 — Long editing sessions (100 sequential edits):**

| Session type | Total (100 edits) | Per edit |
|-------------|-------------------|----------|
| Typing at end of large document | 8.43 ms | ~84 µs |
| Typing in middle of large document | 8.98 ms | ~90 µs |
| Scattered variable renames | 5.50 ms | ~55 µs |

**Tier 3 — Incremental vs full reparse (wide arithmetic, 100 terms):**

| Operation | Mean | vs full parse |
|-----------|------|---------------|
| Full parse (baseline) | 88.18 µs | — |
| Incremental edit near end | 180.75 µs | 2.0× slower* |

*\*Wide arithmetic is a left-leaning `BinaryExpr` — any edit invalidates the root spine. Per-edit latency in sessions includes cursor setup + interner overhead. Real benefit emerges with independent subtrees (let bindings).*

**Tier 4 — Interner growth (200-edit typing session):**

| Metric | Initial | After 200 edits | Growth |
|--------|---------|-----------------|--------|
| Token interner size | 21 | 22 | +1 entry |
| Node interner size | 45 | 1,247 | ~28× |

**Key observations:**
- All per-edit latencies are well under the 16ms real-time target (~55-90 µs per edit)
- Token interner is effectively bounded by vocabulary (21 → 22 over 200 edits)
- Node interner grows ~28× over 200 edits — each edit creates new structural variants for the spine. Growth is monotonic but bounded by document complexity, not edit count alone
- Typing at end vs middle shows ~7% difference, suggesting most cost is in tree rebuilding, not damage tracking
- Scattered replacements are faster (~55 µs) than sequential typing (~84 µs) because single-char replacements don't grow the source

### Incremental vs Full Reparse — Honest Comparison

*Measured 2026-02-28, `moon bench --release`*

**100-edit sessions on ~200-token nested lambda document:**

| Session type | Full Reparse | Incremental | Ratio |
|-------------|-------------|-------------|-------|
| Typing at end | 5.37 ms | 8.03 ms | 1.5× slower |
| Typing in middle | 5.50 ms | 8.75 ms | 1.6× slower |
| Scattered replacements | 3.83 ms | 5.39 ms | 1.4× slower |

**Scaling with document size (wide arithmetic, 50-edit sessions):**

| Size | Full Reparse (1 parse) | Incr. Single Edit | Session: Reparse | Session: Incremental | Ratio |
|------|----------------------|-------------------|-----------------|---------------------|-------|
| 100 terms (~200 tok) | 71 µs | 201 µs | 3.79 ms | 9.62 ms | **2.5× slower** |
| 500 terms (~1000 tok) | 352 µs | 1.07 ms | 18.2 ms | 101 ms | **5.6× slower** |
| 1000 terms (~2000 tok) | 718 µs | 2.23 ms | 40.1 ms | 381 ms | **9.5× slower** |

**Why incremental is currently slower:**
- Lambda calculus trees are left-leaning (`BinaryExpr` spine) — every edit invalidates the root, so subtree reuse never fires meaningfully
- Incremental overhead (damage tracking, position adjustment, cursor construction, interning) scales with tree depth
- Full reparse has zero overhead — just parse and return
- The ratio *worsens* at larger sizes because the overhead grows with the tree

**When incremental will win:**
- Grammar expansion with `let` bindings creates **independent sibling subtrees** — editing one binding won't invalidate others
- At that point, incremental cost becomes O(edited-binding) while full reparse stays O(N)

### Phase 7: ParserDb Signal/Memo Pipeline

*Measured 2026-02-25, `moon bench --release`*

| Benchmark | Mean | Range (min … max) |
|-----------|------|-------------------|
| cold — new + term() | 6.23 µs | 6.14 µs … 6.32 µs |
| warm — term() no change | 0.03 µs | 0.02 µs … 0.03 µs |
| signal no-op — set_source(same) + term() | 0.04 µs | 0.04 µs … 0.04 µs |
| full recompute — set_source(new) + term() | 13.37 µs | 13.16 µs … 13.56 µs |
| undo/redo cycle | 13.43 µs | 13.30 µs … 13.62 µs |
| diagnostics — malformed input | 0.06 µs | 0.06 µs … 0.06 µs |

**Key ratios:**
- Warm path is ~200× faster than cold (0.03 µs vs 6.23 µs): Memo staleness check only, no tokenization or parsing
- Signal no-op (0.04 µs) ≈ warm: `String::Eq` short-circuits before any Memo runs
- Full recompute (13.37 µs) ≈ 2× cold: two `set_source` + two full pipeline evaluations per iteration
- Diagnostics (0.06 µs) hits the warm path for the cached malformed result

### Phase 1: Incremental Lexer (110 tokens)

*Measured 2026-02-25, `moon bench --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| full tokenize (110 tokens) | 1.84 µs | 1.79 µs ... 1.90 µs |
| incremental: edit at start | 3.49 µs | 3.40 µs ... 3.59 µs |
| incremental: edit in middle | 3.35 µs | 3.27 µs ... 3.51 µs |
| incremental: edit at end | 3.15 µs | 3.10 µs ... 3.21 µs |
| full re-tokenize after edit | 1.88 µs | 1.80 µs ... 2.15 µs |

**Methodology:** Each incremental benchmark includes `TokenBuffer::new()` (which
calls `tokenize()` internally at ~1.84 µs). Subtracting this setup cost gives
the isolated update time:

| Edit location | Update cost (estimated) | vs full re-tokenize | Speedup |
|---------------|------------------------|---------------------|---------|
| Start | ~1.65 µs | 1.88 µs | ~1.1x |
| Middle | ~1.51 µs | 1.88 µs | ~1.2x |
| End | ~1.31 µs | 1.88 µs | ~1.4x |

**Observations:**
- Incremental update is faster than full re-tokenize at all edit positions
- Edits near the end are cheapest: fewer tokens need position adjustment after the splice
- All operations are well under the 16ms real-time editing target (< 3 us total)
- At 110 tokens the speedup is modest (1.3-1.7x) because full tokenize is already fast;
  larger inputs will show greater benefit as update cost stays proportional to damaged
  region while full tokenize grows linearly

### Phase 4: Checkpoint-Based Subtree Reuse

*Measured 2026-02-25, `moon bench --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| damage tracking - localized damage | 1.30 µs | 1.27 µs ... 1.33 µs |
| damage tracking - widespread damage | 5.21 µs | 5.10 µs ... 5.41 µs |
| best case - cosmetic change | 3.20 µs | 3.12 µs ... 3.31 µs |
| worst case - full invalidation | 13.87 µs | 13.49 µs ... 14.41 µs |
| sequential edits - typing simulation | 2.41 µs | 2.23 µs ... 3.08 µs |
| sequential edits - backspace simulation | 2.28 µs | 2.23 µs ... 2.40 µs |
| incremental vs full - edit at start | 12.79 µs | 12.61 µs ... 13.31 µs |
| incremental vs full - edit at end | 12.45 µs | 12.23 µs ... 12.88 µs |
| incremental vs full - edit in middle | 12.69 µs | 12.53 µs ... 13.09 µs |

**Performance Comparison (vs full parse of 30+ tokens at 7.88 µs):**

| Scenario | Time | Speedup vs Full Parse |
|----------|------|----------------------|
| Localized damage | 1.30 µs | ~6.1x faster |
| Best case (cosmetic) | 3.20 µs | ~2.5x faster |
| Typing simulation | 2.41 µs | ~3.3x faster |
| Backspace simulation | 2.28 µs | ~3.5x faster |
| Widespread damage | 5.21 µs | ~1.5x faster |
| Edit at start/middle/end | ~12.6 µs | ~0.6x (slower)* |
| Worst case (full invalidation) | 13.87 µs | ~0.6x (slower)* |

*\*Edits that invalidate the tree root (lambda/binary expression spine) require rebuilding the entire tree structure. This is expected for left-leaning trees where the root spans the entire source.*

**Observations:**
- Subtree reuse provides significant speedup (3-6x) for localized edits
- Typing/backspace simulations are fast (< 2 µs), supporting real-time editing
- Edits at expression boundaries (start/middle/end of chains) invalidate the root node
- Lambda calculus trees are left-leaning: `f a b c` → App(App(App(f,a),b),c)
- When root is invalidated, incremental has overhead vs fresh parse
- Real benefit comes with let bindings (Phase 5) where sibling definitions are independent

### Parse Scaling

*Measured 2026-02-25, `moon bench --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| parse scaling - small (5 tokens) | 1.08 µs | 1.06 µs ... 1.10 µs |
| parse scaling - medium (15 tokens) | 4.74 µs | 4.63 µs ... 5.05 µs |
| parse scaling - large (30+ tokens) | 7.88 µs | 7.67 µs ... 8.59 µs |

### Basic Operations

*Measured 2026-02-25, `moon bench --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| full parse - simple (`42`) | 0.47 µs | — |
| full parse - lambda (`λx.x`) | 0.92 µs | — |
| full parse - nested lambdas | 2.65 µs | — |
| full parse - arithmetic | 2.21 µs | — |
| full parse - complex | 4.86 µs | — |
| tokenization | 0.30 µs | — |

### Incremental Parser

*Measured 2026-02-25, `moon bench --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| incremental - initial parse | 0.58 µs | — |
| incremental - small edit | 2.45 µs | — |
| incremental - multiple edits | 4.10 µs | — |
| incremental - replacement | 2.67 µs | — |

## Expected Performance Characteristics

### Time Complexity

| Phase | Tokenization | Parsing | Total |
|-------|-------------|---------|-------|
| Before Phase 1 | O(N) | O(N) | O(N) |
| After Phase 1 (incremental lexer) | O(d) | O(N) | O(N) |
| After Phase 4 (subtree reuse) | O(d) | O(depth)* | O(depth) |

*\*For localized edits. Edits that invalidate the root still require O(N) parsing.*

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Initial parse | O(n) | n = source length |
| Incremental edit (localized) | O(depth) | With subtree reuse |
| Incremental edit (root invalidated) | O(n) | Tree spine must be rebuilt |
| Damage tracking | O(m) | m = tree nodes |

### Benchmark Targets

Based on Wagner-Graham algorithm and Tree-sitter benchmarks:

| Metric | Target | Current Status |
|--------|--------|----------------|
| Full parse (small) | < 1ms | 1.08 µs ✅ |
| Full parse (medium) | < 5ms | 4.74 µs ✅ |
| Full tokenize (110 tokens) | < 2ms | 1.84 µs ✅ |
| Incremental tokenize (110 tokens) | < full tokenize | 3.15-3.49 µs (with setup) ✅ |
| Incremental edit (localized) | < full parse | 1.30-2.41 µs (3-6x faster) ✅ |
| Incremental edit (worst case) | < 2x full parse | 13.87 µs (~1.8x full) ✅ |
| Subtree reuse rate | > 50% for local edits | Verified in tests ✅ |
| Memory overhead | < 2x source | To measure |

### Real-Time Editing Target

**60 FPS target**: < 16ms per edit
- Parse: < 5ms
- Damage tracking: < 3ms
- CRDT sync: < 6ms

## Benchmark Results Format

MoonBit benchmark output format:
```
test bench: full parse - simple ... ok (XXX iterations in XXXms)
test bench: incremental - small edit ... ok (XXX iterations in XXXms)
```

Performance metrics to track:
1. **Iterations per second**: Higher is better
2. **Time per iteration**: Lower is better
3. **Relative speedup**: Incremental vs full reparse

## Interpreting Results

### Good Performance Indicators

✅ **Incremental edits faster than full reparse** (for localized edits)
✅ **Linear scaling with input size**
✅ **< 16ms for typical edits**
✅ **Subtree reuse rate > 50%** for single-token edits on large inputs
✅ **Typing/backspace simulations < 2 µs**

### Performance Red Flags

⚠️ **Incremental slower than full reparse for localized edits** → Subtree reuse not triggering
⚠️ **Exponential scaling** → Algorithm complexity problem
⚠️ **High memory usage** → AST node allocation issue
⚠️ **Zero reuse count** → ReuseCursor conditions too strict

### Phase 4 Specific Notes

**Expected behavior:**
- Localized edits (adding/removing a character within a subtree) should be 3-6x faster
- Edits at expression boundaries (start of chain) invalidate the root and are slower
- Lambda calculus trees are left-leaning, so root invalidation is common

**When root is invalidated:**
- Incremental parse has overhead (~1.5-2x full parse) due to cursor setup
- This is expected and acceptable; benefit comes from localized edits
- Phase 5 (let bindings) will provide independent subtrees for better reuse

## Optimization Opportunities

Based on benchmark results, consider:

1. **If tokenization is slow:**
   - Implement parallel tokenization
   - Add streaming tokenization

2. **If parsing is slow:**
   - Implement lazy subtree expansion
   - Add position indexing

3. **If damage tracking is slow:**
   - Optimize tree traversal
   - Add early termination

4. **If CRDT conversion is slow:**
   - Implement incremental CRDT updates
   - Optimize attribute copying

## Profiling Tips

### Identify Bottlenecks

1. **Run benchmarks with profiler:**
   ```bash
   moon bench --package parser --release
   ```

2. **Compare incremental vs full:**
   - If incremental ≈ full → Whole-tree reuse not triggering
   - If incremental << full → Working as expected

### Memory Profiling

Track memory usage patterns:
- AST node allocation
- CRDT tree size

## Continuous Benchmarking

Recommended CI integration:
```yaml
- name: Run benchmarks
  run: moon bench --package parser --release

- name: Compare against baseline
  run: |
    moon bench --package parser --release
```

Keep historical snapshots in `docs/benchmark_history.md` to compare trends over time.

## References

- MoonBit Benchmarks: https://docs.moonbitlang.com/en/latest/language/benchmarks.html
- Wagner-Graham Paper: https://dl.acm.org/doi/10.1145/293677.293678
- Tree-sitter Benchmarks: https://tree-sitter.github.io/tree-sitter/
