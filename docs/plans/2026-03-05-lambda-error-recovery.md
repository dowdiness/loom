# Apply Error Recovery Combinators to Lambda Example — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply the recovery combinators from `loom/src/core/recovery.mbt` (`expect`, `skip_until`, `skip_until_balanced`, `node_with_recovery`, `expect_and_recover`) to the lambda calculus example grammar in `examples/lambda/src/`. This serves as the first real-world validation of the combinators and establishes patterns for other grammars.

**Architecture:** Modify the existing lambda grammar functions to use recovery combinators instead of (or in addition to) existing ad-hoc error handling. Add error recovery tests with broken inputs. No new files — changes are to existing grammar/parser files and test files.

**Tech Stack:** MoonBit, `moon` build system.

**Prerequisite:** The error recovery combinators plan (archived at `docs/archive/completed-phases/2026-03-05-loom-error-recovery.md`) is complete. Verify with `cd loom && moon test -p dowdiness/loom/core`.

---

## Task 0: Read and understand the lambda example

> **This task is a reading task — no code changes.**

Before making any changes, read the following files to understand the current grammar structure:

```bash
# List all files in the lambda example
find examples/lambda/src/ -name '*.mbt' | sort

# Key files to read (read in this order):
# 1. Token type and SyntaxKind definitions
# 2. Tokenizer / lexer
# 3. Grammar / parser functions (the parse_root, parse_expr, parse_atom, etc.)
# 4. AST definitions and term_convert (CST → AST conversion)
# 5. Existing tests
# 6. The Grammar definition that wires everything together
```

While reading, identify and note:

1. **The token type** (`@token.Token` enum with variants: `Lambda`, `Dot`, `LeftParen`, `RightParen`, `Plus`, `Minus`, `If`, `Then`, `Else`, `Let`, `In`, `Eq`, `Identifier(String)`, `Integer(Int)`, `Whitespace`, `Newline`, `EOF` — derives `Eq`, manual `Show` impl)
2. **The SyntaxKind type** (`@syntax.SyntaxKind` enum with node kinds like `LambdaExpr`, `AppExpr`, `VarRef`, `LetExpr`, `ParenExpr`, `SourceFile`, `LetDef`, `BinaryExpr`, `IfExpr`, `IntLiteral`, `ErrorNode`, etc.)
3. **The grammar entry point** (`parse_root` or equivalent registered in `LanguageSpec.parse_root`)
4. **Each parse function** and how it currently handles errors (look for `ctx.error(...)`, `ctx.bump_error()`, `ctx.emit_error_placeholder()`)
5. **The `Grammar` definition** (the `let lambda_grammar = Grammar::new(...)` or similar)
6. **Existing error-handling tests** (search for tests with broken input like `"λ"`, `"(λx."`, `"++"`, etc.)

Record these findings in a mental model before proceeding.

### Verification

```bash
cd examples/lambda && moon test
```

Expected: all existing tests pass. Note the test count for regression checking.

---

## Task 1: Replace simple token expectations with `expect`

**Precondition:** Task 0 complete — you know the token type and grammar functions.

This task targets the most common error-handling pattern: checking for a specific token and emitting an error on mismatch.

### Step 1: Find all `ctx.at(Token::X) + ctx.emit_token(Kind::X)` pairs

Search the grammar file(s) for patterns like:

```moonbit
// Pattern A: check + emit, no error on mismatch (crash or silent skip)
if ctx.at(some_token) {
  ctx.emit_token(some_kind)
}

// Pattern B: check + emit + manual error
match ctx.peek() {
  SomeToken => ctx.emit_token(SomeKind)
  _ => {
    ctx.error("expected ...")
    ctx.emit_error_placeholder()
  }
}

// Pattern C: unconditional emit (aborts at EOF)
ctx.emit_token(SomeKind)  // when preceded by an at() check
```

### Step 2: Replace with `expect`

For each occurrence of Pattern B (check + manual error), replace with:

```moonbit
// Before:
match ctx.peek() {
  @token.Dot => ctx.emit_token(@syntax.DotToken)
  _ => {
    ctx.error("expected '.'")
    ctx.emit_error_placeholder()
  }
}

// After:
ctx.expect(@token.Dot, @syntax.DotToken)
```

For Pattern A where error handling is missing, add it via `expect`:

```moonbit
// Before (no error path):
if ctx.at(@token.Dot) {
  ctx.emit_token(@syntax.DotToken)
}
// What happens if not a Dot? Silent failure.

// After:
ctx.expect(@token.Dot, @syntax.DotToken)
// Now: diagnostic + placeholder on mismatch
```

**Important — do NOT replace `lambda_expect`:**

The existing `lambda_expect` helper (in `cst_parser.mbt`) calls `consume_soft_newlines_before_expected(ctx, expected)` before the token check. This handles optional newlines in the grammar. Replacing `lambda_expect` with `ctx.expect()` would **break soft-newline handling**. Instead:
- Use `ctx.expect()` only for **new** error paths that don't need soft newlines
- Keep `lambda_expect` for existing call sites that rely on soft-newline consumption
- Consider creating a `lambda_expect_recover` wrapper if `expect_and_recover` semantics are needed with soft newlines

**Important:** Do NOT replace every `emit_token` call. Keep `emit_token` where the grammar already knows the token matches (e.g. inside a `match ctx.peek()` arm). Only replace where the grammar needs to handle possible mismatch.

### Step 3: Run tests

```bash
cd examples/lambda && moon test
```

Expected: all existing tests pass. Some error message strings in tests may need updating to match the new auto-generated format (`"expected Dot, got Eof"` instead of `"expected '.'"` or similar).

### Step 4: Add tests for `expect` error paths

Append tests for inputs that trigger the new `expect` error paths. The exact inputs depend on the grammar, but typical cases include:

```moonbit
// Missing dot in lambda: "λx x" instead of "λx. x"
// Missing closing paren: "(λx. x"
// Missing 'in' in let: "let x = 1 x"
// Missing '=' in let: "let x 1 in x"
```

For each test, verify:
1. The parser does NOT crash (no abort)
2. A diagnostic is produced with an auto-generated message
3. The CST is complete (the tree text_len equals source length)

### Step 5: Run tests

```bash
cd examples/lambda && moon test
```

Expected: all tests pass including new ones.

---

## Task 2: Add `skip_until` recovery to expression parsing

**Precondition:** Task 1 complete.

This task adds panic-mode recovery to expression-level parse functions.

### Step 1: Identify sync points for the lambda language

Sync points are tokens that reliably indicate the start of a new syntactic construct. For the lambda calculus, these include:

- `RightParen` — end of parenthesized expression
- `In` — end of let binding's value expression
- `Lambda` — start of a new lambda
- `Let` — start of a new let expression
- `If` — start of an if-then-else
- `Then` / `Else` — if-then-else continuation
- `EOF` — end of input

Define a helper function for sync point detection:

```moonbit
// In cst_parser.mbt
fn is_sync_point(t : @token.Token) -> Bool {
  match t {
    RightParen | In | Lambda | Let | If | Then | Else | EOF => true
    _ => false
  }
}
```

### Step 2: Add recovery to the expression parser's error branch

Find the main expression-parsing function (e.g. `parse_expr` or `parse_atom`). If it has a catch-all error branch like:

```moonbit
_ => {
  ctx.error("expected expression")
  ctx.bump_error()  // consumes one token
}
```

Replace with `skip_until`:

```moonbit
_ => {
  ctx.error("expected expression")
  let _ = ctx.skip_until(is_sync_point)
}
```

This recovers more gracefully from multi-token garbage.

### Step 3: Add tests for multi-token error inputs

```moonbit
// Multiple unexpected tokens before a valid expression
// e.g. "++ λx. x" — "++" is garbage, should skip to λ

// Garbage between valid expressions in application position
// e.g. "f ++ g" — "++" should be error, parse should continue

// Garbage at end of input
// e.g. "λx. x ++" — "++" should be an error, not crash
```

### Step 4: Run tests

```bash
cd examples/lambda && moon test
```

Expected: all pass. New tests verify that the parser produces diagnostics but does not crash.

---

## Task 3: Add `skip_until_balanced` for parenthesized expressions

**Precondition:** Task 2 complete.

### Step 1: Find the parenthesized expression parser

Look for the function that handles `(expr)` parsing (e.g. `parse_paren_expr` or a branch in `parse_atom` that matches `LeftParen`).

### Step 2: Add balanced recovery for missing `)`

After parsing the inner expression, if `)` is missing, use `skip_until_balanced` to skip to the matching close paren:

```moonbit
// Inside parse_paren_expr or the LeftParen branch:
ctx.emit_token(@syntax.LeftParenToken)  // consume "("
parse_expr(ctx)                          // parse inner expression

// Instead of just lambda_expect(ctx, RightParen, RightParenToken):
if not(ctx.expect(@token.RightParen, @syntax.RightParenToken)) {
  // RightParen was missing — skip until we find one (respecting nesting)
  ctx.skip_until_balanced(
    t => t == @token.LeftParen,
    t => t == @token.RightParen,
  )
  // Try to consume the RightParen we found
  if ctx.at(@token.RightParen) {
    ctx.emit_token(@syntax.RightParenToken)
  }
}
```

### Step 3: Add tests

```moonbit
// Missing close paren: "(λx. x"
// Extra tokens before close paren: "(λx. x ++ )"
// Nested parens with error: "((λx. x)"  — one ) missing
```

### Step 4: Run tests

```bash
cd examples/lambda && moon test
```

---

## Task 4: Use `node_with_recovery` for top-level constructs

**Precondition:** Task 3 complete.

### Step 1: Find node-level parse functions

Look for calls to `ctx.node(SomeKind, fn() { ... })` in the grammar. These are candidates for `node_with_recovery` when the body can fail.

### Step 2: Convert appropriate `node` calls to `node_with_recovery`

Convert calls where the body has a failure mode:

```moonbit
// Before:
ctx.node(@syntax.LetExpr, () => {
  ctx.emit_token(@syntax.LetKeyword)
  // ... parse binding, '=', value, 'in', body
  // Currently: if something goes wrong, inconsistent error handling
})

// After:
ctx.node_with_recovery(
  @syntax.LetExpr,
  () => {
    ctx.emit_token(@syntax.LetKeyword)
    // Note: Identifier has a payload, so use lambda_expect or manual check
    // ctx.expect won't work for Identifier(String) since payload varies
    if not(ctx.at_identifier()) { // pseudo — check actual identifier handling
      ctx.error("Expected variable name after 'let'")
      ctx.emit_error_placeholder()
      return false
    }
    ctx.emit_token(@syntax.IdentToken)
    let ok_eq = ctx.expect(@token.Eq, @syntax.EqToken)
    if not(ok_eq) { return false }
    parse_expr(ctx)  // value
    let ok_in = ctx.expect(@token.In, @syntax.InKeyword)
    if not(ok_in) { return false }
    parse_expr(ctx)  // body
    true
  },
  is_sync_point,
)
```

**Note on `Identifier(String)`:** The `Identifier` token carries a payload, so `ctx.expect(@token.Identifier(...), ...)` won't work — you'd need to match the exact string. Use a manual `match ctx.peek() { Identifier(_) => ... }` check or the existing pattern from `cst_parser.mbt` for identifier handling.

**Important:** Not all `node` calls should be converted. Only convert those where:
- The body can encounter unexpected tokens
- Recovery makes sense (i.e. there is a meaningful sync point)
- The node represents a complete syntactic construct (not a wrapper like SourceFile)

### Step 3: Add tests

```moonbit
// Malformed let: "let = 1 in x" (missing identifier)
// Malformed let: "let x 1 in x" (missing '=')
// Malformed let: "let x = 1 x" (missing 'in')
// Each should produce a diagnostic and a parseable CST
```

### Step 4: Run tests

```bash
cd examples/lambda && moon test
```

---

## Task 5: Incremental reuse integration test with error recovery

**Precondition:** Task 4 complete.

This task verifies that `ImperativeParser.edit()` works correctly when the CST contains error nodes produced by recovery combinators.

### Step 1: Add test — fix an error by editing

```moonbit
// 1. Parse broken input: "λx x" (missing dot)
//    → CST with error placeholder, diagnostic present
// 2. Apply edit: insert "." at position 2 → "λx. x"
//    → CST should now be clean, no diagnostics
//    → ReuseCursor should reuse undamaged subtrees
test "incremental: fix missing dot by editing" {
  let grammar = lambda_grammar  // the Grammar instance
  let parser = @loom.new_imperative_parser("λx x", grammar)
  let ast1 = parser.parse()
  let diags1 = parser.diagnostics()
  // Should have at least one diagnostic (missing dot)
  inspect(diags1.length() > 0, content="true")

  // Insert "." after "λx"
  let edit = @loom.Edit::new(2, 0, 1) // insert 1 char at position 2
  let ast2 = parser.edit(edit, "λx. x")
  let diags2 = parser.diagnostics()
  inspect(diags2.length(), content="0")
}
```

(Adjust token positions and the grammar variable name to match the actual lambda example.)

### Step 2: Add test — introduce an error by editing

```moonbit
// 1. Parse valid input: "λx. x"
//    → clean CST, no diagnostics
// 2. Apply edit: delete "." at position 2 → "λx x"
//    → CST should contain error recovery artifacts
//    → diagnostics present
test "incremental: introduce error by deleting dot" {
  let grammar = lambda_grammar
  let parser = @loom.new_imperative_parser("λx. x", grammar)
  let _ast1 = parser.parse()
  inspect(parser.diagnostics().length(), content="0")

  let edit = @loom.Edit::new(2, 1, 0) // delete 1 char at position 2
  let _ast2 = parser.edit(edit, "λx x")
  inspect(parser.diagnostics().length() > 0, content="true")
}
```

### Step 3: Add test — edit within an error region

```moonbit
// 1. Parse broken input: "(λx. x" (missing closing paren)
// 2. Apply edit: append ")" at end
//    → error should be resolved
test "incremental: fix missing paren by appending" {
  let grammar = lambda_grammar
  let parser = @loom.new_imperative_parser("(λx. x", grammar)
  let _ast1 = parser.parse()
  inspect(parser.diagnostics().length() > 0, content="true")

  let src = "(λx. x)"
  let edit = @loom.Edit::new(6, 0, 1) // insert ")" at end
  let _ast2 = parser.edit(edit, src)
  inspect(parser.diagnostics().length(), content="0")
}
```

### Step 4: Run tests

```bash
cd examples/lambda && moon test
```

Expected: all pass. The incremental parser correctly handles transitions between error and non-error states.

---

## Task 6: Verify full suite, format, commit

### Step 1: Run lambda and loom test suites separately

```bash
cd examples/lambda && moon test   # lambda module tests
cd loom && moon test              # loom framework tests (separate module)
```

Expected: all tests pass in both modules.

### Step 2: Format and check

```bash
cd examples/lambda && moon fmt && moon check
```

No warnings.

### Step 3: Update interfaces if any signatures changed

```bash
cd examples/lambda && moon info
```

Check the interface diff — grammar file changes are internal, so no public interface changes are expected unless you added public helper functions (like `is_sync_point`).

### Step 4: Commit

From the repo root (`loom/`):

```bash
git add examples/lambda/
git commit -m "feat(examples/lambda): apply error recovery combinators — expect, skip_until, balanced recovery, node_with_recovery"
```

---

## Verification checklist

```bash
cd examples/lambda && moon test && moon check  # lambda module tests + lint
cd loom && moon test && moon check             # loom framework tests + lint (separate module)
```

---

## Design notes for the coding agent

### Token type has Show — verified

The `@token.Token` type has a manual `Show` impl (in `token/token.mbt`) and derives `Eq`. Both constraints required by `expect` and `expect_and_recover` are satisfied. No changes needed.

### `Identifier(String)` cannot use `expect` directly

The `Identifier` variant carries a `String` payload. `ctx.expect(@token.Identifier("x"), ...)` would only match identifiers with that exact name. For identifier expectations, continue using manual `match ctx.peek() { Identifier(_) => ctx.emit_token(...) ... }` patterns or the existing error-handling code in `cst_parser.mbt`.

### `lambda_expect` handles soft newlines — do not replace blindly

The existing `lambda_expect` helper calls `consume_soft_newlines_before_expected(ctx, expected)` before the token check. This is grammar-specific behavior that `ctx.expect()` does not replicate. Keep `lambda_expect` at existing call sites. Use `ctx.expect()` only for new error paths or where soft newlines are irrelevant.

### Do not remove existing error handling prematurely

Some existing error handling may be more nuanced than what the combinators provide. In those cases, keep the existing code and only add combinator-based recovery for cases that are currently unhandled (crash or silent failure). The goal is "strictly better error handling", not "rewrite everything".

### CST completeness invariant

After every parse (including broken inputs), the CST's `text_len` must equal the source string's length in UTF-16 code units (what MoonBit's `String::length()` returns). Every code unit of input must be accounted for in the tree — either as a normal token, a trivia token, or an error token/node. If a test shows `text_len != source.length()`, something is wrong with the recovery logic. Note: `λ` is 1 code unit (U+03BB fits in a single UTF-16 unit), so `"λx. x".length()` is 5.

### The `is_sync_point` function

This function is grammar-specific. For the lambda calculus it should be conservative — only tokens that are unambiguously structural boundaries. Do NOT include `Identifier` as a sync point (it appears everywhere). DO include closing delimiters (`RightParen`), block-starting keywords (`Lambda`, `Let`, `If`), and block-separating keywords (`In`, `Then`, `Else`).

### Incremental tests use code-unit offsets

The offsets in the incremental tests (Task 5) and the `Edit` type use UTF-16 code units — the unit that MoonBit's `String::length()` returns. `λ` (U+03BB) is 1 code unit, so `"λx"` has length 2. Verify positions with `source.length()` before writing edit offsets.

### Order of application

Apply combinators to the **deepest** parse functions first (e.g. `parse_atom`), then work outward (`parse_application` → `parse_expr` → `parse_root`). This ensures inner recovery fires before outer recovery, producing the most precise error localization.
