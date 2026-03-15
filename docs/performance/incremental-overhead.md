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

### Attempted optimizations

1. **Skip `leading_token_matches` for pre-damage nodes:** No measurable improvement. The per-node overhead is distributed, not concentrated in one check. Complication: nodes adjacent to damage need trailing context checked even when `node_end < damage_start` (the follow token may be inside the damage region).

2. **`advance_past_reused` token_count jump:** `total_token_count` (including trivia) was added to `CstNode`, but it counts CST leaf tokens, not token-stream entries. Synthetic zero-width tokens (error/incomplete placeholders) inflate the count, causing the jump to overshoot. The offset-based loop is correct because it uses the actual token stream positions. **Blocker:** The mismatch between CST leaf count and token-stream entry count means O(1) jump is not safe without a separate "stream token count" field that excludes synthetic tokens. This requires tracking which tokens are synthetic at construction time.

3. **Skip `collect_reused_error_spans` via `has_errors` guard:** `CstNode::has_errors` is itself a recursive O(subtree) walk, making it no cheaper than `collect_reused_error_spans`. A shallow direct-children check misses deeply nested errors, causing silent diagnostic loss. **Blocker:** Needs a cached `has_errors` boolean flag on `CstNode`, computed at construction time. But `CstNode::new` doesn't know which `RawKind` values are error/incomplete (grammar-specific). Would need new parameters or a post-construction fixup.

### Remaining actionable path

The most promising approach requires a **seam API change**: add `error_kind` and `incomplete_kind` parameters to `CstNode::new` (or a new constructor variant) so it can compute and cache a `has_any_error : Bool` flag at O(0) marginal cost (the children loop already runs). This enables:
- O(1) `has_any_error` check in `emit_reused` to skip `collect_reused_error_spans`
- O(1) skip of `Array[ReusedErrorSpan]` allocation for healthy nodes
- The same flag could skip `synthesize_reused_diagnostics` entirely

The `advance_past_reused` loop remains. Its cost (~4 closure calls per LetDef) is minor compared to the error span collection.

---

## Future: `re_intern_subtree` early-exit optimization

`re_intern_subtree` currently does an O(subtree_size) walk for every reused node, even when the node is already fully interned (the production path). All `intern_token`/`intern_node` calls are O(1) cache hits, but the walk still allocates temporary `Array[CstElement]` at every level.

An early-exit check could reduce this to O(1) for already-canonical subtrees: call `node_interner.intern_node(node)` first, and if the returned reference is the same canonical copy, skip the children walk entirely.

**Blocker:** `NodeInterner::intern_node` returns the same reference for both "already in interner" (safe to skip) and "newly inserted" (must walk children) cases. A `NodeInterner::lookup` method (get-without-insert) is needed to distinguish these safely.

---

## Resolved: Right-Recursive Grammars

Right-recursive grammars were the original worst case. Fixed by switching to flat `LetDef*` structure (PR #36, 2026-03-15). The remaining ~2.5x overhead is now in the cursor/try_reuse infrastructure, not the grammar structure.
