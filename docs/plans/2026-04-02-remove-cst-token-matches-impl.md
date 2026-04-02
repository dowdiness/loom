# Remove `cst_token_matches` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `cst_token_matches` callback from LanguageSpec. Framework compares old CstToken against new source directly. Languages use payload-free Token enums.

**Architecture:** ReuseCursor gains a `text_at` closure (from `token_text_at`). Token matching becomes `old.kind == new_token.to_raw() && old.text == text_at(pos)`. Lambda and JSON Token enums drop text payloads. Lexers return position/length instead of accumulated strings.

**Tech Stack:** MoonBit, loom framework, seam CST library

**Key insight:** MoonBit auto-coerces `String` → `StringView` for `==` comparison, so `old_cst_token.text == text_at(pos)` works without explicit conversion.

---

### Task 1: Add `text_at` to ReuseCursor, replace `cst_token_matches` callsites

**Files:**
- Modify: `loom/src/core/reuse_cursor.mbt:99-116` — add `text_at` field to struct
- Modify: `loom/src/core/reuse_cursor.mbt:161-197` — add `text_at` parameter to `ReuseCursor::new`
- Modify: `loom/src/core/reuse_cursor.mbt:231-246` — replace `leading_token_matches`
- Modify: `loom/src/core/reuse_cursor.mbt:340-355` — replace `trailing_context_matches`

- [ ] **Step 1: Add `text_at` field to ReuseCursor struct**

In `loom/src/core/reuse_cursor.mbt`, add after line 114 (`get_start`):

```moonbit
  get_text : (Int) -> StringView
```

- [ ] **Step 2: Add `text_at` parameter to `ReuseCursor::new`**

In `loom/src/core/reuse_cursor.mbt`, add parameter after `get_start`:

```moonbit
pub fn[T, K : @seam.ToRawKind] ReuseCursor::new(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_text : (Int) -> StringView,
  spec : LanguageSpec[T, K],
  reuse_size_threshold? : Int = 0,
  old_token_cache? : OldTokenCache = OldTokenCache::empty(),
) -> ReuseCursor[T, K] {
```

Add `get_text,` to the struct literal in the constructor body.

- [ ] **Step 3: Replace `leading_token_matches` to use framework comparison**

Replace the function body:

```moonbit
fn[T, K : @seam.ToRawKind] leading_token_matches(
  node : @seam.CstNode,
  cursor : ReuseCursor[T, K],
  token_pos : Int,
) -> Bool {
  if token_pos >= cursor.token_count {
    return false
  }
  let new_kind = (cursor.get_token)(token_pos).to_raw()
  let ws_raw = cursor.spec.whitespace_kind.to_raw()
  match node.first_token(fn(r) { r == ws_raw }) {
    None => false
    Some(old_tok) =>
      old_tok.kind == new_kind && old_tok.text == (cursor.get_text)(token_pos)
  }
}
```

- [ ] **Step 4: Add `new_follow_token_with_pos` helper**

`new_follow_token` (line 320) returns `T?` — the token value but not its index.
We need the index to call `get_text(pos)`. Add a variant that returns both:

```moonbit
fn[T : @seam.IsTrivia + @seam.IsEof, K] new_follow_token_with_pos(
  cursor : ReuseCursor[T, K],
  byte_offset : Int,
) -> (T, Int)? {
  let mut lo = lower_bound(cursor, byte_offset)
  while lo < cursor.token_count {
    let t = (cursor.get_token)(lo)
    if t.is_eof() {
      break
    }
    if t.is_trivia() {
      lo = lo + 1
      continue
    }
    return Some((t, lo))
  }
  None
}
```

- [ ] **Step 5: Replace `trailing_context_matches` to use framework comparison**

Replace the function body:

```moonbit
fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] trailing_context_matches(
  cursor : ReuseCursor[T, K],
  node_end : Int,
) -> Bool {
  let old_follow = old_follow_token_lazy(cursor, node_end)
  let new_follow = new_follow_token_with_pos(cursor, node_end)
  match (old_follow, new_follow) {
    (None, None) => true
    (Some(old), Some((new_tok, new_pos))) =>
      old.kind == new_tok.to_raw() && old.text == (cursor.get_text)(new_pos)
    _ => false
  }
}
```

Note: added `K : @seam.ToRawKind` bound since we now call `.to_raw()` on the token.

- [ ] **Step 6: Run `moon check` in loom/**

```bash
cd loom && moon check
```

Expected: compilation errors where `cst_token_matches` is still referenced. Fix any remaining references.

- [ ] **Step 7: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/core/reuse_cursor.mbt loom/src/core/pkg.generated.mbti
git commit -m "refactor(core): ReuseCursor owns token matching via text_at"
```

---

### Task 2: Remove `cst_token_matches` from LanguageSpec

**Files:**
- Modify: `loom/src/core/parser.mbt:58-102` — remove field and constructor parameter

- [ ] **Step 1: Remove `cst_token_matches` field from LanguageSpec struct**

In `loom/src/core/parser.mbt`, delete lines 64-65:

```moonbit
  // DELETE these lines:
  // reuse support: match old leaves to new tokens
  cst_token_matches : (@seam.RawKind, String, T) -> Bool
```

- [ ] **Step 2: Remove from LanguageSpec::new constructor**

In `loom/src/core/parser.mbt`, remove the `cst_token_matches` parameter (lines 86-88) and its assignment (line 98):

```moonbit
// DELETE parameter:
//   cst_token_matches? : (@seam.RawKind, String, T) -> Bool = fn(_, _, _) { false },
// DELETE from struct literal:
//   cst_token_matches,
```

- [ ] **Step 3: Update ReuseCursor::new callsite in factories.mbt**

In `loom/src/factories.mbt:195-207`, add the `get_text` closure:

```moonbit
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          edit.start,
          edit.old_end(),
          buffer.token_count(),
          fn(i) { buffer.get_token(i) },
          fn(i) { buffer.get_start(i) },
          fn(i) { buffer.get_text(i) },
          spec,
          reuse_size_threshold=spec.reuse_size_threshold,
          old_token_cache=old_token_cache.val,
        ),
      )
```

Verify `TokenBuffer` has a `get_text` method. If not, add one that delegates to `token_text_at` on the underlying source.

- [ ] **Step 4: Update reuse_cursor.mbt header comment**

In `loom/src/core/reuse_cursor.mbt:1-10`, remove the `cst_token_matches` line from the comment:

```moonbit
// DELETE:
//   cst_token_matches            — match old leaf (RawKind + text) to new token T
```

- [ ] **Step 5: Run `moon check` in loom/**

```bash
cd loom && moon check
```

Expected: PASS. All `cst_token_matches` references removed from framework.

- [ ] **Step 6: Run `moon test` in loom/**

```bash
cd loom && moon test
```

Expected: compilation errors in test files that reference `cst_token_matches`. Fix in Task 3.

- [ ] **Step 7: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/core/parser.mbt loom/src/core/reuse_cursor.mbt loom/src/factories.mbt loom/src/core/pkg.generated.mbti
git commit -m "refactor(core): remove cst_token_matches from LanguageSpec"
```

---

### Task 3: Update loom test fixtures

**Files:**
- Modify: `loom/src/core/parser_wbtest.mbt` — remove all `cst_token_matches` from test specs
- Modify: `loom/src/factories_wbtest.mbt` — same

- [ ] **Step 1: Remove `cst_token_matches` from test LanguageSpec constructors**

Search `parser_wbtest.mbt` for all `cst_token_matches` references. Remove the parameter from every `LanguageSpec::new` call. The default behavior is now in the framework.

At minimum, update:
- Line 35: `cst_token_matches: fn(_, _, _) { false }` → delete
- Line 244: `cst_token_matches: fn(raw, text, tok) { ... }` → delete
- Line 538: test "LanguageSpec cst_token_matches callback is stored and callable" → delete entire test
- Line 1266: `cst_token_matches=test_spec.cst_token_matches` → delete

- [ ] **Step 2: Add `get_text` to test ReuseCursor constructions**

Every `ReuseCursor::new` call in tests needs the new `get_text` parameter. Add a closure that extracts text from the test source string:

```moonbit
fn(i) { src[starts[i]:starts[i] + tokens[i].len] }
```

The exact closure depends on how each test builds its token array. Follow the existing `get_start` pattern.

- [ ] **Step 3: Run `moon check && moon test` in loom/**

```bash
cd loom && moon check && moon test
```

Expected: all 195 tests pass (minus the deleted `cst_token_matches` test).

- [ ] **Step 4: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/core/parser_wbtest.mbt loom/src/factories_wbtest.mbt loom/src/core/pkg.generated.mbti
git commit -m "test(core): update test fixtures for framework-owned token matching"
```

---

### Task 4: Lambda Token — remove payloads

**Files:**
- Modify: `examples/lambda/src/token/token.mbt` — remove `Identifier(String)` and `Integer(Int)` payloads
- Modify: `examples/lambda/src/lambda_spec.mbt` — remove `cst_token_matches`
- Modify: `examples/lambda/src/cst_parser.mbt` — `Identifier(_)` → `Identifier`

- [ ] **Step 1: Remove payloads from Token enum**

In `examples/lambda/src/token/token.mbt`, change:

```moonbit
  Identifier  // variable names (text via token_text_at)
  Integer     // integer literals (value via parse_int on token text)
```

- [ ] **Step 2: Update Show impl**

In `examples/lambda/src/token/token.mbt`, change:

```moonbit
      Identifier => "<ident>"
      Integer => "<int>"
```

- [ ] **Step 3: Update cst_parser.mbt — remove wildcards**

In `examples/lambda/src/cst_parser.mbt`, replace all occurrences:
- `@token.Identifier(_)` → `@token.Identifier`
- `@token.Integer(_)` → `@token.Integer`

- [ ] **Step 4: Remove `cst_token_matches` from lambda_spec.mbt**

In `examples/lambda/src/lambda_spec.mbt`:
- Delete the `cst_token_matches` function (lines 22-44)
- Remove `cst_token_matches~` from the LanguageSpec constructor call

- [ ] **Step 5: Run `moon check` in examples/lambda/**

```bash
cd examples/lambda && moon check
```

Expected: errors in lexer.mbt (still produces `Identifier(string)`) and test files. Fix in next steps.

- [ ] **Step 6: Commit**

```bash
cd examples/lambda && moon info && moon fmt
git add src/token/token.mbt src/lambda_spec.mbt src/cst_parser.mbt
git commit -m "refactor(lambda): Token enum drops Identifier/Integer payloads"
```

---

### Task 5: Lambda lexer — eliminate string accumulator

**Files:**
- Modify: `examples/lambda/src/lexer/lexer.mbt:24-38` — rewrite `read_identifier`
- Modify: `examples/lambda/src/lexer/lexer.mbt:41-52` — rewrite `read_number`
- Modify: `examples/lambda/src/lexer/lexer.mbt:175-194` — update callsites

- [ ] **Step 1: Rewrite `read_identifier`**

Replace the recursive string-accumulating function:

```moonbit
fn read_identifier(input : String, start : Int) -> Int {
  let mut pos = start
  while pos < input.length() {
    let code = input.code_unit_at(pos).to_int()
    if is_alphabet(code) || is_numeric(code) {
      pos = pos + 1
    } else {
      break
    }
  }
  pos
}
```

- [ ] **Step 2: Rewrite `read_number`**

Replace the recursive accumulating function:

```moonbit
fn read_number(input : String, start : Int) -> Int {
  let mut pos = start
  while pos < input.length() {
    let code = input.code_unit_at(pos).to_int()
    if is_numeric(code) {
      pos = pos + 1
    } else {
      break
    }
  }
  pos
}
```

- [ ] **Step 3: Update identifier callsite**

In `examples/lambda/src/lexer/lexer.mbt`, replace the identifier branch (~line 175-188):

```moonbit
    Some(c) if is_alphabet(c.to_int()) => {
      let end_pos = read_identifier(input, pos)
      let len = end_pos - pos
      let text : StringView = input[pos:end_pos]
      let token = match text {
        "if" => @token.Token::If
        "then" => @token.Token::Then
        "else" => @token.Token::Else
        "let" => @token.Token::Let
        "in" => @token.Token::In
        _ => @token.Token::Identifier
      }
      @core.LexStep::Produced(
        @core.TokenInfo::new(token, len),
        next_offset=end_pos,
      )
    }
```

- [ ] **Step 4: Update number callsite**

Replace the number branch (~line 190-195):

```moonbit
    Some(c) if is_numeric(c.to_int()) => {
      let end_pos = read_number(input, pos)
      let len = end_pos - pos
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Integer, len),
        next_offset=end_pos,
      )
    }
```

- [ ] **Step 5: Run `moon check` in examples/lambda/**

```bash
cd examples/lambda && moon check
```

Expected: errors in test files referencing old Token constructors.

- [ ] **Step 6: Commit**

```bash
cd examples/lambda && moon info && moon fmt
git add src/lexer/lexer.mbt
git commit -m "refactor(lambda): lexer returns position, no string accumulation"
```

---

### Task 6: Lambda test updates

**Files:**
- Modify: `examples/lambda/src/lexer/lexer_test.mbt` — update token assertions
- Modify: `examples/lambda/src/*_test.mbt` — update all `Identifier("x")` → `Identifier`, `Integer(42)` → `Integer`

- [ ] **Step 1: Update lexer tests**

Replace all occurrences in test files:
- `Token::Identifier("...")` → `Token::Identifier`
- `@token.Identifier("...")` → `@token.Identifier`
- `Token::Integer(N)` → `Token::Integer`
- `@token.Integer(N)` → `@token.Integer`

- [ ] **Step 2: Update snapshot tests**

```bash
cd examples/lambda && moon test --update
```

Review updated snapshots to ensure they match expected output.

- [ ] **Step 3: Run full test suite**

```bash
cd examples/lambda && moon check && moon test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
cd examples/lambda && moon info && moon fmt
git add -A
git commit -m "test(lambda): update tests for payload-free Token enum"
```

---

### Task 7: JSON Token — remove payloads and simplify lexer

**Files:**
- Modify: `examples/json/src/token.mbt` — remove `StringLit(String)` and `NumberLit(String)` payloads
- Modify: `examples/json/src/lexer.mbt` — string/number readers return position
- Modify: `examples/json/src/json_spec.mbt` — remove `cst_token_matches`
- Modify: `examples/json/src/cst_parser.mbt` — `StringLit(_)` → `StringLit`
- Modify: `examples/json/src/*_test.mbt` — update assertions

- [ ] **Step 1: Remove payloads from JSON Token enum**

In `examples/json/src/token.mbt`:

```moonbit
  StringLit  // string literal (text via token_text_at)
  NumberLit  // number literal (text via token_text_at)
```

Update `Show` impl:

```moonbit
      StringLit => "<string>"
      NumberLit => "<number>"
```

- [ ] **Step 2: Update JSON lexer**

In `examples/json/src/lexer.mbt`, update string and number reading to return `(end_pos, len)` instead of accumulated text. Change callsites to use `StringLit` / `NumberLit` without payload.

- [ ] **Step 3: Remove `cst_token_matches` from json_spec.mbt**

Delete the `cst_token_matches` function and remove it from the LanguageSpec constructor.

- [ ] **Step 4: Update cst_parser.mbt**

Replace all `StringLit(_)` → `StringLit`, `NumberLit(_)` → `NumberLit`.

- [ ] **Step 5: Update tests and snapshots**

```bash
cd examples/json && moon test --update
```

- [ ] **Step 6: Run full test suite**

```bash
cd examples/json && moon check && moon test
```

Expected: all 72 tests pass.

- [ ] **Step 7: Commit**

```bash
cd examples/json && moon info && moon fmt
git add -A
git commit -m "refactor(json): Token drops payloads, lexer simplified"
```

---

### Task 8: Verification and cleanup

**Files:**
- Modify: `docs/api/api-contract.md` — update LanguageSpec section
- Modify: `docs/README.md` — if archiving the plan

- [ ] **Step 1: Run all test suites**

```bash
cd seam && moon test
cd ../loom && moon test
cd ../examples/lambda && moon test
cd ../examples/json && moon test
```

Expected: seam 162, loom ~194 (one test deleted), lambda 410, json 72.

- [ ] **Step 2: Run benchmarks**

```bash
cd examples/lambda && moon bench --release -p dowdiness/lambda/benchmarks -f zero_copy_benchmark.mbt
```

Expected: no regression. Possible improvement from fewer Token allocations.

- [ ] **Step 3: Update API contract**

In `docs/api/api-contract.md`, remove `cst_token_matches` from the LanguageSpec section. Note that token matching is now framework-internal.

- [ ] **Step 4: Run docs check**

```bash
bash check-docs.sh
```

- [ ] **Step 5: Final commit**

```bash
git add docs/
git commit -m "docs: update API contract for framework-owned token matching"
```
