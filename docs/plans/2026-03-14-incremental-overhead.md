# Incremental Parser Overhead: Waste Elimination

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate three sources of constant-factor waste in incremental parsing to make it faster than full reparse.

**Architecture:** Three independent fixes targeting `token_buffer.mbt`, `reuse_cursor.mbt`, and `parser.mbt`/`event.mbt`. Each fix removes unnecessary O(n) work from the edit→reparse hot path. Fixes are independent and can be applied in any order.

**Tech Stack:** MoonBit, loom parser framework (`dowdiness/loom`)

**Reference:** [`docs/performance/incremental-overhead.md`](../performance/incremental-overhead.md)

---

## Chunk 1: Fix 1 + Fix 2

### Task 1: Remove defensive copy from `TokenBuffer::update`

**Files:**
- Modify: `loom/src/core/token_buffer.mbt:199-283`
- Modify: `loom/src/core/token_buffer_wbtest.mbt:2-17`
- Modify: `loom/src/factories.mbt:97`

The `update()` method returns `Array[TokenInfo[T]]` — a defensive `.copy()` of internal state. The sole caller (`factories.mbt:97`) discards the return with `let _`. Removing this eliminates an O(n) array copy on every edit.

- [ ] **Step 1: Write failing test — update returns Unit**

In `loom/src/core/token_buffer_wbtest.mbt`, add a test that verifies `update()` works without needing a return value:

```moonbit
///|
test "TokenBuffer::update: returns unit, internal state updated" {
  let buf = TokenBuffer::new(
    "ab",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
  )
  buf.update(Edit::insert(1, 1), "axb")
  // Verify internal tokens are updated via public accessor
  let stored = buf.get_tokens()
  inspect(stored[0].token, content="char")
  inspect(stored[0].len, content="1")
  inspect(buf.get_start(1), content="1")
  inspect(buf.get_end(1), content="2")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test -p dowdiness/loom/core -f token_buffer_wbtest.mbt`
Expected: FAIL — `update()` returns `Array[TokenInfo[T]]`, not `Unit`

- [ ] **Step 3: Change `update` return type to `Unit`**

In `loom/src/core/token_buffer.mbt`:

1. Line 203: Change signature from `-> Array[TokenInfo[T]] raise LexError` to `-> Unit raise LexError`
2. Line 213: Change `return self.tokens.copy()` to `return`
3. Line 282: Remove `self.tokens.copy()` (last line of function body)

- [ ] **Step 4: Update the caller in factories.mbt**

In `loom/src/factories.mbt`, line 97: Change `let _ = buffer.update(edit, source)` to `buffer.update(edit, source)`.
Also update the catch block (lines 98-117) — the dummy `[]` return on line 116 is no longer needed. Replace the entire `catch` block to match the new `Unit` return:

```moonbit
        Some(buffer) => {
          buffer.update(edit, source) catch {
            @core.LexError(msg) => {
              let rebuilt = create_buffer(
                source,
                tokenize,
                spec.eof_token,
                error_token,
                prefix_lexer~,
              ) catch {
                @core.LexError(msg2) => {
                  token_buf.val = None
                  last_diags.val = []
                  return @incremental.ParseOutcome::LexError(
                    "Tokenization error: " + msg2,
                  )
                }
              }
              ignore(msg)
              token_buf.val = Some(rebuilt)
            }
          }
        }
```

- [ ] **Step 5: Update the existing defensive copy test**

Replace the "TokenBuffer::update returns a defensive copy" test in `token_buffer_wbtest.mbt` (lines 2-17) with the new test from Step 1. The defensive copy test asserts `update()` returns an array, which no longer applies.

- [ ] **Step 6: Run tests to verify**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test -p dowdiness/loom/core && moon test -p dowdiness/loom/src`
Expected: All tests pass

- [ ] **Step 7: Update interfaces**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon info && moon fmt`
Verify `git diff *.mbti` shows only the `update` return type change.

- [ ] **Step 8: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add loom/src/core/token_buffer.mbt loom/src/core/token_buffer_wbtest.mbt loom/src/factories.mbt
git add -u -- '*.mbti'
git commit -m "perf: remove defensive copy from TokenBuffer::update

Change return type from Array[TokenInfo[T]] to Unit.
The sole caller discarded the return value. Saves O(n) array
copy per edit."
```

---

### Task 2: Lazy trailing-context token lookup

**Files:**
- Modify: `loom/src/core/reuse_cursor.mbt:35-125, 168-175, 220-232`

Replace the upfront `collect_old_tokens` O(n) tree walk with on-demand lookup. The old tree is already available via `ReuseCursor.stack` — we can walk from a given offset to find the first non-trivia leaf directly.

- [ ] **Step 1: Write failing test — old follow token from tree walk**

In `loom/src/core/reuse_cursor_wbtest.mbt` (create if needed — check existing file first), add:

```moonbit
///|
test "old_follow_token_from_tree: finds first non-trivia token at offset" {
  // Build a small tree: "1 + 2" → root contains tokens at offsets 0, 2, 4
  let (tree, _) = parse_with("1 + 2", test_spec, test_tokenize, test_grammar)
  let ws_raw = test_spec.whitespace_kind.to_raw()
  let err_raw = test_spec.error_kind.to_raw()
  let incomplete_raw = test_spec.incomplete_kind.to_raw()
  // After offset 1 (past "1"), first non-trivia token should be "+" at offset 2
  let result = old_follow_token_from_tree(tree, 0, 1, ws_raw, err_raw, incomplete_raw)
  inspect(result is Some(_), content="true")
  let tok = result.unwrap()
  inspect(tok.start, content="2")
  inspect(tok.text, content="+")
}

///|
test "old_follow_token_from_tree: returns None past end of tree" {
  let (tree, _) = parse_with("42", test_spec, test_tokenize, test_grammar)
  let ws_raw = test_spec.whitespace_kind.to_raw()
  let err_raw = test_spec.error_kind.to_raw()
  let incomplete_raw = test_spec.incomplete_kind.to_raw()
  let result = old_follow_token_from_tree(tree, 0, 99, ws_raw, err_raw, incomplete_raw)
  inspect(result is Some(_), content="false")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test -p dowdiness/loom/core -f reuse_cursor_wbtest.mbt`
Expected: FAIL — `old_follow_token_from_tree` does not exist

- [ ] **Step 3: Implement `old_follow_token_from_tree`**

In `reuse_cursor.mbt`, add a function that walks the old CST to find the first non-trivia, non-error leaf token starting at or after a given offset:

```moonbit
///|
/// Walk old CST to find the first non-trivia, non-error, non-incomplete leaf
/// token starting at or after `target_offset`. Returns OldToken or None.
/// O(depth) amortized — descends into the relevant subtree, skips siblings
/// before target_offset without entering them.
fn old_follow_token_from_tree(
  node : @seam.CstNode,
  node_start : Int,
  target_offset : Int,
  ws_raw : @seam.RawKind,
  err_raw : @seam.RawKind,
  incomplete_raw : @seam.RawKind,
) -> OldToken? {
  let node_end = node_start + node.text_len
  if node_end <= target_offset {
    return None
  }
  let mut offset = node_start
  for child in node.children {
    let child_width = child.text_len()
    let child_end = offset + child_width
    if child_end <= target_offset {
      offset = child_end
      continue
    }
    match child {
      @seam.CstElement::Token(t) => {
        if offset >= target_offset &&
          t.kind != ws_raw &&
          t.kind != err_raw &&
          t.kind != incomplete_raw {
          return Some({ kind: t.kind, text: t.text, start: offset })
        }
        offset = child_end
      }
      @seam.CstElement::Node(n) => {
        let result = old_follow_token_from_tree(
          n, offset, target_offset, ws_raw, err_raw, incomplete_raw,
        )
        if result is Some(_) {
          return result
        }
        offset = child_end
      }
    }
  }
  None
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test -p dowdiness/loom/core -f reuse_cursor_wbtest.mbt`
Expected: PASS

- [ ] **Step 5: Store old tree root in ReuseCursor instead of old_tokens array**

In `reuse_cursor.mbt`:

1. In `ReuseCursor` struct (line 35-47): Replace `old_tokens : Array[OldToken]` with:
   ```moonbit
   old_root : @seam.CstNode
   ws_raw : @seam.RawKind
   err_raw : @seam.RawKind
   incomplete_raw : @seam.RawKind
   ```

2. In `ReuseCursor::new` (lines 92-125): Remove the `collect_old_tokens` call and `old_tokens` array. Store the old tree root and raw kinds directly:
   ```moonbit
   let ws_raw = spec.whitespace_kind.to_raw()
   let err_raw = spec.error_kind.to_raw()
   let incomplete_raw = spec.incomplete_kind.to_raw()
   // ... (remove collect_old_tokens call)
   {
     stack,
     current_offset: 0,
     damage_start,
     damage_end,
     old_root: old_tree,
     ws_raw,
     err_raw,
     incomplete_raw,
     reuse_globally_disabled,
     // ... rest unchanged
   }
   ```

3. Update `old_follow_token` (lines 168-175) to delegate to the tree-walk function:
   ```moonbit
   fn[T, K] old_follow_token_lazy(
     cursor : ReuseCursor[T, K],
     offset : Int,
   ) -> OldToken? {
     old_follow_token_from_tree(
       cursor.old_root, 0, offset,
       cursor.ws_raw, cursor.err_raw, cursor.incomplete_raw,
     )
   }
   ```

4. Update `trailing_context_matches` (line 224): Change `old_follow_token(cursor.old_tokens, node_end)` to `old_follow_token_lazy(cursor, node_end)`.

5. Remove the `OffsetIndexed` impl for `Array[OldToken]` (lines 53-60) — no longer needed.

6. Update `snapshot` (lines 418-443): Replace `old_tokens` sharing with the new fields:
   ```moonbit
   pub fn[T, K] ReuseCursor::snapshot(
     self : ReuseCursor[T, K],
   ) -> ReuseCursor[T, K] {
     let stack : Array[CursorFrame] = []
     for frame in self.stack {
       stack.push({
         node: frame.node,
         child_index: frame.child_index,
         start_offset: frame.start_offset,
         current_child_offset: frame.current_child_offset,
       })
     }
     {
       stack,
       current_offset: self.current_offset,
       damage_start: self.damage_start,
       damage_end: self.damage_end,
       old_root: self.old_root,
       ws_raw: self.ws_raw,
       err_raw: self.err_raw,
       incomplete_raw: self.incomplete_raw,
       reuse_globally_disabled: self.reuse_globally_disabled,
       token_count: self.token_count,
       get_token: self.get_token,
       get_start: self.get_start,
       spec: self.spec,
     }
   }
   ```

- [ ] **Step 6: Remove `OldToken` struct and `collect_old_tokens` function**

In `reuse_cursor.mbt`:
- Keep the `OldToken` struct (lines 26-30) — it's still used as the return type of `old_follow_token_from_tree`.
- Delete `collect_old_tokens` function (lines 64-87) — no longer called.
- Remove the `OffsetIndexed` impl for `Array[OldToken]` (lines 53-60).

- [ ] **Step 7: Run all loom tests**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test -p dowdiness/loom/core && moon test -p dowdiness/loom/src`
Then run full suite: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test`
Expected: All tests pass

- [ ] **Step 8: Update interfaces**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon info && moon fmt`
Verify `git diff *.mbti` — `ReuseCursor` struct changes are internal (priv fields), so `.mbti` may not change.

- [ ] **Step 9: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add loom/src/core/reuse_cursor.mbt
git add loom/src/core/reuse_cursor_wbtest.mbt 2>/dev/null || true
git add -u -- '*.mbti'
git commit -m "perf: lazy trailing-context lookup in ReuseCursor

Replace upfront collect_old_tokens O(n) tree walk with on-demand
old_follow_token_from_tree. Only walks the subtree path to the
target offset — O(depth) per lookup instead of O(n) upfront."
```

---

## Chunk 2: Fix 3

### Task 3: `ReuseNode` event type to skip serialize/deserialize round-trip

**Files:**
- Modify: `seam/event.mbt:10-20, 230-289, 297-351, 167-218`
- Modify: `loom/src/core/parser.mbt:546-559, 740-780`

When a subtree is reused, `emit_node_events` recursively walks the CstNode to emit StartNode/Token/FinishNode events, then `build_tree_fully_interned` reconstructs the same CstNode from those events. Adding a `ReuseNode(CstNode)` event lets the tree builder attach the canonical node directly.

- [ ] **Step 1: Add `ReuseNode` variant to `ParseEvent`**

In `seam/event.mbt`, line 10-20, add a new variant:

```moonbit
pub(all) enum ParseEvent {
  StartNode(RawKind)
  FinishNode
  Token(RawKind, String)
  Tombstone
  /// Attach an already-built subtree directly, skipping event serialization.
  ReuseNode(CstNode)
} derive(Show, Eq)
```

- [ ] **Step 2: Run tests to see what breaks**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon check`
Expected: Non-exhaustive match warnings/errors in `build_tree`, `build_tree_interned`, `build_tree_fully_interned`

- [ ] **Step 3: Handle `ReuseNode` in all three `build_tree` variants**

In `seam/event.mbt`:

For `build_tree` (line 297-351), add after the `Tombstone` case:
```moonbit
      ReuseNode(node) =>
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => abort("build_tree: stack empty when adding ReuseNode")
        }
```

For `build_tree_interned` (line 167-218), add after the `Tombstone` case:
```moonbit
      ReuseNode(node) =>
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => abort("build_tree_interned: stack empty when adding ReuseNode")
        }
```

For `build_tree_fully_interned` (line 230-289), add after the `Tombstone` case:
```moonbit
      // Reused node is already interned from the previous parse — the
      // process-global NodeInterner is never cleared, so the canonical
      // reference is still valid. No need to re-intern.
      ReuseNode(node) =>
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort(
              "build_tree_fully_interned: stack empty when adding ReuseNode",
            )
        }
```

- [ ] **Step 4: Write unit test for ReuseNode in build_tree**

In `seam/event_wbtest.mbt` (or `seam/event_test.mbt` — use whichever exists), add:

```moonbit
///|
test "build_tree: ReuseNode attaches subtree directly" {
  // Build a child node first
  let child = CstNode::new(
    RawKind(1),
    [CstElement::Token(CstToken::new(RawKind(2), "x"))],
  )
  // Build a parent tree using ReuseNode event
  let events : Array[ParseEvent] = [
    StartNode(RawKind(3)),
    ReuseNode(child),
    FinishNode,
  ]
  let root = build_tree(events, RawKind(0))
  // Root should have one child node (kind 3) containing the reused child
  inspect(root.children.length(), content="1")
  match root.children[0] {
    Node(n) => {
      inspect(n.kind, content="RawKind(3)")
      inspect(n.children.length(), content="1")
      match n.children[0] {
        Node(inner) => inspect(inner.kind, content="RawKind(1)")
        _ => abort("expected Node")
      }
    }
    _ => abort("expected Node")
  }
}
```

- [ ] **Step 5: Run seam tests to verify**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test -p dowdiness/seam`
Expected: All tests pass

- [ ] **Step 6: Replace `emit_node_events` with `ReuseNode` event in parser**

In `loom/src/core/parser.mbt`:

1. Replace `emit_node_events` (lines 546-559) body to emit a single `ReuseNode` event:
```moonbit
fn[T, K] ParserContext::emit_node_events(
  self : ParserContext[T, K],
  node : @seam.CstNode,
) -> Unit {
  self.events.push(@seam.ParseEvent::ReuseNode(node))
}
```

- [ ] **Step 7: Run all loom tests**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test`
Expected: All tests pass

- [ ] **Step 8: Run crdt editor tests**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test`
Expected: All tests pass (editor depends on loom parser)

- [ ] **Step 9: Run benchmarks**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon bench --release`
Expected: Incremental should now be faster than reparse for flat grammar with 320 lets.

- [ ] **Step 10: Update interfaces and format**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon info && moon fmt`
Verify `git diff *.mbti` — `ParseEvent` enum gains `ReuseNode(CstNode)` variant.

- [ ] **Step 11: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add seam/event.mbt seam/event_wbtest.mbt seam/event_test.mbt loom/src/core/parser.mbt 2>/dev/null || true
git add -u -- '*.mbti'
git commit -m "perf: ReuseNode event skips serialize/deserialize round-trip

Add ReuseNode(CstNode) variant to ParseEvent. Reused subtrees are
attached directly to the parent during tree construction instead of
being serialized to events then reconstructed."
```

---

### Task 4: Update documentation and verify

**Files:**
- Modify: `docs/performance/incremental-overhead.md`

- [ ] **Step 1: Update incremental-overhead.md**

Add `**Status:** Complete` near the top and note all three findings are resolved.

- [ ] **Step 2: Final full test suite**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom && moon test`
Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add docs/performance/incremental-overhead.md
git commit -m "docs: mark incremental overhead findings as complete"
```
