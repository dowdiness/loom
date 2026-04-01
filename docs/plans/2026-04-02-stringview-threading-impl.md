# StringView Threading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate intermediate String allocations in the parse pipeline by threading StringView through ParseEvent → Interner → CstToken, achieving zero allocations on the interner hit path.

**Architecture:** `token_text_at` returns `StringView` (zero-copy slice into source). `ParseEvent::Token` carries `StringView`. `Interner` uses `HashMap[StringView, CstToken]` for zero-alloc lookups — stored keys reference `CstToken.text` (owned String), not the source, so old sources are GC'd normally. `CstToken::new` accepts `StringView` and calls `.to_string()` internally, preserving the position-independent `text: String` field.

**Tech Stack:** MoonBit, StringView (built-in zero-copy string slice)

**Key insight:** MoonBit auto-coerces `String` → `StringView` in function arguments and enum constructors. All existing callers compile without changes after each step.

**Dependency order:** Changes flow bottom-up: hash → CstToken → Interner → ParseEvent → ParserContext. Each consumer is updated before its producer, so `moon check` passes after every step.

---

### Task 1: `string_hash` accepts `StringView`

**Files:**
- Modify: `seam/hash.mbt:10` — parameter type

- [ ] **Step 1: Change `string_hash` parameter from `String` to `StringView`**

In `seam/hash.mbt`, change line 10:

```moonbit
pub fn string_hash(s : StringView) -> Int {
```

The body is unchanged — `s.length()` and `s.code_unit_at(i)` work on `StringView`.

- [ ] **Step 2: Run `moon check` in seam/**

```bash
cd seam && moon check
```

Expected: PASS (all callers auto-coerce String → StringView)

- [ ] **Step 3: Run `moon test` in seam/**

```bash
cd seam && moon test
```

Expected: all 351 tests pass

- [ ] **Step 4: Commit**

```bash
cd seam && moon info && moon fmt
git add seam/hash.mbt seam/pkg.generated.mbti
git commit -m "refactor(seam): string_hash accepts StringView"
```

---

### Task 2: `CstToken::new` accepts `StringView`

**Files:**
- Modify: `seam/cst_node.mbt:30-34` — parameter type + `.to_string()` for storage

- [ ] **Step 1: Change `CstToken::new` to accept `StringView`**

In `seam/cst_node.mbt`, replace the constructor (lines 30-34):

```moonbit
pub fn CstToken::new(kind : RawKind, text : StringView) -> CstToken {
  let RawKind(k) = kind
  let h = combine_hash(k, string_hash(text))
  { kind, text: text.to_string(), hash: h }
}
```

Key change: `text` parameter is `StringView`, and `text.to_string()` materializes the owned String for the struct field.

- [ ] **Step 2: Run `moon check` in seam/**

```bash
cd seam && moon check
```

Expected: PASS (all callers pass String, auto-coerced to StringView)

- [ ] **Step 3: Run `moon test` in seam/**

```bash
cd seam && moon test
```

Expected: all tests pass. The `interner_wbtest` test comparing `interned == direct` still passes because both produce tokens with the same hash and text content.

- [ ] **Step 4: Commit**

```bash
cd seam && moon info && moon fmt
git add seam/cst_node.mbt seam/pkg.generated.mbti
git commit -m "refactor(seam): CstToken::new accepts StringView"
```

---

### Task 3: Interner uses `StringView` keys for zero-alloc hit path

**Files:**
- Modify: `seam/interner.mbt:14-51` — HashMap key type + `intern_token` parameter

- [ ] **Step 1: Change Interner struct and `intern_token`**

Replace the full content of `seam/interner.mbt`:

```moonbit
///|
/// Session-scoped token intern table.
///
/// Deduplicates CstToken objects by (kind, text): every call to
/// intern_token with the same arguments returns a structurally equal token.
///
/// Lifetime: own one Interner per parse session (e.g. per IncrementalParser).
/// The GC collects the Interner and all its tokens when the owner is dropped.
/// Not thread-safe.
///
/// Key design: two-level map (RawKind → (StringView → CstToken)).
/// On the hot hit path, lookup uses the caller's StringView directly
/// with zero allocation. Stored keys are auto-coerced from CstToken.text
/// (owned String), so old source strings are not retained by the interner.
pub struct Interner {
  priv tokens : @hashmap.HashMap[RawKind, @hashmap.HashMap[StringView, CstToken]]
}

///|
/// Create a new empty Interner.
pub fn Interner::new() -> Interner {
  { tokens: @hashmap.HashMap::new() }
}

///|
/// Return the canonical CstToken for (kind, text).
/// On first call for a given pair: allocates a CstToken and stores it.
/// On subsequent calls: returns the stored object (same heap reference).
/// Hit path is zero-alloc — StringView lookup, no String materialization.
pub fn Interner::intern_token(
  self : Interner,
  kind : RawKind,
  text : StringView,
) -> CstToken {
  match self.tokens.get(kind) {
    Some(inner) =>
      match inner.get(text) {
        Some(token) => token
        None => {
          let token = CstToken::new(kind, text)
          inner.set(token.text, token)
          token
        }
      }
    None => {
      let token = CstToken::new(kind, text)
      let inner : @hashmap.HashMap[StringView, CstToken] = @hashmap.HashMap::new()
      inner.set(token.text, token)
      self.tokens.set(kind, inner)
      token
    }
  }
}

///|
/// Number of distinct (kind, text) pairs currently interned.
pub fn Interner::size(self : Interner) -> Int {
  let mut total = 0
  self.tokens.each(fn(_kind, inner) { total = total + inner.length() })
  total
}

///|
/// Clear all interned tokens. The Interner can be reused after this call,
/// e.g. when starting a new document in a long-lived language server session.
pub fn Interner::clear(self : Interner) -> Unit {
  self.tokens.clear()
}
```

Note: `inner.set(token.text, token)` — `token.text` is `String`, auto-coerced to `StringView` for the HashMap key. The key references `token.text`'s backing String (owned by the CstToken), not the source string. This ensures old source strings are GC'd after parsing.

- [ ] **Step 2: Run `moon check` in seam/**

```bash
cd seam && moon check
```

Expected: PASS (all callers pass String, auto-coerced to StringView)

- [ ] **Step 3: Run `moon test` in seam/**

```bash
cd seam && moon test
```

Expected: all tests pass. Interner tests use string literals which auto-coerce.

- [ ] **Step 4: Commit**

```bash
cd seam && moon info && moon fmt
git add seam/interner.mbt seam/pkg.generated.mbti
git commit -m "perf(seam): Interner uses StringView keys for zero-alloc hit path"
```

---

### Task 4: `ParseEvent::Token` carries `StringView`

**Files:**
- Modify: `seam/event.mbt:16` — variant payload type

- [ ] **Step 1: Change the Token variant**

In `seam/event.mbt`, change line 16:

```moonbit
  /// A leaf token with the given kind and source text view.
  Token(RawKind, StringView)
```

- [ ] **Step 2: Update `build_tree` Token case**

In `seam/event.mbt`, the `build_tree` function's Token case (line 485-490). The pattern match now binds `text` as `StringView`. `CstToken::new(kind, text)` already accepts `StringView` (Task 2). No code change needed — verify the pattern match compiles.

- [ ] **Step 3: Run `moon check` in seam/**

```bash
cd seam && moon check
```

Expected: PASS. Pattern matches bind `StringView` instead of `String`. All consumers (`CstToken::new`, `intern_token`) already accept `StringView` from Tasks 2-3. Test constructors like `ParseEvent::Token(kind, "x")` auto-coerce.

- [ ] **Step 4: Run `moon test` in seam/**

```bash
cd seam && moon test
```

Expected: all tests pass.

- [ ] **Step 5: Run `moon check` and `moon test` in downstream modules**

```bash
cd ../loom && moon check && moon test
cd ../examples/lambda && moon check && moon test
cd ../examples/json && moon check && moon test
```

Expected: all pass. The parser's `emit_token` and `flush_trivia` still produce `ParseEvent::Token(kind, text)` where `text` is `String` (from `token_text_at`). String auto-coerces to StringView for the enum constructor.

- [ ] **Step 6: Commit**

```bash
cd seam && moon info && moon fmt
git add seam/event.mbt seam/pkg.generated.mbti
git commit -m "refactor(seam): ParseEvent::Token carries StringView"
```

---

### Task 5: `token_text_at` returns `StringView`

**Files:**
- Modify: `loom/src/core/parser.mbt:281-327` — return types + remove surrogate slow path

- [ ] **Step 1: Change `token_text_at` to return `StringView`**

In `loom/src/core/parser.mbt`, replace the `token_text_at` function (lines 269-304):

```moonbit
///|
/// Extract the source text of the token at `pos` as a zero-copy StringView.
///
/// Returns a view into `self.source`. No String allocation.
/// StringView slicing does not validate UTF-16, preserving raw code units
/// for CRDT sync fidelity. Surrogate handling is deferred to point-of-use.
pub fn[T, K] ParserContext::token_text_at(
  self : ParserContext[T, K],
  pos : Int,
) -> StringView {
  if pos < 0 || pos >= self.token_count {
    return ""
  }
  let start = (self.get_start)(pos)
  let end = (self.get_end)(pos)
  if start < 0 || end < start || end > self.source.length() {
    return ""
  }
  self.source[start:end]
}
```

Key changes:
- Return type: `String` → `StringView`
- Removed `has_lone_surrogate` check and StringBuilder slow path
- `self.source[start:end]` is zero-copy (no `.to_string()`)
- Empty string literals `""` auto-coerce to `StringView`

- [ ] **Step 2: Change `text_at` alias return type**

In `loom/src/core/parser.mbt`, update the `text_at` alias (lines 320-327):

```moonbit
///|
/// Extract source text at a token index. Internal alias for token_text_at.
fn[T, K] ParserContext::text_at(
  self : ParserContext[T, K],
  pos : Int,
) -> StringView {
  self.token_text_at(pos)
}
```

- [ ] **Step 3: Remove `has_lone_surrogate` function**

Delete lines 306-318 in `loom/src/core/parser.mbt`:

```moonbit
// DELETE the entire has_lone_surrogate function (lines 306-318)
```

The surrogate scan is no longer needed — StringView slicing preserves raw code units.

- [ ] **Step 4: Run `moon check` in loom/**

```bash
cd loom && moon check
```

Expected: PASS. `emit_token` and `flush_trivia` call `self.text_at()` which now returns `StringView`. They pass it to `ParseEvent::Token(kind, text)` which expects `StringView` (Task 4). ✓

- [ ] **Step 5: Run `moon test` across all modules**

```bash
cd loom && moon test
cd ../seam && moon test
cd ../examples/lambda && moon test
cd ../examples/json && moon test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/core/parser.mbt loom/src/core/pkg.generated.mbti
git commit -m "perf(core): token_text_at returns StringView (zero-copy)"
```

---

### Task 6: Verification and benchmarks

**Files:**
- Read: `examples/lambda/src/benchmarks/zero_copy_benchmark.mbt`

- [ ] **Step 1: Run full test suite**

```bash
cd seam && moon test
cd ../loom && moon test
cd ../examples/lambda && moon test
cd ../examples/json && moon test
```

Expected: all tests pass across all modules.

- [ ] **Step 2: Run `moon info && moon fmt` in modified modules**

```bash
cd seam && moon info && moon fmt
cd ../loom && moon info && moon fmt
```

- [ ] **Step 3: Verify API changes with `git diff *.mbti`**

```bash
git diff *.mbti seam/pkg.generated.mbti loom/src/core/pkg.generated.mbti
```

Expected changes:
- `string_hash(String)` → `string_hash(StringView)`
- `CstToken::new(RawKind, String)` → `CstToken::new(RawKind, StringView)`
- `Interner::intern_token(... String)` → `Interner::intern_token(... StringView)`
- `ParseEvent::Token(RawKind, String)` → `ParseEvent::Token(RawKind, StringView)`
- `token_text_at` return type `String` → `StringView`
- `has_lone_surrogate` removed

- [ ] **Step 4: Run zero-copy benchmarks**

```bash
cd examples/lambda && moon bench --release -p dowdiness/lambda/benchmarks -f zero_copy_benchmark.mbt
```

Baseline (before):

| Input | Tokenize | Full Parse |
|-------|----------|------------|
| Integers | 2.80 µs | 28.69 µs |
| Short identifiers | 5.09 µs | 30.62 µs |
| Long identifiers | 6.35 µs | 45.81 µs |

Expected: tokenize times unchanged (lexer not modified). Full parse times reduced, especially for long identifiers where interner hit-path savings are largest.

- [ ] **Step 5: Record benchmark results in spec**

Add "after" column to the benchmark table in `docs/plans/2026-04-02-stringview-threading-design.md`.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "docs: record StringView threading benchmark results"
```
