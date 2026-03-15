# Incremental Parser Overhead: Low-Hanging-Fruit Waste Elimination

**Status:** Implemented; benchmarked on flat-grammar parser benchmarks.

**Context:** Incremental parsing is slower than full reparse on right-recursive let chains (320-deep). This document records actionable waste elimination opportunities found during investigation.

**Related:** [ADR: physical_equal interner](../decisions/2026-03-14-physical-equal-interner.md) (O(n^2) interner fix)

---

## Finding 1: `buffer.update()` returns unnecessary copy — **Resolved**

`TokenBuffer::update` returned `Array[TokenInfo[T]]` via `self.tokens.copy()`, creating an O(n) copy per edit. Changed to return `Unit`. All call sites updated to use `buffer.get_tokens()` when needed.

## Finding 2: `collect_old_tokens` walks entire old CST upfront — **Resolved**

`ReuseCursor::new` eagerly called `collect_old_tokens`, flattening the entire old CST. Replaced with a lazy `OldTokenCache` shared across snapshots — the table is built once on first `trailing_context_matches` call and reused across speculative branches.

## Finding 3: `emit_reused` serializes then deserializes reused nodes — **Resolved**

Added `ReuseNode(CstNode)` variant to `ParseEvent`. Reused subtrees are attached directly via a single event instead of recursively emitting StartNode/Token/FinishNode. `build_tree_fully_interned` re-interns the node through `NodeInterner` (O(1) cache hit for already-interned nodes).

---

## Benchmark Summary (2026-03-15)

Key incremental benchmarks, before vs after (lambda module, `moon bench --release`):

| Benchmark | Before | After | Change |
|-----------|--------|-------|--------|
| phase3: cursor reuse, edit at end (110 tok) | 40.04 µs | 33.79 µs | -16% |
| phase3: cursor reuse, edit at start (110 tok) | 34.01 µs | 30.94 µs | -9% |
| phase4: nested let body - multiple reused | 4.05 µs | 3.63 µs | -10% |
| scale: 100 terms - incremental single edit | 148.98 µs | 131.83 µs | -12% |
| scale: 500 terms - incremental single edit | 829.47 µs | 750.24 µs | -10% |
| scale: 1000 terms - incremental single edit | 1.84 ms | 1.63 ms | -11% |
| heavy: typing session - 100 edits at end | 5.02 ms | 3.29 ms | -34% |
| heavy: typing session - 100 edits in middle | 6.26 ms | 5.29 ms | -15% |

---

## Phase Profiling (2026-03-15)

Isolated each sub-phase of the incremental parse path using profiling benchmarks on flat-grammar let chains (`moon bench --release`).

### 80 lets — single edit

| Phase | Time |
|-------|------|
| Tokenize only | 20.76 µs |
| Tree build (normal events) | 12.96 µs |
| Tree build (ReuseNode events) | 7.84 µs |
| **Full reparse total** | **97.30 µs** |
| → Grammar execution (derived) | 63.58 µs |
| **Incremental total** | **244.51 µs** |
| → Overhead vs full reparse | 147.21 µs |

### 320 lets — single edit

| Phase | Time |
|-------|------|
| Tokenize only | 96.71 µs |
| Tree build (normal events) | 61.80 µs |
| Tree build (ReuseNode events) | 35.38 µs |
| **Full reparse total** | **441.66 µs** |
| → Grammar execution (derived) | 283.15 µs |
| **Incremental total** | **1120 µs** |
| → Overhead vs full reparse | 678.34 µs |

### Conclusions

1. **Tree building is NOT the bottleneck.** `rebuild_subtree` (ReuseNode path) is faster than building from normal events (7.84 µs vs 12.96 µs for 80 lets). The `NodeInterner::lookup` early-exit optimization would help, but tree building is only ~13% of total time.

2. **The bottleneck is grammar execution with cursor.** Cursor-aware grammar execution is ~3.3x slower than cursor-free execution. The per-node cost of `try_reuse` (cursor seek + 4-condition check + trailing-context binary search) dominates.

3. **Head vs tail edit costs are identical** (~245 µs for both at 80 lets). The overhead is O(n) regardless of edit position — the cursor walks all nodes even when most are trivially reusable.

4. **Next optimization target:** Reduce per-node `try_reuse` cost. Candidates: skip `try_reuse` for nodes entirely outside the damage region without cursor seek, batch trailing-context lookups, or short-circuit the 4-condition check for consecutive reusable siblings.

---

## Future: `re_intern_subtree` early-exit optimization

`re_intern_subtree` currently does an O(subtree_size) walk for every reused node, even when the node is already fully interned (the production path). All `intern_token`/`intern_node` calls are O(1) cache hits, but the walk still allocates temporary `Array[CstElement]` at every level.

An early-exit check could reduce this to O(1) for already-canonical subtrees: call `node_interner.intern_node(node)` first, and if the returned reference is the same canonical copy, skip the children walk entirely.

**Blocker:** `NodeInterner::intern_node` returns the same reference for both "already in interner" (safe to skip) and "newly inserted" (must walk children) cases. A `NodeInterner::lookup` method (get-without-insert) is needed to distinguish these safely.

---

## Resolved: Right-Recursive Grammars

Right-recursive grammars were the original worst case. Fixed by switching to flat `LetDef*` structure (PR #36, 2026-03-15). The remaining ~2.5x overhead is now in the cursor/try_reuse infrastructure, not the grammar structure.
