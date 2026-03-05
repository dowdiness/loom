# loom Error Recovery Combinators — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add reusable error recovery combinators to `loom/src/core/` so grammar authors can write resilient parsers without hand-rolling recovery logic. Five combinators: `expect`, `skip_until`, `skip_until_balanced`, `node_with_recovery`, `expect_and_recover`.

**Architecture:** All combinators are added in a single new file `loom/src/core/recovery.mbt`. Tests go in `loom/src/core/recovery_wbtest.mbt`. No new package dependencies — only existing `@seam` traits are used. Combinators build on existing `ParserContext` primitives (`bump_error`, `emit_error_placeholder`, `error`, `start_node`/`finish_node`, `try_reuse`/`emit_reused`). Tests reuse `TestTok`, `TestKind`, `test_spec`, `test_tokenize` from `loom/src/core/parser_wbtest.mbt`.

**Tech Stack:** MoonBit, `moon` build system. All `moon` commands run from `loom/`.

---

## Background

Read before starting:
- `loom/src/core/parser.mbt` — `ParserContext` struct and existing methods (`bump_error`, `emit_error_placeholder`, `error`, `emit_token`, `node`, `try_reuse`, `emit_reused`, `start_node`, `finish_node`, `at`, `at_eof`, `peek`, `flush_trivia`)
- `loom/src/core/parser_wbtest.mbt` — test fixtures: `TestTok` enum, `TestKind` enum, `test_spec` constant, `test_tokenize` function, `test_grammar` function
- `loom/src/core/diagnostics.mbt` — `Diagnostic[T]` struct

**Key conventions:**
- Tests live in `loom/src/core/recovery_wbtest.mbt` (whitebox — same package, access private symbols)
- Test fixtures (`TestTok`, `TestKind`, `test_spec`, `test_tokenize`) are defined in `parser_wbtest.mbt` and visible within the same package without import
- Test assertions use `inspect(expr, content="expected_string")`
- Run tests: `cd loom && moon test -p dowdiness/loom/core`
- Run all tests: `cd loom && moon test`

**Critical context — existing primitives:**

```moonbit
// Already in ParserContext (parser.mbt):
pub fn bump_error(self)              // consume token as error leaf
pub fn emit_error_placeholder(self)  // zero-width error token
pub fn error(self, msg : String)     // record diagnostic
pub fn emit_token(self, kind : K)    // consume + emit leaf
pub fn at(self, token : T) -> Bool   // peek == token?
pub fn at_eof(self) -> Bool          // past end?
pub fn peek(self) -> T               // next non-trivia token
pub fn start_node(self, kind : K)    // open node
pub fn finish_node(self)             // close node
pub fn try_reuse(self, kind : K) -> CstNode?  // incremental reuse
pub fn emit_reused(self, node)       // replay reused subtree
pub fn node(self, kind, body)        // reuse-aware node combinator
```

**TestTok and TestKind (from parser_wbtest.mbt):**

```moonbit
enum TestTok { Num(Int); Plus; Ws; TokEof } derive(Eq, Show)
impl @seam.IsTrivia for TestTok  // Ws is trivia
impl @seam.IsEof for TestTok     // TokEof is eof

enum TestKind { KNum; KPlus; KExpr; KRoot; KWs; KErr } derive(Show)
impl @seam.ToRawKind for TestKind

let test_spec : LanguageSpec[TestTok, TestKind]  // error_kind = KErr
fn test_tokenize(src : String) -> Array[TokenInfo[TestTok]]
```

---

## Task 1: Create `recovery.mbt` with `expect`

**Files:**
- Create: `loom/src/core/recovery.mbt`
- Create: `loom/src/core/recovery_wbtest.mbt`

### Step 1: Create `recovery.mbt` with the file header and `expect`

Create `loom/src/core/recovery.mbt`:

```moonbit
// Error recovery combinators for ParserContext.
//
// These build on the existing primitives (bump_error, emit_error_placeholder,
// error, start_node/finish_node) to provide reusable patterns that grammar
// authors can call instead of hand-rolling recovery logic.
//
// All combinators produce well-formed CST subtrees: every error-recovery
// path emits nodes/tokens that the ReuseCursor, diagnostic replay, and
// incr backdating machinery already handle correctly.

// ─── expect ───────────────────────────────────────────────────────────────────

///|
/// Consume the current token if it matches `expected`, otherwise record a
/// diagnostic and emit a zero-width error placeholder.
///
/// Returns true when the token was consumed normally, false when recovery fired.
/// The grammar can branch on the return value when the missing token changes
/// subsequent parse logic (e.g. a missing `)` means "stop parsing arguments").
///
/// Error message is auto-generated from `T : Show`:
///   "expected <expected>, got <actual>"
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::expect(
  self : ParserContext[T, K],
  expected : T,
  kind : K,
) -> Bool {
  if self.at(expected) {
    self.emit_token(kind)
    true
  } else {
    let got = self.peek()
    self.error("expected " + expected.to_string() + ", got " + got.to_string())
    self.emit_error_placeholder()
    false
  }
}
```

### Step 2: Create `recovery_wbtest.mbt` with tests for `expect`

Create `loom/src/core/recovery_wbtest.mbt`:

```moonbit
// Whitebox tests for recovery combinators.
// Reuses TestTok, TestKind, test_spec, test_tokenize from parser_wbtest.mbt.

// ─── expect ───────────────────────────────────────────────────────────────────

///|
test "expect: consumes matching token and returns true" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  ctx.finish_node()
  inspect(ok, content="true")
  inspect(ctx.errors.length(), content="0")
}

///|
test "expect: emits placeholder and diagnostic on mismatch" {
  let src = "+ 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  // Token should NOT be consumed — still at "+"
  inspect(ok, content="false")
  inspect(ctx.errors.length(), content="1")
  // Auto-generated message includes Show of both tokens
  inspect(
    ctx.errors[0].message.contains("expected") && ctx.errors[0].message.contains("Plus"),
    content="true",
  )
  // Position unchanged — "+" is still the current token
  inspect(ctx.at(TestTok::Plus), content="true")
  ctx.finish_node()
}

///|
test "expect: at EOF emits placeholder with eof in message" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  inspect(ok, content="false")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message.contains("TokEof"), content="true")
  ctx.finish_node()
}
```

### Step 3: Run to verify tests pass

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all tests pass (3 new + all existing).

---

## Task 2: Add `skip_until`

**Files:**
- Modify: `loom/src/core/recovery.mbt` (append)
- Modify: `loom/src/core/recovery_wbtest.mbt` (append)

### Step 1: Append `skip_until` to `recovery.mbt`

Append after `expect`:

```moonbit
// ─── skip_until ───────────────────────────────────────────────────────────────

///|
/// Skip tokens until `is_sync(token)` returns true or EOF is reached.
///
/// Skipped tokens are wrapped in a single error-kind node so they form one
/// contiguous error region in the CST rather than a sequence of individual
/// error tokens. The wrapping node is only emitted when at least one token
/// is actually skipped (no empty error nodes are produced).
///
/// Returns the number of tokens consumed. Zero means the current token was
/// already a sync point (or EOF), so no recovery was needed.
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until(
  self : ParserContext[T, K],
  is_sync : (T) -> Bool,
) -> Int {
  let mut count = 0
  let needs_wrap = not(self.at_eof()) && not(is_sync(self.peek()))
  if needs_wrap {
    self.start_node(self.spec.error_kind)
  }
  while not(self.at_eof()) && not(is_sync(self.peek())) {
    self.bump_error()
    count = count + 1
  }
  if needs_wrap {
    self.finish_node()
  }
  count
}
```

### Step 2: Append tests to `recovery_wbtest.mbt`

```moonbit
// ─── skip_until ───────────────────────────────────────────────────────────────

///|
test "skip_until: skips to sync token" {
  // "1 + 2" — skip until we see Num(2)
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(fn(t) {
    match t {
      Num(2) => true
      _ => false
    }
  })
  inspect(skipped, content="2") // Num(1) and Plus
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}

///|
test "skip_until: returns 0 when already at sync point" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(fn(t) {
    match t {
      Num(_) => true
      _ => false
    }
  })
  inspect(skipped, content="0")
  inspect(ctx.at(TestTok::Num(1)), content="true")
  ctx.finish_node()
}

///|
test "skip_until: skips to EOF when no sync found" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(fn(_t) { false }) // nothing is sync
  inspect(skipped, content="3") // Num(1), Plus, Num(2)
  inspect(ctx.at_eof(), content="true")
  ctx.finish_node()
}

///|
test "skip_until: returns 0 on empty input" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(fn(_t) { false })
  inspect(skipped, content="0")
  ctx.finish_node()
}
```

### Step 3: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass (4 new + previous).

---

## Task 3: Add `skip_until_balanced`

**Files:**
- Modify: `loom/src/core/recovery.mbt` (append)
- Modify: `loom/src/core/recovery_wbtest.mbt` (append)

### Step 1: Append `skip_until_balanced` to `recovery.mbt`

```moonbit
// ─── skip_until_balanced ──────────────────────────────────────────────────────

///|
/// Skip tokens until `is_close(token)` at bracket nesting depth 0, or EOF.
///
/// Respects bracket nesting: encountering `is_open` increments depth,
/// `is_close` decrements it. Only a close at depth 0 stops the skip.
/// Skipped tokens are wrapped in a single error-kind node.
///
/// The closing token itself is NOT consumed — the caller decides whether
/// to emit it (common for `)` recovery) or leave it for the parent.
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until_balanced(
  self : ParserContext[T, K],
  is_open : (T) -> Bool,
  is_close : (T) -> Bool,
) -> Int {
  let mut depth = 0
  let mut count = 0
  let needs_wrap = not(self.at_eof()) && not(is_close(self.peek()) && depth == 0)
  if needs_wrap {
    self.start_node(self.spec.error_kind)
  }
  while not(self.at_eof()) {
    let t = self.peek()
    if is_close(t) && depth == 0 {
      break
    }
    if is_open(t) {
      depth = depth + 1
    } else if is_close(t) {
      depth = depth - 1
    }
    self.bump_error()
    count = count + 1
  }
  if needs_wrap {
    self.finish_node()
  }
  count
}
```

### Step 2: Append tests to `recovery_wbtest.mbt`

```moonbit
// ─── skip_until_balanced ──────────────────────────────────────────────────────

///|
test "skip_until_balanced: stops at close at depth 0" {
  // "1 + 2" — treat Plus as close, no open tokens
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_balanced(
    fn(_t) { false }, // no open
    fn(t) { t == TestTok::Plus }, // Plus is close
  )
  inspect(skipped, content="1") // skipped Num(1)
  inspect(ctx.at(TestTok::Plus), content="true") // Plus not consumed
  ctx.finish_node()
}

///|
test "skip_until_balanced: respects nesting depth" {
  // "1 + + 2" — tokens: [Num(1), Plus, Plus, Num(2)]
  // is_open = Num(1), is_close = Plus
  //   Num(1) → open, depth=1, skip
  //   Plus → close, depth=0, skip
  //   Plus → close at depth 0, BREAK
  //   → skipped 2, now at second Plus
  let src = "1 + + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_balanced(
    fn(t) {
      match t {
        Num(1) => true
        _ => false
      }
    },
    fn(t) { t == TestTok::Plus },
  )
  inspect(skipped, content="2") // Num(1) and first Plus
  inspect(ctx.at(TestTok::Plus), content="true") // second Plus not consumed
  ctx.finish_node()
}
```

### Step 3: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass (2 new + previous).

---

## Task 4: Add `node_with_recovery`

**Files:**
- Modify: `loom/src/core/recovery.mbt` (append)
- Modify: `loom/src/core/recovery_wbtest.mbt` (append)

### Step 1: Append `node_with_recovery` to `recovery.mbt`

```moonbit
// ─── node_with_recovery ───────────────────────────────────────────────────────

///|
/// Reuse-aware node combinator with automatic recovery on failure.
///
/// `body` returns true on success, false when it cannot make progress.
/// On failure, `skip_until(is_sync)` is called inside the node to consume
/// unexpected tokens before closing it.
///
/// Reuse fast-path: if an old subtree can be reused, `body` and `is_sync`
/// are never called (same semantics as `node()`).
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::node_with_recovery(
  self : ParserContext[T, K],
  kind : K,
  body : () -> Bool,
  is_sync : (T) -> Bool,
) -> Unit {
  if self.try_reuse(kind) is Some(reuse) {
    self.emit_reused(reuse)
    return
  }
  self.start_node(kind)
  let ok = body()
  if not(ok) {
    let _ = self.skip_until(is_sync)
  }
  self.finish_node()
}
```

### Step 2: Append tests to `recovery_wbtest.mbt`

```moonbit
// ─── node_with_recovery ───────────────────────────────────────────────────────

///|
test "node_with_recovery: success path — no recovery" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.node_with_recovery(
    KExpr,
    fn() {
      ctx.emit_token(KNum)
      true
    },
    fn(_t) { true },
  )
  ctx.finish_node()
  inspect(ctx.errors.length(), content="0")
  inspect(ctx.at_eof(), content="true")
}

///|
test "node_with_recovery: failure triggers skip_until" {
  // "1 + + 2" — parse Num, then fail, recover at second Num
  let src = "1 + + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.node_with_recovery(
    KExpr,
    fn() {
      ctx.emit_token(KNum) // consume "1"
      ctx.error("expected end of expression")
      false // signal failure → triggers recovery
    },
    fn(t) {
      match t {
        Num(_) => true // sync at next number
        _ => false
      }
    },
  )
  // After recovery: "+" "+" were skipped, now at Num(2)
  inspect(ctx.at(TestTok::Num(2)), content="true")
  inspect(ctx.errors.length(), content="1")
  ctx.finish_node()
}
```

### Step 3: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass (2 new + previous).

---

## Task 5: Add `expect_and_recover`

**Files:**
- Modify: `loom/src/core/recovery.mbt` (append)
- Modify: `loom/src/core/recovery_wbtest.mbt` (append)

### Step 1: Append `expect_and_recover` to `recovery.mbt`

```moonbit
// ─── expect_and_recover ───────────────────────────────────────────────────────

///|
/// Expect a token; on mismatch, skip unexpected tokens until a sync point
/// is found, then try the expectation once more.
///
/// This combines `expect` with `skip_until` for the common pattern where
/// the grammar expects a specific delimiter but the user inserted garbage
/// before it.
///
/// Returns true if the expected token was eventually consumed (possibly
/// after skipping), false if recovery gave up (sync point reached or EOF
/// without finding the expected token).
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::expect_and_recover(
  self : ParserContext[T, K],
  expected : T,
  kind : K,
  is_sync : (T) -> Bool,
) -> Bool {
  if self.at(expected) {
    self.emit_token(kind)
    return true
  }
  // Record diagnostic before skipping
  let got = self.peek()
  self.error("expected " + expected.to_string() + ", got " + got.to_string())
  // Skip garbage
  let _ = self.skip_until(fn(t) { t == expected || is_sync(t) })
  // Try once more after recovery
  if self.at(expected) {
    self.emit_token(kind)
    true
  } else {
    self.emit_error_placeholder()
    false
  }
}
```

### Step 2: Append tests to `recovery_wbtest.mbt`

```moonbit
// ─── expect_and_recover ───────────────────────────────────────────────────────

///|
test "expect_and_recover: immediate match" {
  let src = "+ 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect_and_recover(TestTok::Plus, KPlus, fn(t) {
    match t {
      Num(_) => true
      _ => false
    }
  })
  inspect(ok, content="true")
  inspect(ctx.errors.length(), content="0")
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}

///|
test "expect_and_recover: skips garbage then finds expected" {
  // "1 + 2" — expect Plus, but Num(1) is first. Skip Num(1), find Plus.
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect_and_recover(TestTok::Plus, KPlus, fn(t) {
    match t {
      Num(2) => true // Num(2) is also a sync point
      _ => false
    }
  })
  inspect(ok, content="true") // found Plus after skipping Num(1)
  inspect(ctx.errors.length(), content="1") // diagnostic recorded
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}

///|
test "expect_and_recover: gives up when expected not found" {
  // "1 2" — expect Plus, skip Num(1), reach Num(2) = sync. Plus not found.
  let src = "1 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect_and_recover(TestTok::Plus, KPlus, fn(t) {
    match t {
      Num(2) => true
      _ => false
    }
  })
  inspect(ok, content="false") // gave up
  inspect(ctx.errors.length(), content="1")
  // Num(2) is still available (sync point not consumed)
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}
```

### Step 3: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass (3 new + previous).

---

## Task 6: Update interfaces, format, and verify full suite

### Step 1: Run full test suite

```bash
cd loom && moon test
```

Expected: all loom tests pass (core + incremental + pipeline).

### Step 2: Update interfaces and format

```bash
cd loom && moon info && moon fmt
```

### Step 3: Verify interface diff

```bash
cd loom && git diff src/core/pkg.generated.mbti
```

Expected: five new method signatures added to `ParserContext`:

```
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::expect(Self[T, K], T, K) -> Bool
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until(Self[T, K], (T) -> Bool) -> Int
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until_balanced(Self[T, K], (T) -> Bool, (T) -> Bool) -> Int
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::node_with_recovery(Self[T, K], K, () -> Bool, (T) -> Bool) -> Unit
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::expect_and_recover(Self[T, K], T, K, (T) -> Bool) -> Bool
```

No existing signatures changed. No other files modified.

### Step 4: Run examples to verify no regressions

```bash
cd loom/examples/lambda && moon test
```

Expected: all lambda example tests pass (count unchanged).

### Step 5: Commit

```bash
cd loom && git add src/core/recovery.mbt src/core/recovery_wbtest.mbt src/core/pkg.generated.mbti
git commit -m "feat(core): add error recovery combinators — expect, skip_until, skip_until_balanced, node_with_recovery, expect_and_recover"
```

---

## Verification checklist

```bash
cd loom && moon test                      # all loom tests pass
cd loom && moon check                     # no warnings
cd loom/examples/lambda && moon test      # lambda tests unchanged
cd loom && git diff src/core/pkg.generated.mbti  # only additions
```

---

## Design notes for the coding agent

### Why `T : Show` on `expect` and `expect_and_recover`

The `Show` constraint enables auto-generated diagnostic messages like `"expected Num(1), got Plus"`. Grammar authors never write error strings for simple token mismatches. The other three combinators (`skip_until`, `skip_until_balanced`, `node_with_recovery`) do NOT require `Show` — they operate on closures and leave diagnostic recording to the caller.

### Error node wrapping in `skip_until`

Skipped tokens are wrapped in `start_node(self.spec.error_kind)` ... `finish_node()`. This creates ONE error node containing multiple error tokens, rather than N individual error tokens. The wrapping is conditional — if no tokens are skipped (already at sync point or EOF), no node is emitted (avoids empty error nodes in the CST).

### `node_with_recovery` reuse fast-path

The combinator calls `try_reuse` directly (not via `node()`) because `node()` uses a closure for the body. `node_with_recovery` needs a different closure signature (`() -> Bool` instead of `() -> Unit`) to signal success/failure. The reuse fast-path is identical to `node()`: if `try_reuse` returns `Some`, `emit_reused` is called and both `body` and `is_sync` closures are never invoked.

### `expect_and_recover` skip target

The `skip_until` inside `expect_and_recover` stops at EITHER the expected token OR a sync point: `fn(t) { t == expected || is_sync(t) }`. This ensures recovery doesn't skip past the token it's looking for. After skipping, one more `at(expected)` check determines success or failure.

### `skip_until_balanced` does not consume the close token

The closing bracket is left for the caller to consume. This matches the common pattern where `parse_paren_expr` calls `skip_until_balanced`, then `expect(RParen, ...)` to consume the close with proper diagnostic if missing.
