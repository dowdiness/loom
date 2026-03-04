# loom/core Simplification — Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Three targeted improvements to `loom/src/core/`: fix an O(width) performance regression in `ReuseCursor`, clarify opaque coordinate variable names in `TokenBuffer`, and split the 994-line `lib.mbt` into focused files.

**Architecture:** All three tasks touch `loom/src/core/` only. They are independent — each can be verified with `moon test` before starting the next. Order: (1) token_buffer renames (lowest risk), (2) CursorFrame fix (algorithmic), (3) lib.mbt split (mechanical reorganization).

**Tech Stack:** MoonBit, `moon` build system. All commands run from `loom/` unless otherwise noted.

---

## Background

Read the design doc before starting:
`docs/plans/2026-03-04-loom-core-simplification-design.md`

The two-contract model that guides every decision here:
- **External contract:** any source text, any edit → correct tree, never panic
- **Internal contract:** invariant violations abort immediately (don't silently mask bugs)

---

## Task 1: Rename coordinate variables in `token_buffer.mbt` + replace dead swap with `abort`

**Files:**
- Modify: `loom/src/core/token_buffer.mbt` (lines 43–113)

The `update()` function operates in four coordinate spaces simultaneously (old token index, new token index, old source offset, new source offset). Current names (`left_index`, `right_offset`) don't say which space they're in. One defensive swap (line 64) is dead code after the expand-left step — it masks future bugs.

### Step 1: Run the baseline test suite

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all tests pass. Note the count. This is your rollback baseline.

### Step 2: Open `loom/src/core/token_buffer.mbt` and replace the variable block

Find this block in `update()` (starts around line 58):

```moonbit
  let mut left_index = find_left_index(old_tokens, edit.start)
  let mut right_index = find_right_index(old_tokens, edit.old_end())
  // Conservative: expand left by one token to catch boundary edits.
  if left_index > 0 {
    left_index = left_index - 1
  }
  if left_index > right_index {
    let tmp = right_index
    right_index = left_index
    left_index = tmp
  }
  if right_index < eof_index {
    right_index = right_index + 1
  }
  let mut left_offset_old = old_tokens[left_index].start
  if edit.start < left_offset_old {
    left_offset_old = edit.start
  }
  let mut right_offset_old = old_tokens[right_index].end
  if edit.old_end() > right_offset_old {
    right_offset_old = edit.old_end()
  }
  let left_offset_new = map_start_pos(left_offset_old, edit)
  let right_offset_new = map_end_pos(right_offset_old, edit)
  let new_len = new_source.length()
  let left_offset = clamp_offset(left_offset_new, new_len)
  let mut right_offset = clamp_offset(right_offset_new, new_len)
  if right_offset < left_offset {
    right_offset = left_offset
  }
```

Replace with:

```moonbit
  let mut left_tok_idx = find_left_index(old_tokens, edit.start)
  let mut right_tok_idx = find_right_index(old_tokens, edit.old_end())
  // Conservative: expand left by one token to catch boundary edits.
  if left_tok_idx > 0 {
    left_tok_idx = left_tok_idx - 1
  }
  // After expand-left, left_tok_idx <= right_tok_idx by construction.
  // If this fires it is a programming error in this function, not bad input.
  if left_tok_idx > right_tok_idx {
    abort("internal: left_tok_idx > right_tok_idx after expand-left")
  }
  if right_tok_idx < eof_index {
    right_tok_idx = right_tok_idx + 1
  }
  let mut left_old_offset = old_tokens[left_tok_idx].start
  if edit.start < left_old_offset {
    left_old_offset = edit.start
  }
  let mut right_old_offset = old_tokens[right_tok_idx].end
  if edit.old_end() > right_old_offset {
    right_old_offset = edit.old_end()
  }
  let left_new_offset = map_start_pos(left_old_offset, edit)
  let right_new_offset = map_end_pos(right_old_offset, edit)
  let new_len = new_source.length()
  let left_clamped = clamp_offset(left_new_offset, new_len)
  let mut right_clamped = clamp_offset(right_new_offset, new_len)
  if right_clamped < left_clamped {
    right_clamped = left_clamped
  }
```

### Step 3: Update the three downstream references in `update()`

Find the three places that use the old names after the renamed block:

```moonbit
  let replacement_tokens = self.tokenize_range_impl(
    new_source, left_offset, right_offset,
  )
  let new_tokens : Array[TokenInfo[T]] = []
  for i = 0; i < left_index; i = i + 1 {
    new_tokens.push(old_tokens[i])
  }
  ...
  for i = right_index + 1; i < eof_index; i = i + 1 {
```

Replace with:

```moonbit
  let replacement_tokens = self.tokenize_range_impl(
    new_source, left_clamped, right_clamped,
  )
  let new_tokens : Array[TokenInfo[T]] = []
  for i = 0; i < left_tok_idx; i = i + 1 {
    new_tokens.push(old_tokens[i])
  }
  ...
  for i = right_tok_idx + 1; i < eof_index; i = i + 1 {
```

### Step 4: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: same test count as Step 1, all pass.

Also run the full loom suite:
```bash
cd loom && moon test
```

Expected: all tests pass.

### Step 5: Format and commit

```bash
cd loom && moon fmt
git add loom/src/core/token_buffer.mbt
git commit -m "refactor(core): rename token_buffer coordinate variables, abort on dead invariant"
```

---

## Task 2: Fix O(width) regression in `reuse_cursor.mbt`

**Files:**
- Modify: `loom/src/core/reuse_cursor.mbt`

**Background:** `CursorFrame` lacks a `current_child_offset` field. When `seek_node_at` resumes a frame after ascending from a child, it recomputes the child's start offset by walking from index 0 to `child_index`. For a node with W children this is O(W) per resume. The fix: cache `current_child_offset` in the frame and update it incrementally.

### Step 1: Run the baseline test suite

```bash
cd loom && moon test -p dowdiness/loom/core
```

Note the count. All tests must pass before proceeding.

### Step 2: Add `current_child_offset` to `CursorFrame`

Find `CursorFrame` (lines 14–18):

```moonbit
struct CursorFrame {
  node : @seam.CstNode
  mut child_index : Int
  start_offset : Int
}
```

Replace with:

```moonbit
struct CursorFrame {
  node : @seam.CstNode
  mut child_index : Int
  start_offset : Int
  /// Offset of the child at child_index. Maintained incrementally
  /// so seek_node_at does not need to recompute it from scratch on resume.
  mut current_child_offset : Int
}
```

### Step 3: Update the root frame construction in `ReuseCursor::new`

Find (line ~102):

```moonbit
  let stack = [{ node: old_tree, child_index: 0, start_offset: 0 }]
```

Replace with:

```moonbit
  let stack = [{ node: old_tree, child_index: 0, start_offset: 0, current_child_offset: 0 }]
```

### Step 4: Extract `pop_frame` helper — add it before `seek_node_at`

The pattern of popping a frame and advancing the parent's index appears twice in `seek_node_at`. Extract it into a helper. Insert this function before `seek_node_at`:

```moonbit
///|
/// Pop the top frame and advance the parent frame's child cursor past it.
/// current_child_offset in the parent advances to the end of the popped frame.
fn[T, K] ReuseCursor::pop_frame(self : ReuseCursor[T, K]) -> Unit {
  let frame = self.stack[self.stack.length() - 1]
  let frame_end = frame.start_offset + frame.node.text_len
  let _ = self.stack.pop()
  if self.stack.length() > 0 {
    let parent = self.stack[self.stack.length() - 1]
    parent.child_index = parent.child_index + 1
    parent.current_child_offset = frame_end
  }
}
```

### Step 5: Rewrite `seek_node_at` with the fix

Replace the entire `seek_node_at` function (lines 279–356) with:

```moonbit
///|
/// Advance through the old tree to find a node at target_offset with expected_kind.
/// O(depth) because we only descend/ascend as needed.
/// current_child_offset in each CursorFrame is maintained incrementally — no
/// O(width) recomputation on frame resume.
fn[T, K] ReuseCursor::seek_node_at(
  self : ReuseCursor[T, K],
  target_offset : Int,
  expected_kind : @seam.RawKind,
) -> (@seam.CstNode, Int)? {
  // If target is before current position, reset to root
  if target_offset < self.current_offset {
    let root_frame = self.stack[0]
    let _ = self.stack.drain(1, self.stack.length())
    root_frame.child_index = 0
    root_frame.current_child_offset = 0
    self.current_offset = 0
  }
  while self.stack.length() > 0 {
    let frame = self.stack[self.stack.length() - 1]
    let node = frame.node
    // Check if current frame matches
    if frame.start_offset == target_offset && node.kind == expected_kind {
      return Some((node, frame.start_offset))
    }
    // If target is outside this node's range, pop up
    let node_end = frame.start_offset + node.text_len
    if target_offset < frame.start_offset || target_offset >= node_end {
      self.pop_frame()
      continue
    }
    // Target is within this node — resume from cached child offset (O(1))
    let mut child_offset = frame.current_child_offset
    let mut found_child = false
    // Search remaining children from where we left off
    while frame.child_index < node.children.length() {
      let child = node.children[frame.child_index]
      let child_width = element_width(child)
      let child_end = child_offset + child_width
      if target_offset < child_offset {
        break
      }
      if target_offset < child_end {
        match child {
          @seam.CstElement::Node(child_node) => {
            if child_offset == target_offset && child_node.kind == expected_kind {
              self.current_offset = child_offset
              return Some((child_node, child_offset))
            }
            self.stack.push({
              node: child_node,
              child_index: 0,
              start_offset: child_offset,
              current_child_offset: child_offset,
            })
            found_child = true
            break
          }
          @seam.CstElement::Token(_) => {
            self.current_offset = child_offset
            return None
          }
        }
      }
      child_offset = child_end
      frame.current_child_offset = child_end  // keep frame in sync
      frame.child_index = frame.child_index + 1
    }
    if not(found_child) {
      self.pop_frame()
    }
  }
  None
}
```

### Step 6: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: same count as Step 1, all pass.

Also run the full suite:
```bash
cd loom && moon test
```

And run the lambda example tests (exercises `seek_node_at` via the incremental parser):
```bash
cd loom && moon test -p dowdiness/lambda/src
```

Expected: all pass.

### Step 7: Format and commit

```bash
cd loom && moon fmt
git add loom/src/core/reuse_cursor.mbt
git commit -m "perf(core): fix O(width) regression in CursorFrame, extract pop_frame helper"
```

---

## Task 3: Split `lib.mbt` into `diagnostics.mbt` + `parser.mbt`

**Files:**
- Create: `loom/src/core/diagnostics.mbt`
- Create: `loom/src/core/parser.mbt`
- Create: `loom/src/core/parser_wbtest.mbt`
- Delete: `loom/src/core/lib.mbt`
- Delete: `loom/src/core/lib_wbtest.mbt`

**Background:** `lib.mbt` (994 lines) mixes four unrelated concerns. In MoonBit, all `.mbt` files in a package contribute to the same namespace — no imports between files are needed.

### Step 1: Run the baseline test suite

```bash
cd loom && moon test -p dowdiness/loom/core
```

Note the exact count. This is your correctness baseline.

### Step 2: Create `diagnostics.mbt`

Create `loom/src/core/diagnostics.mbt` containing only the data type definitions. Cut from `lib.mbt`:

```moonbit
// Parse data types: token information, diagnostics, and lex errors.

///|
/// Generic token with source position. T is the language-specific token type.
pub struct TokenInfo[T] {
  token : T
  start : Int // code-unit offset, inclusive
  end : Int // code-unit offset, exclusive
} derive(Show, Eq)

///|
/// A parse diagnostic (error or warning) with source position.
/// Stores the offending token so consumers never need to re-tokenize.
pub struct Diagnostic[T] {
  message : String
  start : Int
  end : Int
  got_token : T
} derive(Show)

///|
/// Format a diagnostic as `"message [start,end]"`.
/// Used by factory functions to normalize diagnostics for parser consumers.
pub fn[T] format_diagnostic(d : Diagnostic[T]) -> String {
  d.message + " [" + d.start.to_string() + "," + d.end.to_string() + "]"
}

///|
/// Lex error raised by a tokenize_fn when the source contains unrecognizable input.
/// Generic replacement for language-specific tokenization error types.
pub(all) suberror LexError {
  LexError(String)
}

///|
/// Construct a TokenInfo. Use this from outside the core package.
pub fn[T] TokenInfo::new(token : T, start : Int, end : Int) -> TokenInfo[T] {
  { token, start, end }
}

///|
priv struct ReusedErrorSpan {
  start : Int
  end : Int
}
```

Note: `ReusedErrorSpan` is private and used only in `lib.mbt`'s incremental reuse logic. It moves here because it is a data type.

### Step 3: Create `parser.mbt`

Create `loom/src/core/parser.mbt` containing:
1. The file header comment from `lib.mbt` (line 1)
2. `OffsetIndexed` + `lower_bound` (lines 3–45 of lib.mbt)
3. `LanguageSpec` struct + constructor (lines 79–155 of lib.mbt)
4. `ParserContext` struct + all constructors and methods (lines 157–782 of lib.mbt), **excluding** the inline tests block (lines 783–883)
5. `parse_with` + `build_tree_generic` + `parse_tokens_indexed` (lines 884–976)
6. `AstView` trait (lines 978–993)

**Do not copy** into parser.mbt:
- `TokenInfo`, `Diagnostic`, `format_diagnostic`, `LexError`, `TokenInfo::new`, `ReusedErrorSpan` — these are now in `diagnostics.mbt`
- The inline test block (`test "TokenInfo stores token..." through test "at matches current token"`) — these go into `parser_wbtest.mbt`

The file should start with:
```moonbit
// Generic parser infrastructure — ParserContext[T, K]
```

And end with the `AstView` trait (cut from the bottom of lib.mbt):
```moonbit
///|
/// Marker trait for typed SyntaxNode view types.
///
/// Every view type in your language package should implement this trait
/// and also provide a `pub fn ViewType::cast(n : @seam.SyntaxNode) -> Self?`
/// static function (can't be in the trait — MoonBit traits require self
/// as first parameter).
///
/// Example:
///   pub struct LambdaExprView { node : @seam.SyntaxNode }
///   pub impl AstView for LambdaExprView with syntax_node(self) { self.node }
///   pub fn LambdaExprView::cast(n : @seam.SyntaxNode) -> LambdaExprView? { ... }
pub(open) trait AstView {
  /// Return the underlying raw SyntaxNode.
  syntax_node(Self) -> @seam.SyntaxNode
}
```

### Step 4: Create `parser_wbtest.mbt`

Create `loom/src/core/parser_wbtest.mbt` as the combination of:
1. The inline tests from `lib.mbt` (the block from `test "TokenInfo stores token..."` through `test "at matches current token"`)
2. The entire content of `lib_wbtest.mbt` (starting from line 1)

The new file should start with:
```moonbit
// Whitebox tests for the core parser — ParserContext, LanguageSpec, ReuseCursor.
// These tests access package-private symbols (e.g. new_follow_token) and define
// test-only types (TestTok, TestKind) that must not appear in the public interface.
```

Followed by all tests from both sources, separated by a blank line.

### Step 5: Delete the old files

```bash
rm loom/src/core/lib.mbt
rm loom/src/core/lib_wbtest.mbt
```

In MoonBit, there is no file registry — removing a file just removes its contributions to the package. No other files need to be updated.

### Step 6: Verify — run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: identical test count and all pass.

If count differs: a test was accidentally omitted or duplicated. Compare `git diff --stat` to check line counts.

Run the full suite:
```bash
cd loom && moon test
```

Expected: all pass.

### Step 7: Update interfaces and format

```bash
cd loom && moon info && moon fmt
```

Check the generated interface diff — it should be identical (no public API change):

```bash
git diff loom/src/core/core.mbti
```

Expected: no diff (content identical, filename reference in comments may change).

### Step 8: Validate docs (no new .md files — skip update)

No `.md` files were added or moved, so `check-docs.sh` does not need updating.

```bash
bash check-docs.sh
```

Expected: `All checks passed.`

### Step 9: Commit

```bash
git add loom/src/core/diagnostics.mbt loom/src/core/parser.mbt loom/src/core/parser_wbtest.mbt
git rm loom/src/core/lib.mbt loom/src/core/lib_wbtest.mbt
git commit -m "refactor(core): split lib.mbt into diagnostics.mbt + parser.mbt, rename wbtest"
```

---

## Verification checklist

After all three tasks:

```bash
cd loom && moon test        # full suite: all pass
cd loom && moon check       # no lint warnings
cd loom && moon info        # regenerate .mbti
git diff *.mbti             # should be empty (no public API change)
cd loom && moon fmt         # clean
bash check-docs.sh          # all checks passed
```
