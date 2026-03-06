# loom Ambiguity Resilience — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan phase-by-phase.

**Goal:** Make loom handle all ambiguous and malformed input without crashing, losing partial results, or entering infinite loops. Six concrete defects are addressed across three phases, ordered by blast radius (process crash → data loss → correctness).

**Architecture:** Changes are primarily in `loom/`, with a small addition to `seam/` (Phase 3.2 adds `EventBuffer::length` and `EventBuffer::truncate`). No changes to `incr/`. Each phase is independently shippable; later phases may depend on earlier ones where noted.

**Tech Stack:** MoonBit, `moon` build system. All `moon` commands run from `loom/`.

---

## Background

Read before starting:

- `seam/docs/design.md` — Three-layer API model: total functions (never panic), checked functions (Option), error information
- `loom/src/core/parser.mbt` — `ParserContext` implementation (emit_token, finish_node, flush_trivia, recovery combinators)
- `loom/src/core/recovery.mbt` — Error recovery combinators (expect, skip_until, skip_until_balanced, node_with_recovery, expect_and_recover)
- `loom/src/core/token_buffer.mbt` — Incremental token buffer
- `loom/src/core/reuse_cursor.mbt` — Incremental reuse cursor
- `loom/src/incremental/damage.mbt` — Damage tracking
- `loom/src/factories.mbt` — Parser factory functions (new_imperative_parser, new_reactive_parser)

**Key conventions:**

- Tests live in `*_wbtest.mbt` (whitebox — same package, access private symbols) or `*_test.mbt` (blackbox)
- Test assertions use `inspect(expr, content="expected_string")`
- Run tests: `cd loom && moon test`
- Run single package: `cd loom && moon test -p dowdiness/loom/core`
- Avoid suppressing MoonBit warnings; fix them structurally

---

## Phase 1 — Eliminate Process Crashes (Highest Priority)

### Defect 1.1: `emit_token` aborts on EOF

**Problem:** `ParserContext::emit_token` calls `abort()` when `at_eof()` is true. A grammar author's bug (or an error-recovery path that over-consumes) kills the entire process. This directly violates seam's "never panic on well-typed input" principle.

**File:** `loom/src/core/parser.mbt`

**Current code (around line 271):**

```moonbit
pub fn ParserContext::emit_token(self, kind) -> Unit {
  if self.at_eof() {
    abort("emit_token: called at EOF — grammar tried to consume past end of input")
  }
  self.flush_trivia()
  let text = self.text_at(self.position)
  self.events.push(@seam.ParseEvent::Token(kind.to_raw(), text))
  self.position = self.position + 1
}
```

**Fix:** Replace `abort` with a diagnostic + zero-width error token emission. The grammar continues with a well-formed CST.

```moonbit
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::emit_token(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  if self.at_eof() {
    // Record diagnostic instead of crashing.
    self.error("emit_token: unexpected EOF")
    self.events.push(@seam.ParseEvent::Token(kind.to_raw(), ""))
    return
  }
  self.flush_trivia()
  let text = self.text_at(self.position)
  self.events.push(@seam.ParseEvent::Token(kind.to_raw(), text))
  self.position = self.position + 1
}
```

**Tests to add** (append to `loom/src/core/parser_wbtest.mbt`):

```moonbit
///|
test "emit_token: at EOF emits zero-width token and diagnostic instead of abort" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  // This must not abort
  ctx.emit_token(KNum)
  ctx.finish_node()
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message.contains("EOF"), content="true")
}

///|
test "emit_token: at EOF after consuming all tokens emits diagnostic" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum) // consume "1"
  // Now at EOF — must not abort
  ctx.emit_token(KPlus)
  ctx.finish_node()
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.at_eof(), content="true")
}
```

**Verification:**

```bash
cd loom && moon test -p dowdiness/loom/core
```

All existing tests must continue to pass. The two `panic` tests for `emit_token` in existing test files (if any) should be removed or converted to non-panic expectations.

---

### Defect 1.2: `finish_node` aborts on underflow

**Problem:** `ParserContext::finish_node` aborts when `open_nodes <= 0`. Same blast radius as 1.1.

**File:** `loom/src/core/parser.mbt`

**Current code (around line 285):**

```moonbit
pub fn ParserContext::finish_node(self) -> Unit {
  if self.open_nodes <= 0 {
    abort("finish_node: no matching start_node")
  }
  self.open_nodes = self.open_nodes - 1
  self.events.push(@seam.FinishNode)
}
```

**Fix:** Silently ignore the unbalanced `finish_node`. No diagnostic is recorded because this is a grammar-author bug (node balancing error), not a user-facing parse error — diagnostics should reflect source-level issues, not internal invariant violations.

```moonbit
pub fn[T, K] ParserContext::finish_node(self : ParserContext[T, K]) -> Unit {
  if self.open_nodes <= 0 {
    // Silently ignore rather than crashing. No diagnostic — this is a
    // grammar bug, not a source-level error.
    return
  }
  self.open_nodes = self.open_nodes - 1
  self.events.push(@seam.FinishNode)
}
```

**Tests to add** (append to `loom/src/core/parser_wbtest.mbt`):

```moonbit
///|
test "finish_node: unbalanced close does not abort" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  // No start_node — finish_node must not abort
  ctx.finish_node()
  inspect(ctx.open_nodes, content="0")
}

///|
test "finish_node: double close does not abort" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  ctx.finish_node()
  // Extra finish_node — must not abort
  ctx.finish_node()
  inspect(ctx.open_nodes, content="0")
}
```

**Verification:**

```bash
cd loom && moon test -p dowdiness/loom/core
```

---

### Defect 1.3: `parse_with` and `parse_tokens_indexed` abort on unbalanced nodes

**Problem:** After the grammar returns, both `parse_with` and `parse_tokens_indexed` call `abort()` if `open_nodes != 0`. This is the third abort path reachable from grammar bugs.

**File:** `loom/src/core/parser.mbt`

**Current code (parse_with, around line 427):**

```moonbit
  if ctx.open_nodes != 0 {
    abort(
      "parse_with: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
```

**Current code (parse_tokens_indexed, around line 474):**

```moonbit
  if ctx.open_nodes != 0 {
    abort(
      "parse_tokens_indexed: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
```

**Fix:** Auto-close remaining open nodes instead of aborting. Push a diagnostic per unclosed node, then emit `FinishNode` events to balance the tree.

```moonbit
  // In parse_with, replace the abort block:
  while ctx.open_nodes > 0 {
    ctx.error("unclosed node (auto-closed)")
    ctx.open_nodes = ctx.open_nodes - 1
    ctx.events.push(@seam.FinishNode)
  }
```

Apply the same pattern in `parse_tokens_indexed`.

**Tests to add** (append to `loom/src/core/parser_wbtest.mbt`):

```moonbit
///|
test "parse_with: unclosed node is auto-closed with diagnostic" {
  let (tree, errors) = parse_with("1", test_spec, test_tokenize, fn(ctx) {
    ctx.start_node(KExpr)
    ctx.emit_token(KNum)
    // Deliberately omit finish_node
  })
  // Must not abort — tree should be valid
  inspect(tree.text_len, content="1")
  // At least one diagnostic about unclosed node
  let has_unclosed = errors.iter().any(fn(e) {
    e.message.contains("unclosed")
  })
  inspect(has_unclosed, content="true")
}
```

**Verification:**

```bash
cd loom && moon test -p dowdiness/loom/core
```

---

## Phase 2 — Eliminate Data Loss

### Defect 2.1: LexError is all-or-nothing

**Problem:** `TokenBuffer::new` and `TokenBuffer::update` raise `LexError`, and `factories.mbt` converts this to `ParseOutcome::LexError` which discards the entire CST. A single unrecognizable byte anywhere in the source means no syntax tree at all.

**Files:**
- `loom/src/core/token_buffer.mbt`
- `loom/src/factories.mbt`

**Current behavior chain:**

1. `tokenize_fn(source)` raises `LexError("bad char at pos 42")`
2. `TokenBuffer::new` propagates the raise
3. `factories.mbt` catches it → `ParseOutcome::LexError(msg)`
4. `ImperativeParser` returns `on_lex_error(msg)` → no CST, no partial results

**Fix — Two-level approach:**

**Level A: Add `TokenBuffer::new_resilient` constructor.**

This constructor wraps the tokenize_fn to catch errors per-segment rather than failing the entire lex. When a `LexError` occurs mid-stream, it inserts an error token for the problematic byte(s) and continues lexing from the next position.

Add to `loom/src/core/token_buffer.mbt`:

```moonbit
///|
/// Construct a TokenBuffer that never raises LexError.
/// On lex failure, inserts an error token covering the unrecognizable byte
/// and retries from the next position. The returned buffer always has a
/// complete token stream suitable for parsing.
///
/// `error_token` — the T value to use for error tokens (e.g. TokError)
/// `error_kind_raw` — not needed here; the grammar's error_kind handles CST classification
pub fn[T] TokenBuffer::new_resilient(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
  error_token~ : T,
) -> TokenBuffer[T] {
  let tokens = tokenize_resilient(source, tokenize_fn, eof_token, error_token)
  { tokenize_fn, eof_token, tokens, source, version: 0 }
}
```

Add the helper:

```moonbit
///|
/// Lex `source` resiliently: on LexError, insert an error token for one
/// code unit and retry from the next position.
///
/// Performance: O(n) when the initial full-lex succeeds (common case).
/// Falls back to O(n²) when the initial lex fails, because each retry
/// re-lexes from `pos` to end-of-source. This is acceptable because
/// LexError on well-formed source is rare, and partial-failure sources
/// are typically short (interactive editing).
fn[T] tokenize_resilient(
  source : String,
  tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token : T,
  error_token : T,
) -> Array[TokenInfo[T]] {
  try {
    tokenize_fn(source)
  } catch {
    LexError(_) => {
      // Fallback: lex character-by-character with error recovery
      let result : Array[TokenInfo[T]] = []
      let mut pos = 0
      while pos < source.length() {
        // Try to lex from current position to end
        let remaining = source[pos:source.length()] catch { _ => break }
        try {
          let sub_tokens = tokenize_fn(remaining.to_string())
          // Success — offset-adjust and append (skip trailing EOF)
          for i = 0; i < sub_tokens.length() - 1; i = i + 1 {
            let t = sub_tokens[i]
            result.push(TokenInfo::new(t.token, t.start + pos, t.end + pos))
          }
          // Done — all remaining source lexed successfully
          pos = source.length()
        } catch {
          LexError(_) => {
            // Insert error token for one code unit and advance
            result.push(TokenInfo::new(error_token, pos, pos + 1))
            pos = pos + 1
          }
        }
      }
      // Always append EOF sentinel
      result.push(TokenInfo::new(eof_token, source.length(), source.length()))
      result
    }
  }
}
```

**Level B: Update factories to use resilient lexing.**

In `loom/src/factories.mbt`, update `new_imperative_parser`'s `full_parse` closure to use `TokenBuffer::new_resilient` when available, falling back to the current behavior when the grammar doesn't provide an `error_token`.

This is a **non-breaking change** — the `Grammar` struct gains an optional `error_token` field:

In `loom/src/grammar.mbt`:

```moonbit
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  to_ast : (@seam.SyntaxNode) -> Ast
  on_lex_error : (String) -> Ast
  error_token : T?  // NEW (optional): when Some, enables resilient lexing
}
```

Update `Grammar::new` to accept the optional field:

```moonbit
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  tokenize~ : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
  error_token~ : T? = None,
) -> Grammar[T, K, Ast] {
  { spec, tokenize, to_ast, on_lex_error, error_token }
}
```

In `factories.mbt`, update the `full_parse` closure in `new_imperative_parser`:

```moonbit
  // Inside full_parse closure:
  let buffer = match grammar.error_token {
    Some(err_tok) =>
      @core.TokenBuffer::new_resilient(
        source,
        tokenize_fn=tokenize,
        eof_token=spec.eof_token,
        error_token=err_tok,
      )
    None =>
      try @core.TokenBuffer::new(
        source,
        tokenize_fn=tokenize,
        eof_token=spec.eof_token,
      ) catch {
        @core.LexError(msg) => {
          token_buf.val = None
          last_diags.val = []
          return @incremental.ParseOutcome::LexError(
            "Tokenization error: " + msg,
          )
        }
      }
  }
```

Apply the same pattern to the `incremental_parse` closure and `new_reactive_parser`.

**Tests to add** (new file `loom/src/core/token_buffer_resilient_wbtest.mbt`):

```moonbit
///|
fn bad_tokenizer(s : String) -> Array[TokenInfo[String]] raise LexError {
  if s.contains("@") {
    raise LexError("bad char @")
  }
  let result : Array[TokenInfo[String]] = []
  for i = 0; i < s.length(); i = i + 1 {
    result.push(TokenInfo::new("char", i, i + 1))
  }
  result.push(TokenInfo::new("EOF", s.length(), s.length()))
  result
}

///|
test "TokenBuffer::new_resilient: clean input produces normal tokens" {
  let buf = TokenBuffer::new_resilient(
    "abc",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
    error_token="ERR",
  )
  // 3 char tokens + 1 EOF = 4
  inspect(buf.get_tokens().length(), content="4")
}

///|
test "TokenBuffer::new_resilient: bad char produces error token and continues" {
  let buf = TokenBuffer::new_resilient(
    "a@b",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  // Should have: "a" at [0,1), ERR at [1,2), "b" at [2,3), EOF at [3,3)
  // The exact count depends on recovery behavior
  // Key invariant: we get tokens, not an exception
  inspect(tokens.length() > 0, content="true")
  // Last token is always EOF
  inspect(tokens[tokens.length() - 1].token, content="EOF")
  // There should be an error token somewhere
  let has_err = tokens.iter().any(fn(t) { t.token == "ERR" })
  inspect(has_err, content="true")
}
```

**Verification:**

```bash
cd loom && moon test -p dowdiness/loom/core
```

---

### Defect 2.2: Damage coordinate mismatch in `factories.mbt`

**Problem:** `factories.mbt` passes `edit.new_end()` (a **new-source** coordinate) as `damage_end` to `ReuseCursor::new`, which walks the **old tree**. When an insertion grows the source, damage_end in old coordinates should be `edit.old_end()`, not `edit.new_end()`. The mismatch can cause `is_outside_damage` to return `true` for nodes that actually overlap the edit, leading to incorrect node reuse.

**File:** `loom/src/factories.mbt`

**Current code (around line 56):**

```moonbit
      let damaged_range = @core.Range::new(edit.start, edit.new_end())
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          damaged_range.start,
          damaged_range.end,  // ← new_end() but cursor walks old tree
```

**Fix:** Use `edit.old_end()` for the damage range passed to `ReuseCursor`, since the cursor walks the old tree:

```moonbit
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          edit.start,
          edit.old_end(),     // ← old-source coordinate for old-tree cursor
          tokens.length(),
          fn(i) { tokens[i].token },
          fn(i) { tokens[i].start },
          spec,
        ),
      )
```

**Tests to add** (append to `loom/src/core/parser_wbtest.mbt`):

```moonbit
///|
test "ReuseCursor: insertion that grows source does not reuse damaged node" {
  // Regression test for coordinate mismatch.
  // Old: "12 34" → Edit: replace "12" (positions 0..2) with "12345" (grows by 3)
  // New: "12345 34"
  // The old node at offset 0 (covering "12") is inside damage [0,2) in old coords.
  // With the bug (using new_end=5), damage was [0,5) which is too wide
  // but happened to be correct by accident. The real risk is the reverse:
  // an edit that shrinks the source, where new_end < old_end could leave
  // damaged nodes outside the damage range.
  fn grammar_two_numbers(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected number")
      }
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected number")
      }
    })
  }

  let old_src = "12 34"
  // Shrink: replace "12" with "1" → new source "1 34"
  let new_src = "1 34"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_two_numbers,
  )
  let new_toks = test_tokenize(new_src)
  // old damage: [0, 2) — the "12" that was replaced
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,  // edit.start
    2,  // edit.old_end() — correct old-source coordinate
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_toks[i].start },
    test_spec,
  )
  // First node (old offset 0, covering "12") is inside damage → must NOT reuse
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is None, content="true")
}
```

**Integration test** (append to a new file `loom/src/factories_wbtest.mbt` or an existing integration test file — this tests the fix through `new_imperative_parser`):

The unit test above validates `ReuseCursor` directly with correct coordinates. An integration test through `new_imperative_parser` would exercise the full `factories.mbt` code path where the bug lives. However, constructing such a test requires a complete `Grammar` instance with tokenizer, AST conversion, and lex-error handler — which is language-specific. The lambda example's existing incremental tests in `examples/lambda/` implicitly cover this path. After applying the fix, verify that `examples/lambda` incremental tests still pass:

```bash
cd examples/lambda && moon test
```

**Verification:**

```bash
cd loom && moon test -p dowdiness/loom/core
cd loom && moon test
cd examples/lambda && moon test
```

---

## Phase 3 — Improve Parse Quality

### Defect 3.1: No multi-token lookahead

**Problem:** `peek()` returns only the next non-trivia token. Grammar authors cannot look 2+ tokens ahead without manually iterating `position`, which is error-prone and breaks encapsulation.

**File:** `loom/src/core/parser.mbt`

**Fix:** Add `peek_nth(n)` that returns the nth non-trivia token (0-indexed, so `peek_nth(0) == peek()`).

```moonbit
///|
/// Return the nth non-trivia token (0-indexed) without consuming it.
/// peek_nth(0) is equivalent to peek().
/// Returns eof_token when fewer than n+1 non-trivia tokens remain.
pub fn[T : @seam.IsTrivia, K] ParserContext::peek_nth(
  self : ParserContext[T, K],
  n : Int,
) -> T {
  let mut pos = self.position
  let mut count = 0
  while pos < self.token_count {
    let t = (self.get_token)(pos)
    if t.is_trivia() {
      pos = pos + 1
    } else {
      if count == n {
        return t
      }
      count = count + 1
      pos = pos + 1
    }
  }
  self.spec.eof_token
}
```

**Tests to add** (append to `loom/src/core/parser_wbtest.mbt`):

```moonbit
///|
test "peek_nth: 0 equals peek" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(0) == ctx.peek(), content="true")
}

///|
test "peek_nth: returns second non-trivia token" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(0), content="Num(1)")
  inspect(ctx.peek_nth(1), content="Plus")
  inspect(ctx.peek_nth(2), content="Num(2)")
}

///|
test "peek_nth: past end returns eof" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(5), content="TokEof")
}

///|
test "peek_nth: skips trivia between tokens" {
  let src = "1   +   2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(0), content="Num(1)")
  inspect(ctx.peek_nth(1), content="Plus")
  inspect(ctx.peek_nth(2), content="Num(2)")
}
```

**Verification:**

```bash
cd loom && moon test -p dowdiness/loom/core
```

---

### Defect 3.2: No speculative parse / checkpoint-restore

**Problem:** Grammar authors cannot try multiple parse paths and choose the one that succeeds. Ambiguous constructs (e.g., `a < b` as comparison vs generic) require backtracking.

**File:** `loom/src/core/parser.mbt`

**Fix:** Add checkpoint/restore API. A checkpoint captures the parser state; restore rewinds to it.

```moonbit
///|
/// Opaque snapshot of parser state for speculative parsing.
/// Create with checkpoint(), restore with restore().
pub(all) struct Checkpoint {
  priv position : Int
  priv events_len : Int
  priv error_count : Int
  priv open_nodes : Int
}
```

```moonbit
///|
/// Save the current parse state. The returned checkpoint can be passed
/// to restore() to rewind the parser to this exact point.
///
/// Events emitted after the checkpoint are discarded on restore.
/// Tokens consumed after the checkpoint are "unconsumed" on restore.
///
/// Checkpoints do not nest implicitly — the most recent checkpoint
/// wins. Multiple checkpoints can coexist; restore any of them.
pub fn[T, K] ParserContext::checkpoint(
  self : ParserContext[T, K],
) -> Checkpoint {
  {
    position: self.position,
    events_len: self.events.length(),
    error_count: self.error_count,
    open_nodes: self.open_nodes,
  }
}

///|
/// Rewind the parser to a previously saved checkpoint.
///
/// - Resets position to the checkpoint's position (tokens are re-readable)
/// - Truncates the event buffer to the checkpoint's length
/// - Removes diagnostics added after the checkpoint
/// - Restores the open_nodes counter
///
/// The reuse cursor is NOT rewound — reuse opportunities for nodes
/// consumed between checkpoint and restore are lost. This is acceptable
/// because speculative paths are typically short (a few tokens).
pub fn[T, K] ParserContext::restore(
  self : ParserContext[T, K],
  cp : Checkpoint,
) -> Unit {
  self.position = cp.position
  self.events.truncate(cp.events_len)
  // Remove diagnostics added after checkpoint
  while self.errors.length() > 0 && self.error_count > cp.error_count {
    let _ = self.errors.pop()
    self.error_count = self.error_count - 1
  }
  self.open_nodes = cp.open_nodes
}
```

This requires adding a `length()` method and `truncate(n)` method to `EventBuffer`:

In `loom/src/core/parser.mbt` or `seam/event.mbt` — since `EventBuffer.events` is `priv`, add methods to `EventBuffer`:

**File:** `seam/event.mbt` — add:

```moonbit
///|
/// Current number of events in the buffer.
pub fn EventBuffer::length(self : EventBuffer) -> Int {
  self.events.length()
}

///|
/// Truncate the buffer to the first `n` events, discarding the rest.
/// No-op if `n >= length()`.
pub fn EventBuffer::truncate(self : EventBuffer, n : Int) -> Unit {
  while self.events.length() > n {
    let _ = self.events.pop()
  }
}
```

**Tests to add** (append to `loom/src/core/parser_wbtest.mbt`):

```moonbit
///|
test "checkpoint/restore: rewinds position and events" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let cp = ctx.checkpoint()
  ctx.emit_token(KNum) // consume "1"
  inspect(ctx.position > 0, content="true")
  ctx.restore(cp)
  inspect(ctx.position, content="0")
  // Token "1" is re-readable
  inspect(ctx.peek(), content="Num(1)")
  ctx.finish_node()
}

///|
test "checkpoint/restore: removes diagnostics added after checkpoint" {
  let src = "+"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let cp = ctx.checkpoint()
  ctx.error("speculative error")
  inspect(ctx.errors.length(), content="1")
  ctx.restore(cp)
  inspect(ctx.errors.length(), content="0")
  ctx.finish_node()
}

///|
test "checkpoint/restore: speculative parse picks successful branch" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  // Branch A: try to parse as a single number (will fail at "+")
  let cp = ctx.checkpoint()
  ctx.emit_token(KNum)
  let branch_a_ok = ctx.at_eof() // false — there's more input
  if not(branch_a_ok) {
    ctx.restore(cp)
  }
  // Branch B: parse as expression
  if not(branch_a_ok) {
    test_grammar(ctx)
  }
  ctx.finish_node()
  inspect(ctx.errors.length(), content="0")
  inspect(ctx.at_eof(), content="true")
}
```

**Verification:**

```bash
cd seam && moon test -p dowdiness/seam
cd loom && moon test -p dowdiness/loom/core
```

---

### Defect 3.3: No progress guarantee in error recovery

**Problem:** `skip_until` can return 0 if the current token is already a sync point. When a grammar author writes a recovery loop that calls `skip_until` followed by a retry, and the retry fails at the same sync token, the loop spins forever.

**File:** `loom/src/core/recovery.mbt`

**Fix:** Add `skip_until_progress` that guarantees forward progress unless at EOF: if already at a sync point, it consumes that sync token as an error so recovery loops cannot spin on the same token.

**Trade-off:** Consuming the sync token means the grammar cannot process it normally after recovery. This is intentional — `skip_until_progress` is designed for recovery loops where repeatedly hitting the same sync token without progress indicates the grammar cannot handle it. Use plain `skip_until` when the sync token must be preserved.

```moonbit
///|
/// Like skip_until, but guarantees forward progress: if the current token
/// is already a sync point, it is consumed as an error token so the parser
/// advances past it. At EOF, returns 0 (nothing to consume).
///
/// Returns the number of tokens consumed (always >= 1 unless at EOF).
///
/// Use this inside recovery loops to prevent infinite spinning.
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until_progress(
  self : ParserContext[T, K],
  is_sync : (T) -> Bool,
) -> Int {
  if self.at_eof() {
    return 0
  }
  if is_sync(self.peek()) {
    // Already at sync point — consume one token to make progress
    self.bump_error()
    return 1
  }
  let n = self.skip_until(is_sync)
  if n == 0 && not(self.at_eof()) {
    // Shouldn't happen given the is_sync check above, but defend in depth
    self.bump_error()
    return 1
  }
  n
}
```

**Tests to add** (append to `loom/src/core/recovery_wbtest.mbt`):

```moonbit
///|
test "skip_until_progress: consumes at least one token when at sync point" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  // is_sync matches Num — we're already at Num(1)
  // skip_until would return 0, but skip_until_progress consumes 1
  let skipped = ctx.skip_until_progress(t => {
    match t {
      Num(_) => true
      _ => false
    }
  })
  inspect(skipped, content="1")
  // Now at Plus, not stuck at Num(1)
  inspect(ctx.at(TestTok::Plus), content="true")
  ctx.finish_node()
}

///|
test "skip_until_progress: returns 0 at EOF" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_progress(_t => false)
  inspect(skipped, content="0")
  ctx.finish_node()
}

///|
test "skip_until_progress: normal skip when not at sync" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  // Skip until Num(2) — should skip Num(1) and Plus
  let skipped = ctx.skip_until_progress(t => {
    match t {
      Num(2) => true
      _ => false
    }
  })
  inspect(skipped, content="2")
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}
```

**Verification:**

```bash
cd loom && moon test -p dowdiness/loom/core
```

---

## Execution Order & Dependencies

```
Phase 1 (no dependencies between tasks — can be done in any order):
  1.1  emit_token abort removal          [parser.mbt]
  1.2  finish_node abort removal         [parser.mbt]
  1.3  parse_with/parse_tokens_indexed   [parser.mbt]

Phase 2 (1.1–1.3 must be done first):
  2.1  Resilient lexing                  [token_buffer.mbt, grammar.mbt, factories.mbt]
  2.2  Damage coordinate fix             [factories.mbt]

Phase 3 (independent of Phase 2, but Phase 1 must be done):
  3.1  peek_nth                          [parser.mbt]
  3.2  checkpoint/restore                [parser.mbt, event.mbt (seam)]
  3.3  skip_until_progress               [recovery.mbt]
```

---

## Verification Checklist

After all phases:

```bash
cd seam && moon test            # seam tests pass (event.mbt changes)
cd seam && moon check           # no warnings

cd loom && moon test            # all loom tests pass
cd loom && moon check           # no warnings

cd loom && moon info            # update pkg.generated.mbti files
cd loom && moon fmt             # format all files
```

**Interface diff check:**

```bash
cd loom && git diff src/core/pkg.generated.mbti
```

Expected additions:
- `ParserContext::peek_nth`
- `ParserContext::checkpoint`
- `ParserContext::restore`
- `ParserContext::skip_until_progress`
- `Checkpoint` struct
- `TokenBuffer::new_resilient`

```bash
cd seam && git diff pkg.generated.mbti
```

Expected additions:
- `EventBuffer::length`
- `EventBuffer::truncate`

No existing signatures should be removed or changed.
