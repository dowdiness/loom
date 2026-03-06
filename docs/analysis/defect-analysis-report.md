# Loom Framework: Defect Analysis Report

## 1. Project Structure Overview

Three modules: **seam** (CST data structures), **incr** (incremental computation engine), **loom** (parser framework). I traced four primary execution paths:
1. `ReactiveParser::new → set_source → term()` (reactive pipeline)
2. `ImperativeParser::new → parse → edit` (imperative pipeline)
3. `Runtime::batch → Signal::set → commit_batch` (batch flow)
4. `ParserContext::node → try_reuse → emit_reused` (incremental reuse)

---

## 2. Confirmed Defects

### 2.1 `next_sibling_has_error` — Redundant and incomplete `has_errors` calls

**Location:** `reuse_cursor.mbt:398-400`

```moonbit
n.has_errors(err_raw, err_raw) ||
n.has_errors(err_raw, incomplete_raw) ||
n.has_errors(incomplete_raw, incomplete_raw)
```

**Issue:** `CstNode::has_errors` takes `(error_node_kind, error_token_kind)`. The call `n.has_errors(err_raw, err_raw)` checks for nodes whose kind is `err_raw` OR tokens whose kind is `err_raw`. The call `n.has_errors(incomplete_raw, incomplete_raw)` checks for nodes/tokens of `incomplete_raw`. But `n.has_errors(err_raw, incomplete_raw)` checks error nodes OR incomplete tokens. The missing combination is `n.has_errors(incomplete_raw, err_raw)` — incomplete nodes with error tokens. This means a subtree containing a node of kind `incomplete_raw` with child tokens of kind `err_raw` would be missed.

**Certainty:** Likely (depends on whether `incomplete_kind` is ever used as a node kind, not just a token kind — which it is, per `emit_incomplete_placeholder` emitting a zero-width token).

### 2.2 `DamageTracker::add_range` — Adjacent ranges not merged

**Location:** `damage.mbt:39-54`

```moonbit
if existing.overlaps(merged) {
  merged = merged.merge(existing)
} else {
  new_ranges.push(existing)
}
```

**Issue:** `Range::overlaps` returns `self.start < other.end && other.start < self.end`. Two adjacent ranges like `[5,10)` and `[10,15)` are NOT considered overlapping (10 < 10 is false). They remain separate in the array. While not semantically incorrect for damage checking (both ranges are still tracked), it means `DamageTracker::range()` correctly returns the bounding range but `damaged_ranges.length()` overstates fragmentation, and `is_damaged` for a range exactly at the boundary between two adjacent damage regions (e.g., `[9,11)`) will correctly report damaged. However, `expand_for_node` adds a new range that may overlap one but not the other, causing the merge to miss the second adjacent range — leaving three ranges where one would suffice.

**Certainty:** Possible (the adjacency gap doesn't cause incorrect damage detection, but causes suboptimal damage coalescing that could lead to redundant work in downstream consumers).

---

## 3. High-Risk Areas and Potential Bugs

### 3.1 `commit_batch` — Recursive re-entrancy with unbounded depth

**Location:** `runtime.mbt:565-576`

```moonbit
self.batch_depth = self.batch_depth + 1
for cb in callbacks {
  cb()
}
self.batch_depth = self.batch_depth - 1
if self.batch_pending_signals.length() > 0 {
  self.commit_batch()  // recursive call
}
```

**Issue:** If an `on_change` callback sets a signal, that signal's pending value is registered. After all callbacks finish, `commit_batch` is called recursively. If that recursive commit also triggers `on_change` callbacks that set more signals, the recursion continues. There is no depth limit and no guard against infinite recursion. A cyclic pattern where signal A's `on_change` sets signal B and B's `on_change` sets A would recurse unboundedly.

**Scenario:** `sig_a.on_change(fn(_) { sig_b.set(1) })`, `sig_b.on_change(fn(_) { sig_a.set(2) })`. Inside a batch, set `sig_a`. Commit fires A's callback → sets B (pending). Recursive commit fires B's callback → sets A (pending). Recursive commit fires A's callback → sets B again... Stack overflow.

**Certainty:** Likely (no guard exists, and the pattern is plausible in reactive UI bindings).

### 3.2 `commit_batch` — `batch_max_durability` reset before recursive commit

**Location:** `runtime.mbt:564`

```moonbit
self.batch_max_durability = Low
// ...
self.batch_depth = self.batch_depth + 1
for cb in callbacks {
  cb()
}
```

**Issue:** `batch_max_durability` is reset to `Low` at line 564, *before* callbacks execute. When a callback calls `Signal::set`, `set_batch` calls `self.rt.bump_revision(self.durability)`, which (since `batch_depth > 0`) only updates `batch_max_durability`. This is correct — the new `batch_max_durability` is built from scratch for the callback-triggered batch. But there is a subtle issue: `advance_revision` at the recursive `commit_batch` will use this new `batch_max_durability`, which might be lower than the outer batch's durability. The outer batch's revision was already advanced at line 554 with the correct max durability, so this is not a bug per se. However, the `durability_last_changed` array for the recursive commit may understate the durability level, potentially causing a false durability shortcut miss in subsequent verification.

**Certainty:** Possible (needs specific multi-durability callback scenario to trigger).

### 3.3 `MemoMap::get_or_create_memo` — Key captured by reference, not by value

**Location:** `memo_map.mbt:114`

```moonbit
let memo = match self.label {
  Some(label) => Memo::new(self.rt, () => (self.compute)(key), label~)
  None => Memo::new(self.rt, () => (self.compute)(key))
}
```

**Issue:** The comment says "key is captured by value in closure." Whether MoonBit captures `key` by value or reference depends on the type. For primitive types (Int), this is fine. For reference types (String, structs), the closure captures the reference. If `K` is a mutable type and the caller mutates it after `get()` returns, the captured key inside the memo's compute closure will see the mutated value, producing incorrect results on recomputation.

**Certainty:** Possible (depends on MoonBit's closure semantics for the specific `K` type — likely safe for typical key types like Int and String which are immutable in MoonBit).

### 3.4 `text_to_delta` — Incorrect handling of multi-byte characters

**Location:** `delta.mbt:82-94`

```moonbit
let mut prefix = 0
while prefix < old_len && prefix < new_len && old[prefix] == new[prefix] {
  prefix += 1
}
```

**Issue:** `String.length()` in MoonBit returns the number of UTF-16 code units, and `old[prefix]` accesses by code unit index. The prefix/suffix calculation iterates by code unit, which is correct for UTF-16 indexing. However, the suffix scan:

```moonbit
let mut suffix = 0
while suffix < old_len - prefix &&
      suffix < new_len - prefix &&
      old[old_len - 1 - suffix] == new[new_len - 1 - suffix] {
  suffix += 1
}
```

This scans backward by code unit. For surrogate pairs (characters outside BMP), scanning backward by one code unit lands in the middle of a surrogate pair. This produces incorrect `Delete`/`Insert` sizes that split a surrogate pair, which could cause downstream corruption when the `Edit` is applied to rebuild source text.

**Certainty:** Likely (any string containing emoji or non-BMP characters would trigger this).

---

## 4. Edge Cases and Reliability Concerns

### 4.1 `Edit::apply_to_position` — Position at `old_end` maps to `start`

**Location:** `edit.mbt:47-52`

The condition `pos <= self.old_end()` means a position at the exact end of the deleted range maps to `start` rather than being shifted. This is a design choice (documented in tests), but callers expecting "positions after the edit shift by delta" may be surprised that a cursor at `old_end` jumps backward to `start` instead of mapping to `new_end`.

**Certainty:** Possible design friction (not a bug, but the inclusive boundary is unusual).

### 4.2 `to_edits` — `accumulated_delta` tracks `Int` without overflow protection

**Location:** `delta.mbt:30-73`

`accumulated_delta` grows with each insert and shrinks with each delete. For very large documents with many edits, this is a plain `Int` addition. MoonBit's `Int` is 32-bit; a document with cumulative inserts exceeding ~2GB code units would overflow. This is practically unlikely but theoretically possible in automated CRDT merge scenarios.

**Certainty:** Possible (extremely unlikely in practice).

### 4.3 `diff_nodes` — Position tracking doesn't account for unequal child counts

**Location:** `diff.mbt:18-22`

```moonbit
if old.kind != new.kind || old.children.length() != new.children.length() {
  result.push(Edit::new(old_pos, old.text_len, new.text_len))
  return
}
```

When children count differs, the entire node is emitted as a single Edit. This is correct but coarse — a node that gained one child at the end could produce a better diff by walking the common prefix of children. This is a design choice, not a bug.

**Certainty:** Design limitation, not a defect.

### 4.4 `ReuseCursor::snapshot` — Shares `old_tokens` array reference

**Location:** `reuse_cursor.mbt:430`

```moonbit
let old_tokens = self.old_tokens // immutable after construction — safe to share
```

The comment says "immutable after construction." This is true by convention — `collect_old_tokens` populates it during `ReuseCursor::new` and nothing else writes to it. But the `Array` type in MoonBit is mutable. If any code path (future or current) pushed to `old_tokens` after construction, both the original and snapshot would see the mutation.

**Certainty:** Currently safe, fragile to future changes.

### 4.5 `ParserContext::restore` — Error truncation loop condition

**Location:** `parser.mbt:385-388`

```moonbit
while self.errors.length() > 0 && self.error_count > cp.error_count {
  let _ = self.errors.pop()
  self.error_count = self.error_count - 1
}
```

This pops errors until `error_count` matches the checkpoint. But `push_diagnostic_unique` can *update* existing diagnostics (returning false, not incrementing `error_count`). If a speculative parse updated an existing diagnostic's `got_token` field without incrementing `error_count`, restoring the checkpoint won't undo that mutation. The old diagnostic object's `got_token` remains changed.

**Certainty:** Likely (the update path in `push_diagnostic_unique:635` mutates in-place: `self.errors[i] = diag`).

---

## 5. Refactoring Opportunities

### 5.1 `commit_batch` recursion → iterative loop

**Files:** `runtime.mbt:519-581`

**Issue:** The recursive `commit_batch` for callback-triggered signals is unbounded. Converting to an iterative loop with a depth counter and explicit limit would prevent stack overflow.

**Improvement:** Replace the recursive call with a `while self.batch_pending_signals.length() > 0 { ... }` loop with a configurable iteration limit (e.g., 100). Abort or emit a warning on exceeding the limit.

### 5.2 `next_sibling_has_error` — Consolidate into single call

**Files:** `reuse_cursor.mbt:397-401`

**Issue:** Three calls to `has_errors` with manually permuted arguments. This should be a single utility function that checks if a subtree contains any error or incomplete kind.

```moonbit
fn has_any_errors(node, err_raw, incomplete_raw) -> Bool {
  // Check both kinds as both node and token kinds
}
```

**Improvement:** Eliminates the missed combination bug and makes the intent clear.

### 5.3 `DamageTracker::add_range` — Rebuild array via swap rather than copy

**Files:** `damage.mbt:39-54`

**Issue:** Creates a new `Array`, sorts it, then clears and repopulates `damaged_ranges`. This is O(n log n) per insertion.

**Improvement:** Use a merge-insert approach: find the correct position, merge with neighbors, and splice in place. Also fix adjacent-range merging by using `<=` instead of `<` in `Range::overlaps` or adjusting the merge condition specifically.

### 5.4 `Runtime::remove_batch_signal` — O(n) scan with allocation

**Files:** `runtime.mbt:618-632`

```moonbit
fn Runtime::remove_batch_signal(self : Runtime, cell_id : CellId) -> Unit {
  let kept : Array[CellId] = []
  // ... scan and rebuild
}
```

**Issue:** Allocates a new array, copies all elements except one, then copies back. Called from `Signal::set_batch` rollback path. For large batches, this is O(n) per rollback.

**Improvement:** Use a swap-remove or mark-deleted approach. Or track pending signals in a `HashSet` alongside the `Array`.

---

## 6. Structural Design Issues

### 6.1 `CstNode.children` mutability gap

The `children` field is `Array[CstElement]` — mutable by MoonBit's type system. The doc says "frozen after construction" but this is enforced only by convention. Any code with access to a `CstNode` can push/pop children, silently invalidating `text_len`, `hash`, and `token_count`. The `NodeInterner` relies on structural equality via the cached hash, so a mutated node would produce incorrect interning results.

**Impact:** Any accidental mutation of `children` after construction breaks hash consistency, equality semantics, and interning correctness. This is a latent source of subtle bugs that would be extremely difficult to diagnose.

### 6.2 Global mutable interners

`core_interner` and `core_node_interners` in `interners.mbt` are module-level mutable globals. They grow monotonically and are never cleared during the process lifetime. In a long-running language server processing thousands of documents, these interners accumulate all tokens and node structures ever seen.

**Impact:** Memory proportional to the total unique token/node vocabulary across all documents ever parsed in the process. Not a correctness issue, but a memory leak in long-running processes.

### 6.3 `ParserContext::error_count` tracks only additions, not updates

`push_diagnostic_unique` increments `error_count` only when a new diagnostic is added, not when an existing one is updated. `checkpoint`/`restore` uses `error_count` to truncate the errors array. This means the checkpoint system cannot undo in-place updates to diagnostic tokens, as noted in §4.5.

---

## 7. Uncertain Observations

### 7.1 `Memo::force_recompute` — Subscriber links after cycle error

When `force_recompute` detects a cycle via `cell.in_progress`, it returns `Err(CycleError)` before updating dependencies or subscriber links. This leaves the old dependency set intact. If the cycle is handled gracefully (via `get_result`) and the memo is later recomputed successfully, the stale subscriber links from the previous successful computation remain, potentially causing unnecessary recomputations but not incorrect results. **Cannot confirm** whether this actually causes observable issues without tracing a full cycle-recovery-recompute scenario.

### 7.2 `ReuseCursor::seek_node_at` — Root frame reset on backward seek

When `target_offset < self.current_offset`, the cursor drains all frames except the root and resets to position 0. This is correct but loses all cached child positions, making a subsequent forward seek O(depth × width) rather than O(depth). **Cannot confirm** whether this occurs in practice — the parser generally processes left-to-right.

### 7.3 `SyntaxNode::Eq` ignoring offset — correctness for consumers

`SyntaxNode::Eq` compares only the underlying `CstNode`. This means two `SyntaxNode`s at different offsets are considered equal. This is documented as intentional for `Memo` backdating. However, if any consumer stores `SyntaxNode`s in a `HashSet` or uses them as `HashMap` keys, nodes at different positions would collide. **Cannot confirm** whether this pattern exists in consumer code.

---

## 8. Summary of Most Important Findings

| Priority | Issue | Location | Type |
|----------|-------|----------|------|
| **High** | `commit_batch` recursive re-entrancy with no depth limit | `runtime.mbt:574-576` | Stack overflow risk |
| **High** | `text_to_delta` suffix scan splits surrogate pairs | `delta.mbt:88-92` | Data corruption for non-BMP chars |
| **Medium** | `next_sibling_has_error` missing `(incomplete, error)` combination | `reuse_cursor.mbt:398-400` | Incorrect reuse diagnostic replay |
| **Medium** | `checkpoint/restore` cannot undo in-place diagnostic updates | `parser.mbt:385-388, 635` | Stale diagnostic tokens after restore |
| **Low** | Adjacent damage ranges not coalesced | `damage.mbt:39-42` | Suboptimal damage tracking |
| **Low** | Global interners grow without bound | `interners.mbt` | Memory growth in long-running processes |

The most actionable finding is the `commit_batch` recursion risk — adding an iteration limit is a low-cost change that prevents a real stack overflow scenario in reactive applications with cross-signal callbacks.
