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

4. **Next optimization target:** Reduce per-node `emit_reused` cost (see detailed analysis below).

### Attempted: skip leading_token_matches for pre-damage nodes

Skipping `leading_token_matches` for nodes with `node_end < damage_start` gave no measurable improvement (~263 µs vs ~245 µs baseline, within noise). The per-node overhead is not concentrated in any single check within `try_reuse`.

**Complication discovered:** A node ending at offset 2 with `damage_start = 3` cannot skip the trailing context check, because the follow token at offset 3 may be inside the damage region and changed. The fast path needs to preserve `trailing_context_matches` for boundary-adjacent nodes.

### Root cause: `emit_reused` does O(subtree) work per reuse hit

The per-node overhead is in `emit_reused`, not `try_reuse`. For each reused node, `emit_reused` performs:

| Operation | Cost per node | Purpose |
|-----------|--------------|---------|
| `collect_reused_error_spans` | O(subtree) recursive walk | Find error/incomplete tokens |
| `Array[ReusedErrorSpan]` allocation | 1 heap alloc | Error span buffer |
| `error_spans.iter().any(...)` | O(spans) | Boundary ownership check |
| `next_sibling_has_error` | O(1) | EOF boundary check |
| `replay_reused_diagnostics` | O(prev_diags) per node | Replay matching diagnostics |
| `advance_past_reused` | O(tokens_in_node) closure calls | Advance token position |
| `cursor.advance_past` | O(1) | Advance cursor offset |

For 80 healthy LetDefs (zero errors), `collect_reused_error_spans` walks ~320 children total to find zero spans. `advance_past_reused` makes ~320 `get_start` closure calls to advance through ~4 tokens per node. These add up to the ~148 µs overhead.

### Actionable findings

1. **`collect_reused_error_spans` on healthy nodes:** Skip the recursive walk when the node has no errors. `CstNode` could cache an `has_errors` flag, or check `node.has_errors(error_raw, incomplete_raw)` before walking. If no errors, skip span collection and boundary ownership check.

2. **`advance_past_reused` closure calls:** Replace the `get_start` closure loop with a direct `self.position += node.token_count` jump. `CstNode` already stores `token_count` for this purpose. The closure loop is a fallback for zero-width error placeholders, which could be handled as a special case.

3. **`Array[ReusedErrorSpan]` allocation:** Allocating a fresh array per reuse hit (80 allocations for 80 nodes) adds GC pressure. Reuse a shared buffer or skip allocation when no errors.

---

## Future: `re_intern_subtree` early-exit optimization

`re_intern_subtree` currently does an O(subtree_size) walk for every reused node, even when the node is already fully interned (the production path). All `intern_token`/`intern_node` calls are O(1) cache hits, but the walk still allocates temporary `Array[CstElement]` at every level.

An early-exit check could reduce this to O(1) for already-canonical subtrees: call `node_interner.intern_node(node)` first, and if the returned reference is the same canonical copy, skip the children walk entirely.

**Blocker:** `NodeInterner::intern_node` returns the same reference for both "already in interner" (safe to skip) and "newly inserted" (must walk children) cases. A `NodeInterner::lookup` method (get-without-insert) is needed to distinguish these safely.

---

## Resolved: Right-Recursive Grammars

Right-recursive grammars were the original worst case. Fixed by switching to flat `LetDef*` structure (PR #36, 2026-03-15). The remaining ~2.5x overhead is now in the cursor/try_reuse infrastructure, not the grammar structure.
