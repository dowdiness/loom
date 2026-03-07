# Introduce Incomplete Nodes — Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Distinguish "unexpected token consumed" (`error_kind`) from "input ended before the grammar expected" (`incomplete_kind`) in loom's parser infrastructure. This enables IDE consumers to show different UX for "syntax error" vs "user is still typing".

**Architecture:** Add an `incomplete_kind : K` field to `LanguageSpec`, add `emit_incomplete_placeholder()` to `ParserContext`, update recovery combinators (`expect`, `expect_and_recover`) to emit incomplete placeholders at EOF, and update `ReuseCursor` internals to treat incomplete tokens/nodes as synthetic (same exclusion rules as error tokens). No changes to `seam/` — `RawKind` is already opaque and `CstNode::has_errors` already accepts arbitrary kind parameters.

**Tech Stack:** MoonBit, `moon` build system. All `moon` commands run from `loom/`.

**Backward compatibility:** `LanguageSpec::new` accepts `incomplete_kind` as an optional parameter defaulting to `error_kind`. Existing callers that don't pass it get the current behavior (incomplete = error). Struct literal usages (tests, internal specs) must add the new field explicitly.

---

## Background

Read before starting:
- `loom/src/core/parser.mbt` — `LanguageSpec` struct, `ParserContext` methods (`emit_error_placeholder`, `emit_zero_width`)
- `loom/src/core/recovery.mbt` — `expect`, `expect_and_recover` (both call `emit_error_placeholder`)
- `loom/src/core/reuse_cursor.mbt` — `collect_old_tokens`, `collect_reused_error_spans`, `next_sibling_has_error` (all reference `spec.error_kind`)
- `loom/src/core/parser_wbtest.mbt` — `TestKind` enum, `test_spec`, `make_test_fixtures` (struct literal usages that must add the new field)

**Key conventions:**
- Tests live in `*_wbtest.mbt` files (whitebox — same package, access private symbols)
- Test assertions use `inspect(expr, content="expected_string")`
- Run tests: `cd loom && moon test -p dowdiness/loom/core`
- Run all: `cd loom && moon test`

**The semantic distinction:**

| Kind | Meaning | When emitted | IDE UX |
|------|---------|-------------|--------|
| `error_kind` | Unexpected token consumed or missing token mid-input | `bump_error()`, `skip_until()`, `expect()` when NOT at EOF | Red squiggly, "syntax error" |
| `incomplete_kind` | Input ended before grammar finished | `expect()` at EOF, `expect_and_recover()` final fallback at EOF | Grey/dimmed indicator, "waiting for more input" |

---

## Task 1: Add `incomplete_kind` to `LanguageSpec`

**Files:**
- Modify: `loom/src/core/parser.mbt` (struct definition + `new` constructor)

### Step 1: Add the field to the struct

In `loom/src/core/parser.mbt`, find the `LanguageSpec` struct definition and add `incomplete_kind`:

```moonbit
pub struct LanguageSpec[T, K] {
  whitespace_kind : K
  error_kind : K
  incomplete_kind : K  // NEW: kind for "input ended early" placeholders
  root_kind : K
  eof_token : T
  cst_token_matches : (@seam.RawKind, String, T) -> Bool
  parse_root : (ParserContext[T, K]) -> Unit
}
```

### Step 2: Update `LanguageSpec::new` with optional parameter

Find the `LanguageSpec::new` function. Add `incomplete_kind` as an optional parameter that defaults to `error_kind`:

```moonbit
pub fn[T, K] LanguageSpec::new(
  whitespace_kind : K,
  error_kind : K,
  root_kind : K,
  eof_token : T,
  incomplete_kind? : K = error_kind,  // defaults to error_kind for backward compat
  cst_token_matches? : (@seam.RawKind, String, T) -> Bool = fn(_, _, _) { false },
  parse_root? : (ParserContext[T, K]) -> Unit = _ => (),
) -> LanguageSpec[T, K] {
  {
    whitespace_kind,
    error_kind,
    incomplete_kind,
    root_kind,
    eof_token,
    cst_token_matches,
    parse_root,
  }
}
```

### Step 3: Fix all struct literal usages in tests

Search `loom/src/core/parser_wbtest.mbt` for struct literal constructions of `LanguageSpec`. Each must add `incomplete_kind`. There are at least two:

1. `make_test_fixtures()` — add `incomplete_kind: KErr,` (same as error_kind for test fixture)
2. `test_spec` — add `incomplete_kind: KErr,`
3. The `LanguageSpec::new` call in the `cst_token_matches` test — this uses `new()` so it's already backward-compatible, but verify.

Also search `loom/src/factories.mbt` and `loom/src/grammar.mbt` — these use `spec` from Grammar, not struct literals, so no changes needed.

### Step 4: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all existing tests pass. The new field is set to `KErr` everywhere, so behavior is identical.

---

## Task 2: Add `emit_incomplete_placeholder` to `ParserContext`

**Files:**
- Modify: `loom/src/core/parser.mbt` (after `emit_error_placeholder`)
- Test: `loom/src/core/recovery_wbtest.mbt` (append)

### Step 1: Add the method

In `loom/src/core/parser.mbt`, after the `emit_error_placeholder` method, add:

```moonbit
///|
/// Emit a zero-width incomplete placeholder (no source text consumed).
/// Use this when the grammar expects more input but has reached EOF.
/// Distinct from emit_error_placeholder: signals "incomplete input" rather
/// than "unexpected token", enabling IDE consumers to show different UX
/// (e.g. grey indicator vs red squiggly).
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_incomplete_placeholder(
  self : ParserContext[T, K],
) -> Unit {
  self.emit_zero_width(self.spec.incomplete_kind)
}
```

### Step 2: Add a test to verify distinct kinds

Append to `loom/src/core/recovery_wbtest.mbt`:

First, add a new `KIncomplete` variant to `TestKind` in `parser_wbtest.mbt`:

In `loom/src/core/parser_wbtest.mbt`, find the `TestKind` enum:

```moonbit
enum TestKind {
  KNum
  KPlus
  KExpr
  KRoot
  KWs
  KErr
  KIncomplete  // NEW
} derive(Show)
```

Update `test_kind_raw` to map the new variant:

```moonbit
fn test_kind_raw(k : TestKind) -> @seam.RawKind {
  let n = match k {
    KNum => 0
    KPlus => 1
    KExpr => 2
    KRoot => 3
    KWs => 4
    KErr => 5
    KIncomplete => 6  // NEW
  }
  @seam.RawKind(n)
}
```

Update `test_spec` to use distinct incomplete_kind:

```moonbit
let test_spec : LanguageSpec[TestTok, TestKind] = {
  whitespace_kind: KWs,
  error_kind: KErr,
  incomplete_kind: KIncomplete,  // NEW: distinct from KErr
  root_kind: KRoot,
  eof_token: TestTok::TokEof,
  cst_token_matches: fn(raw, text, tok) {
    if raw != test_kind_raw(KNum) {
      return false
    }
    match tok {
      Num(n) => n.to_string() == text
      _ => false
    }
  },
  parse_root: fn(_) { () },
}
```

Also update `make_test_fixtures()` similarly — add `incomplete_kind: KErr,` (this fixture doesn't need a distinct kind).

Now add the test in `recovery_wbtest.mbt`:

```moonbit
///|
test "emit_incomplete_placeholder: emits incomplete_kind, not error_kind" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_incomplete_placeholder()
  ctx.finish_node()
  // Build tree and check the placeholder token kind
  let tree = ctx.events.build_tree(test_kind_raw(KRoot))
  // The root should have one child: a zero-width token with KIncomplete kind
  inspect(tree.children.length(), content="1")
  match tree.children[0] {
    @seam.CstElement::Token(t) => {
      inspect(t.kind == test_kind_raw(KIncomplete), content="true")
      inspect(t.kind == test_kind_raw(KErr), content="false")
      inspect(t.text_len(), content="0")
    }
    _ => inspect("expected token", content="token")
  }
}
```

### Step 3: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass including the new test.

---

## Task 3: Update `expect` to emit incomplete at EOF

**Files:**
- Modify: `loom/src/core/recovery.mbt` (modify `expect`)
- Test: `loom/src/core/recovery_wbtest.mbt` (modify existing + add new)

### Step 1: Modify `expect`

In `loom/src/core/recovery.mbt`, find the `expect` function and change the error branch to distinguish EOF from non-EOF:

```moonbit
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
    if self.at_eof() {
      self.emit_incomplete_placeholder()
    } else {
      self.emit_error_placeholder()
    }
    false
  }
}
```

### Step 2: Update the existing EOF test

Find the test `"expect: at EOF emits placeholder with eof in message"` in `recovery_wbtest.mbt`. It currently only checks the diagnostic message. Add a check that the placeholder uses `KIncomplete`:

```moonbit
///|
test "expect: at EOF emits incomplete placeholder (not error)" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  ctx.finish_node()
  inspect(ok, content="false")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message.contains("TokEof"), content="true")
  // Verify the placeholder is incomplete_kind, not error_kind
  let tree = ctx.events.build_tree(test_kind_raw(KRoot))
  // Find the zero-width placeholder among children
  let has_incomplete = tree.children.iter().any(fn(c) {
    match c {
      @seam.CstElement::Token(t) => t.kind == test_kind_raw(KIncomplete) && t.text_len() == 0
      _ => false
    }
  })
  inspect(has_incomplete, content="true")
}
```

### Step 3: Add test for non-EOF mismatch still using error_kind

```moonbit
///|
test "expect: non-EOF mismatch emits error placeholder (not incomplete)" {
  let src = "+ 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  ctx.finish_node()
  inspect(ok, content="false")
  // Verify the placeholder is error_kind, not incomplete_kind
  let tree = ctx.events.build_tree(test_kind_raw(KRoot))
  let has_error = tree.children.iter().any(fn(c) {
    match c {
      @seam.CstElement::Token(t) => t.kind == test_kind_raw(KErr) && t.text_len() == 0
      _ => false
    }
  })
  inspect(has_error, content="true")
}
```

### Step 4: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass. The old `"expect: emits placeholder and diagnostic on mismatch"` test should still pass because it tests the non-EOF path which still uses error_kind.

---

## Task 4: Update `expect_and_recover` to emit incomplete at EOF

**Files:**
- Modify: `loom/src/core/recovery.mbt` (modify `expect_and_recover`)
- Test: `loom/src/core/recovery_wbtest.mbt` (add new test)

### Step 1: Modify `expect_and_recover`

In `loom/src/core/recovery.mbt`, find the `expect_and_recover` function. The final fallback (after skipping didn't find the expected token) should emit incomplete at EOF:

```moonbit
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
  let _ = self.skip_until(t => t == expected || is_sync(t))
  // Try once more after recovery
  if self.at(expected) {
    self.emit_token(kind)
    true
  } else {
    // Final fallback: distinguish EOF from mid-input failure
    if self.at_eof() {
      self.emit_incomplete_placeholder()
    } else {
      self.emit_error_placeholder()
    }
    false
  }
}
```

### Step 2: Add test

```moonbit
///|
test "expect_and_recover: EOF fallback emits incomplete placeholder" {
  // "1" — expect Plus, skip Num(1), reach EOF. Plus not found.
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect_and_recover(TestTok::Plus, KPlus, _t => false)
  ctx.finish_node()
  inspect(ok, content="false")
  // Verify incomplete_kind was used (not error_kind)
  let tree = ctx.events.build_tree(test_kind_raw(KRoot))
  let has_incomplete = tree.children.iter().any(fn(c) {
    match c {
      @seam.CstElement::Token(t) => t.kind == test_kind_raw(KIncomplete) && t.text_len() == 0
      _ => false
    }
  })
  inspect(has_incomplete, content="true")
}
```

### Step 3: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass.

---

## Task 5: Update `ReuseCursor` to handle `incomplete_kind`

**Files:**
- Modify: `loom/src/core/reuse_cursor.mbt` (three functions)

The `ReuseCursor` treats error tokens as synthetic — excluding them from the old-token list, collecting their spans for diagnostic replay, and checking for error content in siblings. Incomplete tokens must receive the same treatment.

### Step 1: Update `collect_old_tokens`

Find the function in `reuse_cursor.mbt`. It currently excludes tokens where `kind == ws_raw || kind == err_raw`. Add incomplete exclusion:

```moonbit
fn collect_old_tokens(
  node : @seam.CstNode,
  node_start : Int,
  out : Array[OldToken],
  ws_raw : @seam.RawKind,
  err_raw : @seam.RawKind,
  incomplete_raw : @seam.RawKind,  // NEW parameter
) -> Unit {
  let mut offset = node_start
  for child in node.children {
    match child {
      @seam.CstElement::Token(t) => {
        if t.kind != ws_raw && t.kind != err_raw && t.kind != incomplete_raw {
          out.push({ kind: t.kind, text: t.text, start: offset })
        }
        offset = offset + t.text_len()
      }
      @seam.CstElement::Node(n) => {
        collect_old_tokens(n, offset, out, ws_raw, err_raw, incomplete_raw)
        offset = offset + n.text_len
      }
    }
  }
}
```

### Step 2: Update the `ReuseCursor::new` call to `collect_old_tokens`

In `ReuseCursor::new`, find the call to `collect_old_tokens` and pass the new parameter:

```moonbit
  if not(reuse_globally_disabled) {
    let ws_raw = spec.whitespace_kind.to_raw()
    let err_raw = spec.error_kind.to_raw()
    let incomplete_raw = spec.incomplete_kind.to_raw()
    collect_old_tokens(old_tree, 0, old_tokens, ws_raw, err_raw, incomplete_raw)
  }
```

### Step 3: Update `collect_reused_error_spans` in `parser.mbt`

Find `collect_reused_error_spans` in `parser.mbt`. It currently checks `t.kind == error_raw` and `n.kind == error_raw`. It must also check for `incomplete_raw`:

```moonbit
fn[T, K : @seam.ToRawKind] collect_reused_error_spans(
  node : @seam.CstNode,
  node_start : Int,
  spec : LanguageSpec[T, K],
  out : Array[ReusedErrorSpan],
) -> Int {
  let error_raw = spec.error_kind.to_raw()
  let incomplete_raw = spec.incomplete_kind.to_raw()
  let mut offset = node_start
  let mut added = 0
  for child in node.children {
    match child {
      @seam.CstElement::Token(t) => {
        let end = offset + t.text_len()
        if t.kind == error_raw || t.kind == incomplete_raw {
          out.push({ start: offset, end })
          added = added + 1
        }
        offset = end
      }
      @seam.CstElement::Node(n) => {
        let child_added = collect_reused_error_spans(n, offset, spec, out)
        if child_added == 0 && (n.kind == error_raw || n.kind == incomplete_raw) {
          out.push({ start: offset, end: offset + n.text_len })
          added = added + 1
        } else {
          added = added + child_added
        }
        offset = offset + n.text_len
      }
    }
  }
  added
}
```

### Step 4: Update `next_sibling_has_error`

Find `next_sibling_has_error` in `reuse_cursor.mbt`. It checks for `err_raw` in the next sibling. Add incomplete check:

```moonbit
pub fn[T, K : @seam.ToRawKind] ReuseCursor::next_sibling_has_error(
  self : ReuseCursor[T, K],
) -> Bool {
  if self.stack.length() == 0 {
    return false
  }
  let frame = self.stack[self.stack.length() - 1]
  let next_idx = frame.child_index + 1
  if next_idx >= frame.node.children.length() {
    return false
  }
  let err_raw = self.spec.error_kind.to_raw()
  let incomplete_raw = self.spec.incomplete_kind.to_raw()
  match frame.node.children[next_idx] {
    @seam.CstElement::Node(n) =>
      // has_errors(node_kind, token_kind): check both error and incomplete
      // as either node kind or token kind in a single pass per call.
      n.has_errors(err_raw, err_raw) || n.has_errors(err_raw, incomplete_raw)
    @seam.CstElement::Token(t) =>
      t.kind == err_raw || t.kind == incomplete_raw
  }
}
```

### Step 5: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass. Existing reuse tests use `KErr` for both `error_kind` and `incomplete_kind` (since `make_test_fixtures` sets both to `KErr`), so behavior is unchanged.

---

## Task 6: Add reuse tests with distinct incomplete_kind

**Files:**
- Modify: `loom/src/core/parser_wbtest.mbt` (append)

These tests verify that `ReuseCursor` correctly handles incomplete placeholders during incremental reuse.

### Step 1: Add test — reuse replays diagnostics for incomplete subtree

```moonbit
///|
test "ParserContext reuse: replays diagnostics for incomplete subtree at EOF" {
  fn grammar_incomplete_at_eof(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      // Simulate expect() at EOF: diagnostic + incomplete placeholder
      ctx.error("expected Plus, got TokEof")
      ctx.emit_incomplete_placeholder()
    })
  }

  let src = "1"
  let toks = test_tokenize(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_incomplete_at_eof,
  )
  inspect(old_errors.length(), content="1")

  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,  // no damage — force reuse
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  grammar_incomplete_at_eof(ctx)
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message, content="expected Plus, got TokEof")
}
```

### Step 2: Add test — incomplete placeholder does not block subsequent reuse

```moonbit
///|
test "ParserContext reuse: incomplete node followed by reusable sibling" {
  fn grammar_two_nodes_incomplete(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_incomplete_placeholder()
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ()
      }
    })
  }

  let src = "1 2"
  let toks = test_tokenize(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_two_nodes_incomplete,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  // First node has incomplete → reused
  ctx.node(KExpr, fn() {
    ctx.emit_token(KNum)
    ctx.emit_incomplete_placeholder()
  })
  inspect(ctx.reuse_count, content="1")
  // Second node → also reused
  ctx.node(KExpr, fn() {
    match ctx.peek() {
      Num(_) => ctx.emit_token(KNum)
      _ => ()
    }
  })
  inspect(ctx.reuse_count, content="2")
}
```

### Step 3: Run tests

```bash
cd loom && moon test -p dowdiness/loom/core
```

Expected: all pass.

---

## Task 7: Update interfaces, verify full suite, commit

### Step 1: Run full test suite

```bash
cd loom && moon test
```

Expected: all tests pass (core + incremental + pipeline). If `examples/lambda` exists and uses struct literal `LanguageSpec`, it needs `incomplete_kind` added — but lambda example likely uses `Grammar::new` which goes through `LanguageSpec::new`, so it should be backward-compatible. Verify.

### Step 2: Format and check

```bash
cd loom && moon fmt && moon check
```

### Step 3: Update interfaces

```bash
cd loom && moon info
```

Check the diff:

```bash
cd loom && git diff src/core/pkg.generated.mbti
```

Expected changes:
- `LanguageSpec` struct gains `incomplete_kind : K` field
- `ParserContext::emit_incomplete_placeholder` added

### Step 4: Run lambda example tests

```bash
cd examples/lambda && moon test
```

If this fails because lambda's `LanguageSpec` is constructed via struct literal, add `incomplete_kind` to the lambda SyntaxKind enum and the spec. If it uses `LanguageSpec::new`, it should work without changes (the default kicks in).

### Step 5: Commit

```bash
cd loom && git add -A
git commit -m "feat(core): introduce incomplete_kind — distinguish EOF-incomplete from syntax errors

LanguageSpec gains incomplete_kind field (optional, defaults to error_kind).
ParserContext::emit_incomplete_placeholder() emits the new kind.
expect() and expect_and_recover() emit incomplete at EOF, error otherwise.
ReuseCursor treats incomplete tokens as synthetic (same as error tokens)."
```

---

## Verification checklist

```bash
cd loom && moon test                          # all loom tests pass
cd loom && moon check                         # no warnings
cd examples/lambda && moon test               # lambda tests pass
cd loom && git diff src/core/pkg.generated.mbti  # expected additions only
```

---

## Design notes for the coding agent

### Backward compatibility via optional parameter

`LanguageSpec::new` uses `incomplete_kind? : K = error_kind` so callers that don't pass it get `incomplete_kind == error_kind`. This means all existing behavior is preserved. Only callers that explicitly set a distinct `incomplete_kind` see the new behavior.

However, struct literal usages like `{ whitespace_kind: ..., error_kind: ..., ... }` will fail to compile because the new field is missing. All such usages must be updated. Search for `LanguageSpec[` followed by `{` to find them.

### `skip_until` does NOT change

`skip_until` wraps consumed tokens in `error_kind` nodes. This is correct — skipped tokens are genuinely unexpected, not incomplete. The incomplete distinction only applies to zero-width placeholders emitted when the grammar expects more input.

### `node_with_recovery` does NOT change

It delegates to `skip_until` internally. The body's `false` return signals failure, and `skip_until` handles the recovery. No incomplete logic needed here.

### Three functions in ReuseCursor need the incomplete_raw check

1. `collect_old_tokens` — exclude incomplete tokens from the old-token list (they're synthetic, not real source tokens). Without this, trailing-context matching would compare against a synthetic token and produce false negatives.

2. `collect_reused_error_spans` — include incomplete spans in the error-span collection. Without this, incomplete diagnostics from reused subtrees wouldn't be replayed.

3. `next_sibling_has_error` — recognize incomplete content as "error-bearing". Without this, EOF boundary diagnostic attribution would misassign incomplete diagnostics.

### seam does not change

`CstNode::has_errors(error_node_kind, error_token_kind)` already takes kind parameters. IDE consumers can call it with either `error_kind` or `incomplete_kind` as needed. No new seam API is required.

### TestKind addition

Adding `KIncomplete` to `TestKind` with `RawKind(6)` is the minimal change. The existing `KErr` = `RawKind(5)` is unchanged. `test_spec` is updated to use `KIncomplete` as a distinct `incomplete_kind`, which enables tests to verify the correct kind is emitted.

`make_test_fixtures()` can keep `incomplete_kind: KErr` since those tests don't test the incomplete distinction — they test basic ParserContext mechanics.

### Lambda example impact

If the lambda example constructs `LanguageSpec` via `Grammar::new` → `LanguageSpec::new`, backward compatibility handles it (incomplete defaults to error). If it uses a struct literal, a `KIncomplete` variant must be added to the lambda `SyntaxKind` enum. Check both paths.
