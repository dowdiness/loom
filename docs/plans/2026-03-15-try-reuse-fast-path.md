# try_reuse Fast Path for Undamaged Nodes

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skip expensive leading/trailing token checks in `try_reuse` for nodes entirely before the damage region, reducing incremental overhead from ~2.5x to near-parity with full reparse.

**Architecture:** Add a fast path in `ReuseCursor::try_reuse` that skips `leading_token_matches` and `trailing_context_matches` when `node_end < damage_start`. This is safe because `TokenBuffer::update` preserves tokens unchanged before the damaged region (line 253-256 of `token_buffer.mbt`).

**References:**
- [Phase profiling results](../performance/incremental-overhead.md#phase-profiling-2026-03-15)
- `loom/src/core/reuse_cursor.mbt` — `try_reuse`, `seek_node_at`, `trailing_context_matches`
- `loom/src/core/token_buffer.mbt:253-256` — prefix tokens preserved unchanged

---

## Preflight

Verified command shapes:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom && moon check && moon test
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda && moon check && moon test
```

Success criteria:
- All loom and lambda tests pass
- Profiling benchmarks show incremental overhead reduced (target: <1.5x full reparse for 80 lets)
- No behavioral changes for nodes near or overlapping the damage region

---

## Task 1: Add fast path to `try_reuse`

**Files:**
- Modify: `loom/src/core/reuse_cursor.mbt`

- [ ] **Step 1: Add the fast path after `is_outside_damage`**

In `ReuseCursor::try_reuse` (around line 375), after `seek_node_at` finds a node and `is_outside_damage` confirms it's safe, check whether the node ends strictly before `damage_start`. If so, skip `leading_token_matches` and `trailing_context_matches`.

Current code (lines 388-405):

```moonbit
Some((node, node_offset)) => {
  let node_end = node_offset + node.text_len
  if not(is_outside_damage(...)) {
    None
  } else if not(leading_token_matches(node, self, token_pos)) {
    None
  } else if not(trailing_context_matches(self, node_end)) {
    None
  } else {
    Some(node)
  }
}
```

Change to:

```moonbit
Some((node, node_offset)) => {
  let node_end = node_offset + node.text_len
  if not(is_outside_damage(
      node_offset, node_end, self.damage_start, self.damage_end,
    )) {
    None
  } else if node_end < self.damage_start {
    // Fast path: node is entirely before the damage region.
    // Tokens in this range are unchanged by TokenBuffer::update,
    // so leading/trailing context checks are guaranteed to pass.
    Some(node)
  } else if not(leading_token_matches(node, self, token_pos)) {
    None
  } else if not(trailing_context_matches(self, node_end)) {
    None
  } else {
    Some(node)
  }
}
```

The condition `node_end < damage_start` (strict less-than) is important: nodes ending exactly at `damage_start` (`node_end == damage_start`) are excluded because `is_outside_damage` already excludes left-adjacent nodes (`node_end < damage_start`, not `<=`). So the fast path fires for exactly the same nodes that `is_outside_damage` accepts on the left side.

- [ ] **Step 2: Run checks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon check
moon test
```

- [ ] **Step 3: Run lambda tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check
moon test
```

- [ ] **Step 4: Update interfaces and format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon info && moon fmt
```

- [ ] **Step 5: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add loom/src/core/reuse_cursor.mbt
git commit -m "perf: skip token checks for nodes before damage region in try_reuse"
```

---

## Task 2: Run profiling benchmarks and record results

**Files:**
- Modify: `docs/performance/incremental-overhead.md`

- [ ] **Step 1: Run profiling benchmarks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon bench --release 2>&1 | grep -E "profile:" -A2
```

Key comparisons:
- `profile: 80 lets - incremental (edit tail)` — should improve significantly
- `profile: 80 lets - incremental (edit head)` — should show less improvement (most nodes are after damage)
- `profile: 80 lets - full reparse` — should be unchanged (baseline)

- [ ] **Step 2: Record results**

Update `docs/performance/incremental-overhead.md` with before/after profiling numbers.

- [ ] **Step 3: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add docs/performance/incremental-overhead.md
git commit -m "docs: record try_reuse fast path benchmark results"
```

---

## Task 3: Add regression test for fast path correctness

**Files:**
- Modify: `loom/src/core/parser_wbtest.mbt`

- [ ] **Step 1: Add test that verifies reuse before damage region**

Add a whitebox test that parses a multi-node expression, edits the last node, and verifies that nodes before the damage are reused (reuse_count > 0) and the result matches full reparse.

- [ ] **Step 2: Add test that verifies no false reuse at damage boundary**

Add a test with an edit at the boundary between two nodes. Verify that the node immediately before the edit is NOT falsely reused (trailing context may have changed).

- [ ] **Step 3: Run tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon test
```

- [ ] **Step 4: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add loom/src/core/parser_wbtest.mbt
git commit -m "test: add regression tests for try_reuse fast path"
```
