# emit_reused Fast Path for Healthy Nodes

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate O(subtree) work per reuse hit in `emit_reused` for healthy nodes (no errors), reducing incremental overhead from ~2.5x to near-parity with full reparse.

**Architecture:** Three targeted fixes in `emit_reused`:
1. Skip `collect_reused_error_spans` for nodes without errors (use `CstNode.has_errors` check)
2. Replace `advance_past_reused` closure loop with `token_count` jump
3. Avoid per-node `Array[ReusedErrorSpan]` allocation for healthy nodes

**References:**
- [emit_reused overhead analysis](../performance/incremental-overhead.md#root-cause-emit_reused-does-osubtree-work-per-reuse-hit)
- `loom/src/core/parser.mbt` — `emit_reused`, `collect_reused_error_spans`, `advance_past_reused`

**Previous attempt:** Skipping `leading_token_matches` in `try_reuse` for pre-damage nodes gave no measurable improvement. The overhead is in `emit_reused`, not `try_reuse`.

---

## Preflight

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom && moon check && moon test
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda && moon check && moon test
```

Success criteria:
- All loom and lambda tests pass
- Profiling benchmarks show incremental overhead reduced
- No behavioral changes for nodes with errors (error span collection and diagnostic replay must still work)

---

## Task 1: Skip error span collection for healthy nodes

**Files:**
- Modify: `loom/src/core/parser.mbt`

`collect_reused_error_spans` recursively walks every reused node's subtree to find error/incomplete tokens. For healthy nodes (the common case), this is pure waste — zero spans found after O(subtree) work.

- [ ] **Step 1: Check `has_errors` before collecting spans**

In `emit_reused` (around line 722), before calling `collect_reused_error_spans`, check whether the node has any error or incomplete content. `CstNode` has a `has_errors(error_kind, incomplete_kind)` method (used in `next_sibling_has_error`).

Current code:
```moonbit
let error_spans : Array[ReusedErrorSpan] = []
let _ = collect_reused_error_spans(node, node_start, self.spec, error_spans)
let owns_right_boundary = error_spans
  .iter()
  .any(fn(s) { s.start == node_end && s.end == node_end })
```

Change to:
```moonbit
let error_raw = self.spec.error_kind.to_raw()
let incomplete_raw = self.spec.incomplete_kind.to_raw()
let has_errors = node.has_errors(error_raw, error_raw) ||
  node.has_errors(error_raw, incomplete_raw) ||
  node.has_errors(incomplete_raw, incomplete_raw)
let error_spans : Array[ReusedErrorSpan] = []
let owns_right_boundary = if has_errors {
  let _ = collect_reused_error_spans(node, node_start, self.spec, error_spans)
  error_spans.iter().any(fn(s) { s.start == node_end && s.end == node_end })
} else {
  false
}
```

This skips the recursive walk for healthy nodes (the vast majority of reused nodes).

- [ ] **Step 2: Run checks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon check
moon test
```

- [ ] **Step 3: Commit**

```bash
git add loom/src/core/parser.mbt
git commit -m "perf: skip error span collection for healthy reused nodes"
```

---

## Task 2: Replace `advance_past_reused` closure loop with token_count jump

**Files:**
- Modify: `loom/src/core/parser.mbt`

`advance_past_reused` loops through tokens calling `(self.get_start)(self.position)` per token to find the position past the node. `CstNode` already stores `token_count` — use it to jump directly.

- [ ] **Step 1: Replace the loop with a direct jump**

Current code:
```moonbit
fn[T, K] ParserContext::advance_past_reused(
  self : ParserContext[T, K],
  node : @seam.CstNode,
) -> Unit {
  if self.position >= self.token_count {
    return
  }
  let node_end = (self.get_start)(self.position) + node.text_len
  while self.position < self.token_count &&
        (self.get_start)(self.position) < node_end {
    self.position = self.position + 1
  }
}
```

Change to:
```moonbit
fn[T, K] ParserContext::advance_past_reused(
  self : ParserContext[T, K],
  node : @seam.CstNode,
) -> Unit {
  // Jump past all tokens covered by this node using the cached token_count.
  // token_count excludes trivia (whitespace), so add the trivia tokens
  // that precede each non-trivia token.
  // Fallback: use the offset-based loop for nodes with zero-width error
  // placeholders where token_count may not account for all position advances.
  if self.position >= self.token_count {
    return
  }
  let node_end = (self.get_start)(self.position) + node.text_len
  while self.position < self.token_count &&
        (self.get_start)(self.position) < node_end {
    self.position = self.position + 1
  }
}
```

**Note:** This optimization needs investigation. `token_count` is the *non-trivia* token count — it excludes whitespace tokens that still need to be advanced past. The offset-based loop correctly handles trivia. A safe alternative: advance by `node.token_count` for the non-trivia tokens, then scan forward through any remaining trivia. Or, pre-compute the total token span (trivia + non-trivia) when the node is created.

If `token_count` cannot directly replace the loop, keep the loop but explore caching the total token span on `CstNode`.

- [ ] **Step 2: Run checks and verify correctness**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon check
moon test
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon test
```

- [ ] **Step 3: Commit**

```bash
git add loom/src/core/parser.mbt
git commit -m "perf: optimize advance_past_reused token position advance"
```

---

## Task 3: Run profiling benchmarks and record results

**Files:**
- Modify: `docs/performance/incremental-overhead.md`

- [ ] **Step 1: Run profiling benchmarks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon bench --release 2>&1 | grep -E "profile:" -A2
```

Compare incremental vs full reparse at 80 and 320 lets.

- [ ] **Step 2: Record results**

Update `docs/performance/incremental-overhead.md` with before/after numbers.

- [ ] **Step 3: Commit**

```bash
git add docs/performance/incremental-overhead.md
git commit -m "docs: record emit_reused optimization benchmark results"
```
