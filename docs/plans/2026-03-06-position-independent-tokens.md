# Position-Independent Tokens — Implementation Plan

**Date:** March 6, 2026
**Status:** Draft
**Scope:** `loom/src/core/`, `loom/src/`, `loom/src/pipeline/`, `examples/lambda/`

## Goal

Make `TokenInfo[T]` position-independent by storing `(token, len)` instead of `(token, start, end)`. This enables meaningful token-sequence equality comparisons, unlocking a `TokenStage` memo boundary for early cutoff in the reactive pipeline.

## Motivation

### The Avalanche Problem

Today `TokenInfo` stores absolute byte offsets. Any single-character edit shifts every subsequent token's `start` and `end`. This is why the `TokenStage` memo was removed (ADR `2026-02-27-remove-tokenStage-memo.md`) — token arrays always differ after any edit, making the memo vacuous.

But position-independent `CstNode` already works correctly: it stores `text_len`, not absolute positions, and `SyntaxNode` computes positions ephemerally. Tokens should follow the same pattern.

### What This Unlocks

1. **TokenStage early cutoff** — when an edit changes only whitespace positions (not token kinds or content), the token sequence is unchanged and the parse memo can skip entirely.
2. **Cheaper tail reuse in `TokenBuffer::update`** — tail tokens keep their identity unchanged; only the parallel `starts` array shifts.
3. **Foundation for form-level modularity** — position-independent tokens can be compared across form boundaries for per-form incremental parsing.

## Design

### Core Change

```
Before: TokenInfo[T] { token: T, start: Int, end: Int }
After:  TokenInfo[T] { token: T, len: Int }
```

`TokenBuffer` maintains a parallel `starts : Array[Int]` for absolute positions, computed on construction and updated incrementally. This mirrors the CstNode/SyntaxNode split: identity (token, len) is separated from positioning (starts).

### Correctness Prerequisite

Token equality must capture lexeme identity for the memo boundary to be safe. Lambda calculus `Token` satisfies this — `Identifier(String)` and `Integer(Int)` carry their content. A `Token` enum that only stores kind (without payload) would need additional text identity.

### Invariants

```
starts.length() == tokens.length()
starts[i+1] == starts[i] + tokens[i].len   (for all i < len-1)
tokens[last].token == eof_token
starts[last] == source.length()
```

## Background Reading

Before starting:
- `loom/src/core/diagnostics.mbt` — `TokenInfo` struct definition, `Diagnostic`, `TokenInfo::new`
- `loom/src/core/token_buffer.mbt` — `TokenBuffer` struct, `update`, `find_left_index`, `find_right_index`, `tokenize_range_impl`
- `loom/src/core/parser.mbt` — `ParserContext` struct (uses `get_start`/`get_end` closures), `text_at`, `token_info_at_or_after`, `advance_past_reused`
- `loom/src/core/reuse_cursor.mbt` — `ReuseCursor` (uses `get_start` for binary search and `OffsetIndexed`)
- `loom/src/factories.mbt` — `create_buffer`, `new_imperative_parser`, `new_reactive_parser` (routes `tokens[i].start` through closures)
- `loom/src/pipeline/reactive_parser.mbt` — `Signal → Memo[CstStage] → Memo[Ast]` pipeline
- `docs/decisions/2026-02-27-remove-tokenStage-memo.md` — rationale for removing TokenStage (now being reversed)
- `examples/lambda/src/token/token.mbt` — `Token` enum with `Identifier(String)`, `Integer(Int)` payloads

## Phased Implementation

### Phase 0: Route All Position Access Through Accessors

**Goal:** Decouple position access from `TokenInfo` field layout. After this phase, no code outside `TokenBuffer` touches `.start`/`.end` directly.

**Files:**
- Modify: `loom/src/core/token_buffer.mbt` (add `get_token`, `get_end`, `token_count` methods)
- Modify: `loom/src/factories.mbt` (use buffer accessors instead of `tokens[i].start`)
- Modify: `examples/lambda/src/cst_parser.mbt` (same treatment)

**Tasks:**

1. Add indexed accessor methods to `TokenBuffer`:
   ```moonbit
   pub fn[T] TokenBuffer::get_token(self, i : Int) -> T
   pub fn[T] TokenBuffer::get_start(self, i : Int) -> Int  // rename from current get_tokens pattern
   pub fn[T] TokenBuffer::get_end(self, i : Int) -> Int
   pub fn[T] TokenBuffer::token_count(self) -> Int
   ```

2. Update `factories.mbt` — replace all `tokens[i].start` / `tokens[i].end` / `tokens[i].token` patterns with buffer accessor calls. Six call sites in `new_imperative_parser` and `new_reactive_parser`.

3. Update `examples/lambda/src/cst_parser.mbt` — same pattern in `parse_cst_recover`, `parse_cst_with_cursor`, `parse_cst_recover_with_tokens`, `parse_source_file`, `parse_source_file_recover_with_tokens`, `make_reuse_cursor`, `make_source_file_reuse_cursor`.

4. Remove `get_tokens()` method (returns the raw array — breaks encapsulation after this change). If external callers need iteration, add `iter()` or keep `get_tokens()` temporarily.

**Verification:**
```bash
cd loom && moon check && moon test
cd examples/lambda && moon check && moon test
```

**Risk:** Zero — purely mechanical refactoring. All tests must pass unchanged.

### Phase 1: Change `TokenInfo` to `(token, len)`

**Goal:** Make `TokenInfo` position-independent. `TokenInfo::Eq` compares `(token, len)` — no position data.

**Files:**
- Modify: `loom/src/core/diagnostics.mbt` (struct definition + constructor)
- Modify: `loom/src/core/token_buffer.mbt` (add `starts` array, adapt internal logic)
- Modify: `loom/src/core/lex_step.mbt` (`LexStep::Produced` carries `TokenInfo`)
- Modify: `loom/src/core/lex_step_wbtest.mbt` (update test token construction)
- Modify: `loom/src/core/parser_wbtest.mbt` (update test token construction)
- Modify: `loom/src/core/token_buffer_resilient_wbtest.mbt` (update test token construction)

**Tasks:**

1. Change `TokenInfo` struct:
   ```moonbit
   pub struct TokenInfo[T] {
     token : T
     len : Int
   } derive(Show, Eq)

   pub fn[T] TokenInfo::new(token : T, len : Int) -> TokenInfo[T] {
     { token, len }
   }
   ```

2. Add `starts : Array[Int]` to `TokenBuffer` struct. Update all constructors (`new`, `new_resilient`, `new_from_steps`, `new_from_steps_strict`) to build the `starts` array from token positions.

3. Update `TokenBuffer` accessor methods to compute positions from `starts + len`:
   ```moonbit
   pub fn[T] TokenBuffer::get_start(self, i) -> Int { self.starts[i] }
   pub fn[T] TokenBuffer::get_end(self, i) -> Int { self.starts[i] + self.tokens[i].len }
   ```

4. Adapt `TokenBuffer::update` internals:
   - `find_left_index` / `find_right_index`: use `starts[mid]` and `starts[mid] + tokens[mid].len`
   - Tail reuse: push unchanged `TokenInfo` objects (same token, same len) with shifted `starts` entries
   - `tokenize_range_impl`: build spanless `TokenInfo` from lexer output, compute `starts` by prefix walk from slice start

5. Update all `TokenInfo::new(token, start, end)` call sites to `TokenInfo::new(token, end - start)`. This affects:
   - `loom/src/core/token_buffer.mbt` (`tokenize_from_steps`, `tokenize_from_steps_strict`, `tokenize_resilient`, `update`)
   - `loom/src/core/lex_step_wbtest.mbt` (test lexers)
   - `loom/src/core/parser_wbtest.mbt` (test fixtures)
   - `loom/src/core/token_buffer_resilient_wbtest.mbt` (test tokenizers)

6. Update `ParserContext::peek_info` return value — it currently constructs `TokenInfo { token, start, end }`. Change to return a positioned type or adjust callers. The only external caller is `ParserContext::error` which needs `start`/`end` for diagnostics — these should come from `get_start`/`get_end` instead.

**Verification:**
```bash
cd loom && moon check && moon test
```

**Risk:** Medium — touches many files. The `starts` array invariant must hold. Add a debug-mode assertion in `TokenBuffer` constructors to validate the invariant.

### Phase 2: Adapt Lexer Output Boundary

**Goal:** Lexers continue producing positioned tokens externally; normalization happens at the `TokenBuffer` boundary. No lexer contract changes required.

**Files:**
- Modify: `loom/src/core/token_buffer.mbt` (normalization in constructors)
- Modify: `loom/src/grammar.mbt` (`Grammar.tokenize` signature may need a raw/positioned intermediate type)

**Tasks:**

1. Introduce an internal `RawToken[T]` or use `(T, Int, Int)` tuple at the tokenizer boundary. `TokenBuffer` constructors accept the old `(token, start, end)` format from lexers and normalize to `(token, len)` + `starts`:
   ```moonbit
   // Normalization in TokenBuffer::new
   let tokens = raw.map(fn(r) { TokenInfo::new(r.token, r.end - r.start) })
   let starts = raw.map(fn(r) { r.start })
   ```

2. Keep `Grammar.tokenize` signature producing positioned tokens. The conversion is internal to `TokenBuffer`.

3. Update `LexStep::Produced` — currently carries `TokenInfo[T]` with `start`/`end`. The step lexer naturally knows `(token, next_offset - start)`, so adapt to carry `TokenInfo[T]` with `len`. The `tokenize_from_steps` loop maintains a running offset to build `starts`.

**Verification:**
```bash
cd loom && moon check && moon test
cd examples/lambda && moon check && moon test
```

**Risk:** Low — lexer implementations unchanged. Conversion is localized to `TokenBuffer`.

### Phase 3: Lambda Lexer Migration

**Goal:** Update the lambda calculus lexer and all example-level token consumers to work with position-independent `TokenInfo`.

**Files:**
- Modify: `examples/lambda/src/lexer/lexer.mbt` (update `TokenInfo::new` calls)
- Modify: `examples/lambda/src/token/token.mbt` (`print_token_info` no longer has start/end)
- Modify: `examples/lambda/src/cst_parser.mbt` (uses buffer accessors from Phase 0)
- Modify: `examples/lambda/src/lexer/lexer_test.mbt` (update position assertions)

**Tasks:**

1. Update `tokenize_helper` — change `TokenInfo::new(token, pos, new_pos)` to `TokenInfo::new(token, new_pos - pos)`. Return a positioned intermediate if the `Grammar.tokenize` contract still requires it, or adapt the contract.

2. Update `print_token_info` — no longer shows `@start-end` (positions are not in `TokenInfo`). Adjust to show `token(len)` or remove position display.

3. Update lexer tests that assert on token `start`/`end` values. These should either:
   - Assert on `len` instead, or
   - Use a test helper that reconstructs positions from the token array for verification.

4. Run the full test suite including incremental, differential, and property tests.

**Verification:**
```bash
cd examples/lambda && moon check && moon test
cd examples/lambda && moon bench --release  # no performance regression
```

### Phase 4: Reintroduce TokenStage Memo

**Goal:** Add a `TokenStage` memo boundary in the reactive pipeline. When the token sequence is unchanged after an edit, the parse memo skips entirely.

**Files:**
- Modify: `loom/src/pipeline/language.mbt` (add `TokenStage` struct)
- Modify: `loom/src/pipeline/reactive_parser.mbt` (three-memo pipeline)
- Modify: `loom/src/factories.mbt` (`new_reactive_parser` wiring)
- Modify: `loom/src/pipeline/reactive_parser_test.mbt` (add tests)

**Tasks:**

1. Define `TokenStage`:
   ```moonbit
   pub(all) struct TokenStage[T] {
     tokens : Array[TokenInfo[T]]
     is_lex_error : Bool
   } derive(Eq)
   ```

2. Update `ReactiveParser` to three memos:
   ```
   Signal[String]
     → Memo[TokenStage[T]]   (lex only — early cutoff when tokens unchanged)
     → Memo[CstStage]        (parse — early cutoff when CstNode unchanged)
     → Memo[Ast]
   ```

3. The `TokenStage` memo lexes the source and produces position-independent tokens. `CstStage` memo receives the `TokenStage`, reconstructs positions (prefix sum), and parses.

4. Add tests verifying:
   - Whitespace-only edits that don't change token kinds/content → `TokenStage` unchanged → parse skipped
   - Edits that change token content → `TokenStage` changes → re-parse triggered
   - `Whitespace` token len changes ARE detected (trivia tokens are in the array) — discuss whether trivia should be excluded from equality for stronger cutoff

5. Update the `TokenStage` removal ADR or add a new ADR explaining the reversal.

**Verification:**
```bash
cd loom && moon check && moon test
cd examples/lambda && moon check && moon test
```

**Risk:** Low — additive change. The existing `CstStage` cutoff remains as a second boundary.

### Phase 5 (Follow-up): Trivia-Insensitive Token Equality

**Goal:** Optional stronger cutoff — whitespace-only edits (changing trivia length) should not invalidate the parse.

**Status:** Deferred — design decision needed on whether to filter trivia from equality or normalize trivia lengths.

**Options:**
- A. `TokenStage::Eq` compares only non-trivia tokens (filter out `Whitespace`/`Newline`)
- B. Normalize trivia: coalesce consecutive whitespace into a single `Whitespace(len=1)` for comparison
- C. Separate `eq_key` field that excludes trivia

This phase is not required for the core position-independent token benefit. The primary win (position-shift cutoff) is achieved by Phase 4.

## Verification Matrix

For each phase, run:
```bash
cd loom && moon check && moon test      # 88+ tests
cd seam && moon check && moon test      # 99 tests (unchanged — seam has no token dependency)
cd examples/lambda && moon check && moon test  # 311+ tests
```

Before commit:
```bash
cd loom && moon info && moon fmt
cd examples/lambda && moon info && moon fmt
```

## Risks and Mitigations

1. **Risk:** `Diagnostic[T]` stores absolute `start`/`end` positions — these must still be computed.
   **Mitigation:** Diagnostics are created inside `ParserContext::error` which already uses `get_start`/`get_end` closures. No change needed — positions flow through accessors, not `TokenInfo`.

2. **Risk:** External code directly accesses `TokenInfo.start`/`TokenInfo.end` fields.
   **Mitigation:** Phase 0 systematically eliminates all direct field access before changing the struct. `moon check` catches any remaining references at compile time.

3. **Risk:** Performance regression from parallel `starts` array allocation.
   **Mitigation:** `starts` is the same size as the existing `tokens` array (one `Int` per token). Net memory is reduced — two `Int`s removed from each `TokenInfo`, one `Int` added per entry in `starts`. Benchmark with `moon bench --release`.

4. **Risk:** `LexStep::Produced` currently carries `TokenInfo` with position — changing it affects step lexer implementations.
   **Mitigation:** Phase 2 handles this at the `TokenBuffer` boundary. Existing step lexers can be adapted incrementally.

## Deliverables Checklist

- [ ] `TokenBuffer` accessor methods (`get_token`, `get_start`, `get_end`, `token_count`)
- [ ] All external position access routed through accessors
- [ ] `TokenInfo` changed to `{ token, len }`
- [ ] `TokenBuffer` stores `tokens + starts` parallel arrays
- [ ] `TokenBuffer::update` works with new representation
- [ ] Lambda lexer and tests updated
- [ ] `TokenStage` memo reintroduced in reactive pipeline
- [ ] ADR for TokenStage reversal
- [ ] Benchmarks show no regression
