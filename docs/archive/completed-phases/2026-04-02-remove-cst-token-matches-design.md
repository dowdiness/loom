# Remove `cst_token_matches` — Framework-Owned Token Matching

**Date:** 2026-04-02
**Status:** Complete
**Scope:** loom/core (LanguageSpec, ReuseCursor), lambda (Token, lexer), json (Token, lexer)
**Motivation:** Simplify LanguageSpec API, eliminate payload-carrying Token enums, remove O(n²) lexer string building

---

## Goal

Move token matching from a per-language callback to framework-internal logic.
Every language currently implements identical boilerplate in `cst_token_matches`:
"for payload tokens compare text, for fixed tokens compare kind." The framework
already has all the information to do this itself: old `CstToken.text` and new
source text via `token_text_at`.

**Result:** `cst_token_matches` removed from `LanguageSpec`. Languages use
payload-free Token enums. Lexers no longer build strings that are immediately
discarded.

---

## Design

### Framework change — ReuseCursor owns token matching

The reuse cursor currently delegates to
`spec.cst_token_matches(old_kind, old_text, new_token_T)`.

Replace with direct comparison:

```
old_tok.kind == get_token(pos).to_raw() && old_tok.text == text_at(pos)
```

**Changes:**
- Add `text_at : (Int) -> StringView` closure to `ReuseCursor` (sourced from
  `ParserContext::token_text_at`)
- Replace both callsites in `reuse_cursor.mbt`:
  - `leading_token_matches` (line 244)
  - `trailing_context_matches` (line 352)
- Remove `cst_token_matches` field from `LanguageSpec` struct and constructor

`String == StringView` comparison works via MoonBit auto-coercion — `old_tok.text`
(String) coerces to StringView for content equality. Verify at implementation time
that `Eq` across `String`/`StringView` compares by content, not reference.

**Correctness argument:** The reuse cursor only checks tokens outside the damage
range. For undamaged tokens, old text == new text at the corresponding position.
Kind comparison via `to_raw()` handles the case where different token kinds share
the same text (e.g., `in` as keyword vs identifier).

### Lambda Token enum — drop payloads

```moonbit
// Before
Identifier(String)  // carries name
Integer(Int)        // carries parsed value
Error(String)       // carries error message

// After
Identifier          // kind tag only
Integer             // kind tag only
Error(String)       // KEEP — message not derivable from source
```

`Error(String)` keeps its payload because error messages are synthetic (generated
by the lexer, not present in source text).

**File changes in `examples/lambda/src/`:**
- `token/token.mbt` — remove payloads from `Identifier` and `Integer`
- `token/token.mbt` `Show` impl — `Identifier` shows `"<ident>"`, `Integer`
  shows `"<int>"` (debug only)
- `lexer/lexer.mbt` — `read_identifier` becomes a position-advancing loop
  returning `(end_pos, len)`. Keyword matching uses `input[start:end]` StringView.
  `read_number` returns `(end_pos, len)` only.
- `lambda_spec.mbt` — remove `cst_token_matches` from LanguageSpec constructor
- `cst_parser.mbt` — `Identifier(_)` → `Identifier`, `Integer(_)` → `Integer`

### JSON Token enum — same treatment

```moonbit
// Before
StringLit(String)   // carries raw text including quotes
NumberLit(String)    // carries raw text

// After
StringLit           // kind tag only
NumberLit           // kind tag only
```

**File changes in `examples/json/src/`:**
- `token.mbt` — remove payloads from `StringLit` and `NumberLit`
- `token.mbt` `Show` impl — `StringLit` shows `"<string>"`, `NumberLit`
  shows `"<number>"`
- `lexer.mbt` — string/number readers return `(end_pos, len)` instead of
  accumulated text
- `json_spec.mbt` — remove `cst_token_matches` from LanguageSpec constructor
- `cst_parser.mbt` — `StringLit(_)` → `StringLit`, `NumberLit(_)` → `NumberLit`

---

## What does NOT change

- `Token::Error(String)` payload — synthetic, not from source
- `CstToken.text: String` — framework-level text storage unchanged
- `SyntaxToken.text()` — consumers unaffected
- AST layer — already uses `token_text_at()` / `SyntaxToken.text()`, not Token payloads
- Incremental reuse / damage tracking — same protocol, different matching impl
- `CstNode` interning — unrelated

---

## Test impact

**Tests that need updating:**
- `loom/src/core/parser_wbtest.mbt` — remove `cst_token_matches` from test
  fixtures. Delete "cst_token_matches callback is stored and callable" test.
- `loom/src/factories_wbtest.mbt` — remove callback from test LanguageSpec
- `examples/lambda/src/*_test.mbt` — `Token::Identifier("x")` → `Token::Identifier`,
  `Token::Integer(42)` → `Token::Integer`. Snapshot tests may need `--update`.
- `examples/json/src/*_test.mbt` — same pattern for `StringLit`/`NumberLit`

**Correctness verification:**
- All existing reuse cursor tests must pass (exercise leading/trailing matching)
- Lambda and JSON incremental benchmarks serve as integration tests
- Full test suites: seam (162), loom (195), lambda (410), json (72)

**No new tests needed** — framework matching is strictly simpler than the callback.

---

## Dependency order

1. **Framework (loom)** — remove callback, add `text_at` to ReuseCursor
2. **Lambda** — drop payloads, simplify lexer
3. **JSON** — drop payloads, simplify lexer

Steps 2 and 3 are independent but both depend on step 1.

---

## Scope boundaries

**In scope:** LanguageSpec simplification, Token payload removal, lexer cleanup.

**Not in scope:** `Token::Eq`/`Hash` implications (no code depends on content-level
token equality), framework trait additions, markdown parser, loomgen.

---

## Benchmark results

Incremental parsing benchmarks (`--release`, wasm-gc, realistic grammar):

| Benchmark | Before | After | Change |
|-----------|--------|-------|--------|
| 40 defs - full reparse | 241 µs | 241 µs | same |
| 40 defs - incr (edit tail) | 311 µs | 287 µs | **-8%** |
| 40 defs - incr (edit head block) | 14.2 µs | 12.8 µs | **-10%** |
| 40 defs - incr (edit middle block) | 14.4 µs | 13.2 µs | **-8%** |
| 80 defs - full reparse | 525 µs | 476 µs | **-9%** |
| 80 defs - incr (edit tail) | 642 µs | 590 µs | **-8%** |
| 80 defs - incr (edit middle block) | 14.8 µs | 13.1 µs | **-11%** |
| 160 defs - full reparse | 1.32 ms | 1.07 ms | **-19%** |
| 160 defs - incr (edit tail) | 1.34 ms | 1.20 ms | **-10%** |
| 160 defs - incr (edit middle block) | 14.8 µs | 13.6 µs | **-8%** |

Tokenize-only (zero-copy benchmark):

| Input | Before | After | Change |
|-------|--------|-------|--------|
| Short identifiers | 4.88 µs | 4.04 µs | **-17%** |
| Long identifiers | 6.05 µs | 5.14 µs | **-15%** |

Speedup from payload-free Token enum (unboxed tags = fewer heap allocations)
and lexer accumulator elimination (O(n²) → O(n) for identifiers).

## Implementation notes

- `T : @seam.ToRawKind` bound propagated upward through `try_reuse` → `node` →
  `node_with_recovery` → `try_reuse_repeat_group` in `parser.mbt` and `recovery.mbt`.
- `TokenStage::Eq` in `diagnostics.mbt` needed text-based comparison after payload
  removal — previously relied on payload equality for memo invalidation.
- `make_reuse_cursor` in lambda/json gained a `source : String` parameter for the
  `get_text` closure.

## Validation

```bash
cd loom && moon check && moon test
cd seam && moon check && moon test
cd examples/lambda && moon check && moon test
cd examples/json && moon check && moon test
cd examples/lambda && moon bench --release
```
