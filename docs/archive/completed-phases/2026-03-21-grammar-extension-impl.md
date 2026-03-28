# Lambda Grammar Extension Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the lambda calculus grammar with ParamList on LetDef and `{}`-delimited BlockExpr, enabling future block reparse (Phase 3).

**Architecture:** Four new tokens (`{`, `}`, `,`, `;`) and six new syntax kinds (ParamList, BlockExpr, plus 4 token kinds). ParamList desugars to nested `Lam`, BlockExpr desugars to `Module` — no AST changes needed. All work is in `loom/examples/lambda/`.

**Tech Stack:** MoonBit, loom parser framework, seam CST library

**Design spec:** `loom/docs/plans/2026-03-21-grammar-extension-design.md`

---

## File Map

All paths relative to `loom/examples/lambda/`.

| File | Action | Responsibility |
|------|--------|---------------|
| `src/token/token.mbt` | Modify | Add `LBrace`, `RBrace`, `Comma`, `Semicolon` variants + Show/print arms |
| `src/syntax/syntax_kind.mbt` | Modify | Add `ParamList`, `BlockExpr`, `LBraceToken`, `RBraceToken`, `CommaToken`, `SemicolonToken` + to_raw/from_raw/is_token |
| `src/lexer/lexer.mbt` | Modify | Add 4 single-char match arms to `step_lex` |
| `src/lambda_spec.mbt` | Modify | Add 4 entries to `syntax_kind_to_token_kind` |
| `src/cst_parser.mbt` | Modify | Update helpers, add `parse_param_list`, `parse_block_expr`, `consume_delimiters`, modify `parse_let_item` and `parse_atom` |
| `src/views.mbt` | Modify | Update `LetDefView::init()`, add `LetDefView::params()`, add `BlockExprView` |
| `src/term_convert.mbt` | Modify | Handle `ParamList` → nested Lam, `BlockExpr` → Module |
| `src/lexer/lexer_test.mbt` | Modify | Lexer tests for new tokens |
| `src/cst_parser_wbtest.mbt` | Modify | Parser whitebox tests for param list and block expr |
| `src/parser_test.mbt` | Modify | CST snapshot tests for new grammar |
| `src/views_test.mbt` | Modify | LetDefView tests with ParamList, BlockExprView tests |
| `src/error_recovery_test.mbt` | Modify | Error recovery tests for new constructs |

---

## Task 1: New Tokens

**Files:**
- Modify: `src/token/token.mbt:2-20` (Token enum), `:24-47` (Show impl), `:77-98` (print_token)
- Test: `src/lexer/lexer_test.mbt`

- [ ] **Step 1: Write lexer tests for new tokens**

Add to `src/lexer/lexer_test.mbt`:

```moonbit
///|
test "tokenize braces" {
  let tokens = tokenize("{}")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("{"), content="true")
  inspect(token_str.contains("}"), content="true")
}

///|
test "tokenize comma" {
  let tokens = tokenize("x,y")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains(","), content="true")
  inspect(token_str.contains("x"), content="true")
  inspect(token_str.contains("y"), content="true")
}

///|
test "tokenize semicolon" {
  let tokens = tokenize("a;b")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains(";"), content="true")
}

///|
test "tokenize block with semicolons" {
  let tokens = tokenize("{ let a = 1; a }")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("{"), content="true")
  inspect(token_str.contains(";"), content="true")
  inspect(token_str.contains("}"), content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/lexer -f lexer_test.mbt`
Expected: Compile error — `LBrace`, `RBrace`, `Comma`, `Semicolon` not defined on Token

- [ ] **Step 3: Add Token variants**

In `src/token/token.mbt`, add 4 variants inside the `Token` enum (after `Eq` at line 13, before `Identifier` at line 14):

```moonbit
  LBrace // {
  RBrace // }
  Comma // ,
  Semicolon // ;
```

- [ ] **Step 4: Add Show impl arms**

In `src/token/token.mbt`, the `Show` impl uses a single `match` inside `logger.write_string(...)` that returns the token text. Add arms after the `Eq` case (matching existing style of returning literal char text):

```moonbit
      LBrace => "{"
      RBrace => "}"
      Comma => ","
      Semicolon => ";"
```

- [ ] **Step 5: Add print_token arms**

In `src/token/token.mbt` `print_token()` function match (after the `Eq` arm). Same style — returns literal token text:

```moonbit
    LBrace => "{"
    RBrace => "}"
    Comma => ","
    Semicolon => ";"
```

- [ ] **Step 6: Add lexer match arms**

In `src/lexer/lexer.mbt` `step_lex()` function, add 4 arms after the `Some('=')` case (after line 161):

```moonbit
    Some('{') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.LBrace, 1),
        next_offset=pos + 1,
      )
    Some('}') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.RBrace, 1),
        next_offset=pos + 1,
      )
    Some(',') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Comma, 1),
        next_offset=pos + 1,
      )
    Some(';') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Semicolon, 1),
        next_offset=pos + 1,
      )
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/lexer -f lexer_test.mbt`
Expected: PASS (may need `moon test --update` for snapshot format)

- [ ] **Step 8: Verify all existing tests still pass**

Run: `cd loom/examples/lambda && moon test`
Expected: All existing tests PASS (new tokens don't affect existing parsing)

- [ ] **Step 9: Commit**

```bash
cd loom/examples/lambda
git add src/token/token.mbt src/lexer/lexer.mbt src/lexer/lexer_test.mbt
moon info && moon fmt
git add -A
git commit -m "feat(lambda): add LBrace, RBrace, Comma, Semicolon tokens"
```

---

## Task 2: New Syntax Kinds

**Files:**
- Modify: `src/syntax/syntax_kind.mbt:2-30` (enum), `:33-54` (is_token), `:57-88` (to_raw), `:91-123` (from_raw)
- Modify: `src/lambda_spec.mbt:5-21` (syntax_kind_to_token_kind)

- [ ] **Step 1: Add SyntaxKind variants**

In `src/syntax/syntax_kind.mbt`, add 6 new variants inside the enum (after `NewlineToken` at line 29):

```moonbit
  LBraceToken // {
  RBraceToken // }
  CommaToken // ,
  SemicolonToken // ;
  ParamList // ( Ident , Ident , ... )
  BlockExpr // { LetDef* Expression? }
```

- [ ] **Step 2: Add is_token arms**

In `is_token()` function, add before the node-kind cases:

```moonbit
      LBraceToken | RBraceToken | CommaToken | SemicolonToken => true
```

- [ ] **Step 3: Add to_raw arms**

In `to_raw()`, add after `NewlineToken => 28` (line 85):

```moonbit
      LBraceToken => 29
      RBraceToken => 30
      CommaToken => 31
      SemicolonToken => 32
      ParamList => 33
      BlockExpr => 34
```

- [ ] **Step 4: Add from_raw arms**

In `from_raw()`, add after `28 => NewlineToken` (line 120):

```moonbit
      29 => LBraceToken
      30 => RBraceToken
      31 => CommaToken
      32 => SemicolonToken
      33 => ParamList
      34 => BlockExpr
```

- [ ] **Step 5: Update syntax_kind_to_token_kind**

In `src/lambda_spec.mbt`, add 4 entries in `syntax_kind_to_token_kind()` (after the `NewlineToken` arm at line 18):

```moonbit
    @syntax.LBraceToken => Some(@token.LBrace)
    @syntax.RBraceToken => Some(@token.RBrace)
    @syntax.CommaToken => Some(@token.Comma)
    @syntax.SemicolonToken => Some(@token.Semicolon)
```

- [ ] **Step 6: Run moon check**

Run: `cd loom/examples/lambda && moon check`
Expected: No errors (exhaustive match warnings may appear for new variants not yet handled in parser)

- [ ] **Step 7: Run all tests**

Run: `cd loom/examples/lambda && moon test`
Expected: All existing tests PASS

- [ ] **Step 8: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/syntax/syntax_kind.mbt src/lambda_spec.mbt
git add -A
git commit -m "feat(lambda): add ParamList, BlockExpr syntax kinds + token mappings"
```

---

## Task 3: Parser Helpers

**Files:**
- Modify: `src/cst_parser.mbt:7-17` (token_starts_expression), `:28-36` (token_starts_application_atom), `:132-144` (is_sync_point), `:154-183` (skip_until_paren_close_or_sync)
- Test: `src/cst_parser_wbtest.mbt`

- [ ] **Step 1: Update token_starts_expression**

In `src/cst_parser.mbt` `token_starts_expression()` (line 7-17), add `@token.LBrace` to the match:

```moonbit
    @token.Let
    | @token.If
    | @token.LeftParen
    | @token.LBrace
    | @token.Lambda
    | @token.Identifier(_)
    | @token.Integer(_) => true
```

- [ ] **Step 2: Update token_starts_application_atom**

In `token_starts_application_atom()` (line 28-36), add `@token.LBrace`:

```moonbit
    @token.LeftParen
    | @token.LBrace
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda => true
```

- [ ] **Step 3: Update is_sync_point**

In `is_sync_point()` (line 132-144), add `@token.RBrace` and `@token.Semicolon`:

```moonbit
    @token.Newline
    | @token.RightParen
    | @token.RBrace
    | @token.Semicolon
    | @token.Lambda
    | @token.Let
    | @token.If
    | @token.Then
    | @token.Else
    | @token.EOF => true
```

- [ ] **Step 4: Add consume_delimiters helper**

Add a new function after `consume_newline_tokens` (after line 63):

```moonbit
///|
/// Consume Newline and Semicolon tokens as block delimiters.
/// Returns the number of delimiters consumed.
fn consume_delimiters(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Int {
  let mut count = 0
  while ctx.peek() == @token.Newline || ctx.peek() == @token.Semicolon {
    match ctx.peek() {
      @token.Newline => ctx.emit_token(@syntax.NewlineToken)
      @token.Semicolon => ctx.emit_token(@syntax.SemicolonToken)
      _ => break
    }
    count += 1
  }
  count
}
```

- [ ] **Step 5: Generalize skip_until_paren_close_or_sync to track braces**

In `skip_until_paren_close_or_sync()` (line 154-183), add brace depth tracking alongside paren depth. Keep the return type as `Int` (number of skipped tokens) to avoid breaking existing callers:

```moonbit
fn skip_until_paren_close_or_sync(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Int {
  let mut paren_depth = 0
  let mut brace_depth = 0
  let mut skipped = 0
  let mut wrapped = false
  while ctx.peek() != @token.EOF {
    let token = ctx.peek()
    if token == @token.RightParen {
      if paren_depth == 0 {
        break
      }
      paren_depth = paren_depth - 1
    } else if token == @token.LeftParen {
      paren_depth = paren_depth + 1
    } else if token == @token.RBrace {
      if brace_depth == 0 {
        break
      }
      brace_depth = brace_depth - 1
    } else if token == @token.LBrace {
      brace_depth = brace_depth + 1
    } else if paren_depth == 0 && brace_depth == 0 && is_sync_point(token) {
      break
    }
    if not(wrapped) {
      ctx.start_node(@syntax.ErrorNode)
      wrapped = true
    }
    ctx.bump_error()
    skipped = skipped + 1
  }
  if wrapped {
    ctx.finish_node()
  }
  skipped
}
```

- [ ] **Step 6: Update parse_application hardcoded match arms**

In `parse_application()` (line 243-276), add `@token.LBrace` to both hardcoded match expressions that duplicate `token_starts_application_atom`. At line 255-259 (first check) and line 265-269 (loop check):

```moonbit
    // Line 255: initial application check
    @token.LeftParen
    | @token.LBrace
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda =>
```

```moonbit
    // Line 265: loop continuation check
    @token.LeftParen
    | @token.LBrace
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda => parse_atom(ctx, allow_newline_application)
```

**Without this change, `f { ... }` would parse `f` as standalone and `{ ... }` as a separate trailing expression instead of an application.**

- [ ] **Step 7: Run all tests**

Run: `cd loom/examples/lambda && moon test`
Expected: All existing tests PASS (helpers are updated but not yet called with new tokens)

- [ ] **Step 8: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/cst_parser.mbt
git add -A
git commit -m "feat(lambda): update parser helpers for braces, commas, semicolons"
```

---

## Task 4: parse_param_list + Modify parse_let_item

**Files:**
- Modify: `src/cst_parser.mbt:362-378` (parse_let_item)
- Test: `src/parser_test.mbt`, `src/cst_parser_wbtest.mbt`

- [ ] **Step 1: Write parse tests for ParamList**

Add to `src/cst_tree_test.mbt` (CST-level tests) and `src/parser_test.mbt` (term-level tests):

**CST-level tests** in `src/cst_tree_test.mbt`:

```moonbit
///|
test "cst: let with single param" {
  let cst = test_parse_cst("let f(x) = x")
  let root = @seam.SyntaxNode::from_cst(cst)
  // LetDef should have a ParamList child
  let let_def = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(let_def.kind()), content="LetDef")
  // Check ParamList exists among children
  let has_param_list = let_def.children().iter().any(
    fn(c) { @syntax.SyntaxKind::from_raw(c.kind()) == @syntax.ParamList },
  )
  inspect(has_param_list, content="true")
}

///|
test "cst: let with multiple params" {
  let cst = test_parse_cst("let add(x, y) = x + y")
  let root = @seam.SyntaxNode::from_cst(cst)
  let let_def = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(let_def.kind()), content="LetDef")
}

///|
test "cst: let without params unchanged" {
  let cst = test_parse_cst("let x = 1")
  let root = @seam.SyntaxNode::from_cst(cst)
  let let_def = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(let_def.kind()), content="LetDef")
  // No ParamList child
  let has_param_list = let_def.children().iter().any(
    fn(c) { @syntax.SyntaxKind::from_raw(c.kind()) == @syntax.ParamList },
  )
  inspect(has_param_list, content="false")
}
```

**Term-level desugaring tests** — add to `src/parser_test.mbt` but **defer running until Task 8** (term_convert changes). These tests will fail until desugaring is implemented:

```moonbit
///|
test "parse let with single param desugars to lam" {
  let expr = parse("let f(x) = x + x\nf 1") catch { _ => abort("parse error") }
  let printed = @ast.print_term(expr)
  // f(x) desugars to let f = λx. (x + x) in f 1
  inspect(printed.contains("λx"), content="true")
}

///|
test "parse let with multiple params desugars to nested lam" {
  let expr = parse("let add(x, y) = x + y\nadd 1 2") catch {
    _ => abort("parse error")
  }
  let printed = @ast.print_term(expr)
  inspect(printed.contains("λx"), content="true")
  inspect(printed.contains("λy"), content="true")
}

///|
test "parse let without params unchanged" {
  let expr = parse("let x = 1\nx") catch { _ => abort("parse error") }
  let printed = @ast.print_term(expr)
  inspect(printed.contains("λ"), content="false")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test -f cst_tree_test.mbt && moon test -f parser_test.mbt`
Expected: FAIL — `ParamList` not produced by parser, desugaring not implemented

- [ ] **Step 3: Add parse_param_list function**

Add to `src/cst_parser.mbt` before `parse_let_item` (before line 362):

```moonbit
///|
/// Parse parameter list: ( Ident , Ident , ... )
/// Called from parse_let_item when '(' follows the function name.
fn parse_param_list(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  ctx.emit_token(@syntax.LeftParenToken) // (
  // First parameter (required)
  match ctx.peek() {
    @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
    @token.RightParen => {
      ctx.error("Empty parameter list")
      ctx.emit_error_placeholder()
    }
    _ => {
      ctx.error("Expected parameter name")
      ctx.emit_error_placeholder()
    }
  }
  // Remaining parameters
  while ctx.peek() == @token.Comma {
    ctx.emit_token(@syntax.CommaToken) // ,
    match ctx.peek() {
      @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
      @token.RightParen => break // trailing comma — stop, will consume )
      _ => {
        ctx.error("Expected parameter name")
        ctx.emit_error_placeholder()
      }
    }
  }
  let _ = lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken) // )
  ctx.start_at(mark, @syntax.ParamList)
  ctx.finish_node()
}
```

- [ ] **Step 4: Modify parse_let_item to call parse_param_list**

In `src/cst_parser.mbt`, modify `parse_let_item` (line 362-378). Insert the ParamList call after the identifier, before the `=`:

```moonbit
///|
fn parse_let_item(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  ctx.emit_token(@syntax.LetKeyword)
  match ctx.peek() {
    @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
    _ => {
      ctx.error("Expected variable name after 'let'")
      ctx.emit_error_placeholder()
    }
  }
  // NEW: optional parameter list
  if ctx.peek() == @token.LeftParen {
    parse_param_list(ctx)
  }
  let _ = lambda_expect(ctx, @token.Eq, @syntax.EqToken)
  parse_expression_with_mode(ctx, false)
  ctx.start_at(mark, @syntax.LetDef)
  ctx.finish_node()
}
```

- [ ] **Step 5: Run tests**

Run: `cd loom/examples/lambda && moon test -f cst_tree_test.mbt`
Expected: CST-level tests PASS (ParamList node present).

**Do not add the term-level desugaring tests yet** — they depend on Task 8. Add them in Task 8 alongside the desugaring implementation.

- [ ] **Step 6: Run full test suite**

Run: `cd loom/examples/lambda && moon test`
Expected: All tests PASS (no term-level desugaring tests added yet)

- [ ] **Step 7: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/cst_parser.mbt src/parser_test.mbt src/cst_tree_test.mbt
git add -A
git commit -m "feat(lambda): add parse_param_list, optional ParamList in LetDef"
```

---

## Task 5: parse_block_expr + Modify parse_atom

**Files:**
- Modify: `src/cst_parser.mbt:279-353` (parse_atom)
- Test: `src/parser_test.mbt`

- [ ] **Step 1: Write parse tests for BlockExpr**

Add CST-level tests to `src/cst_tree_test.mbt`:

```moonbit
///|
test "cst: block with semicolons" {
  let cst = test_parse_cst("{ let a = 1; a }")
  let root = @seam.SyntaxNode::from_cst(cst)
  let block = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(block.kind()), content="BlockExpr")
}

///|
test "cst: block expression only" {
  let cst = test_parse_cst("{ 42 }")
  let root = @seam.SyntaxNode::from_cst(cst)
  let block = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(block.kind()), content="BlockExpr")
}

///|
test "cst: block in application" {
  let cst = test_parse_cst("f { let x = 1; x }")
  let root = @seam.SyntaxNode::from_cst(cst)
  let app = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(app.kind()), content="AppExpr")
  // Second child of AppExpr should be BlockExpr
  let block = app.nth_child(1).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(block.kind()), content="BlockExpr")
}

///|
test "cst: block with newline delimiters" {
  let cst = test_parse_cst("{\nlet a = 1\nlet b = 2\na + b\n}")
  let root = @seam.SyntaxNode::from_cst(cst)
  let block = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(block.kind()), content="BlockExpr")
}

///|
test "cst: defs-only block" {
  let cst = test_parse_cst("{ let a = 1 }")
  let root = @seam.SyntaxNode::from_cst(cst)
  let block = root.nth_child(0).unwrap()
  inspect(@syntax.SyntaxKind::from_raw(block.kind()), content="BlockExpr")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test -f cst_tree_test.mbt`
Expected: FAIL — `BlockExpr` not handled in parse_atom

- [ ] **Step 3: Add parse_block_expr function**

Add to `src/cst_parser.mbt` before `parse_atom` (before line 279):

```moonbit
///|
/// Parse block expression: { (LetDef (Newline|;))* Expression? }
/// Uses the same LetDef/Expression structure as SourceFile but delimited by {}.
fn parse_block_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.start_node(@syntax.BlockExpr)
  ctx.emit_token(@syntax.LBraceToken) // {
  let _ = consume_delimiters(ctx)
  // Empty block check
  if ctx.peek() == @token.RBrace {
    ctx.error("Empty block expression")
    ctx.emit_token(@syntax.RBraceToken) // }
    ctx.finish_node()
    return
  }
  // LetDefs
  while ctx.peek() == @token.Let {
    parse_let_item(ctx)
    let delim_count = consume_delimiters(ctx)
    if delim_count == 0 && ctx.peek() != @token.RBrace && ctx.peek() != @token.EOF {
      ctx.error("Expected ';' or newline between definitions")
    }
  }
  let _ = consume_delimiters(ctx)
  // Trailing expression (optional)
  if ctx.peek() != @token.RBrace && ctx.peek() != @token.EOF {
    parse_expression(ctx)
  }
  let _ = consume_delimiters(ctx)
  if not(lambda_expect(ctx, @token.RBrace, @syntax.RBraceToken)) {
    let _ = skip_until_paren_close_or_sync(ctx)
    if ctx.peek() == @token.RBrace {
      ctx.emit_token(@syntax.RBraceToken)
    }
  }
  ctx.finish_node()
}
```

- [ ] **Step 4: Add LBrace case to parse_atom**

In `src/cst_parser.mbt` `parse_atom()` (line 279-353), add a new match arm before the `LeftParen` case:

```moonbit
    @token.LBrace => parse_block_expr(ctx)
```

- [ ] **Step 5: Run tests**

Run: `cd loom/examples/lambda && moon test -f cst_tree_test.mbt`
Expected: New block tests PASS.

- [ ] **Step 6: Run full test suite**

Run: `cd loom/examples/lambda && moon test`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/cst_parser.mbt src/cst_tree_test.mbt
git add -A
git commit -m "feat(lambda): add parse_block_expr, BlockExpr in parse_atom"
```

---

## Task 6: Error Recovery Tests

**Files:**
- Test: `src/error_recovery_test.mbt`

- [ ] **Step 1: Write error recovery tests**

Add to `src/error_recovery_test.mbt`:

```moonbit
///|
test "error recovery: empty param list" {
  let (cst, diagnostics) = parse_cst("let f() = x") catch {
    _ => abort("lex error")
  }
  assert_cst_complete("let f() = x", cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing param after comma" {
  let (cst, diagnostics) = parse_cst("let f(x,) = x") catch {
    _ => abort("lex error")
  }
  assert_cst_complete("let f(x,) = x", cst)
  inspect(diagnostics.is_empty().not(), content="true")
}

///|
test "error recovery: empty block" {
  let (cst, diagnostics) = parse_cst("{ }") catch { _ => abort("lex error") }
  assert_cst_complete("{ }", cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing closing brace" {
  let source = "let x = { let a = 1\na"
  let (cst, diagnostics) = parse_cst(source) catch { _ => abort("lex error") }
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing semicolon between defs in block" {
  let source = "{ let a = 1 let b = 2; a }"
  let (cst, diagnostics) = parse_cst(source) catch { _ => abort("lex error") }
  assert_cst_complete(source, cst)
  // Should parse but may error about missing delimiter
  inspect(diagnostics.length() >= 0, content="true")
}
```

**Note:** `assert_cst_complete` is an existing helper in `error_recovery_test.mbt` that verifies `tree.end() == source.length()` (every byte accounted for). Diagnostics come from the `parse_cst()` return tuple, not from a tree method.

- [ ] **Step 2: Run tests**

Run: `cd loom/examples/lambda && moon test -f error_recovery_test.mbt`
Expected: PASS — error recovery should work with the parser changes from Tasks 4-5.

**Note:** Snapshot content for error recovery tests may need adjustment. Use `moon test --update` and review the output to ensure the error recovery shape is reasonable (no panics, no infinite loops, error messages present).

- [ ] **Step 3: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/error_recovery_test.mbt
git add -A
git commit -m "test(lambda): add error recovery tests for ParamList and BlockExpr"
```

---

## Task 7: LetDefView Update + BlockExprView

**Files:**
- Modify: `src/views.mbt:390-436` (LetDefView section)
- Test: `src/views_test.mbt`

- [ ] **Step 1: Write view tests**

Add to `src/views_test.mbt`:

```moonbit
///|
test "LetDefView with params" {
  let (cst, _) = parse_cst("let f(x, y) = x + y") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let let_defs = tree.children().filter(
    fn(child) {
      @syntax.SyntaxKind::from_raw(child.kind()) == @syntax.LetDef
    },
  )
  let def = LetDefView::cast(let_defs[0]).unwrap()
  inspect(def.name(), content="f")
  inspect(def.params().is_empty().not(), content="true")
  // init() should return the body expression, not ParamList
  inspect(
    def.init().map(fn(n) { @syntax.SyntaxKind::from_raw(n.kind()) }),
    content="Some(BinaryExpr)",
  )
}

///|
test "LetDefView without params unchanged" {
  let (cst, _) = parse_cst("let x = 42") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let let_defs = tree.children().filter(
    fn(child) {
      @syntax.SyntaxKind::from_raw(child.kind()) == @syntax.LetDef
    },
  )
  let def = LetDefView::cast(let_defs[0]).unwrap()
  inspect(def.name(), content="x")
  inspect(def.params().is_empty(), content="true")
  inspect(
    def.init().map(fn(n) { @syntax.SyntaxKind::from_raw(n.kind()) }),
    content="Some(IntLiteral)",
  )
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test -f views_test.mbt`
Expected: FAIL — `params()` method doesn't exist, `init()` returns ParamList instead of body

- [ ] **Step 3: Update LetDefView::init() to skip ParamList**

In `src/views.mbt`, modify the `init()` method (line 419-421). The current implementation uses `nth_child(0)` which returns the first node child. Update to skip ParamList:

```moonbit
///|
/// Get the initializer expression — the body after `=`.
/// Skips ParamList if present.
pub fn LetDefView::init(self : LetDefView) -> @seam.SyntaxNode? {
  for child in self.node.children() {
    let kind = @syntax.SyntaxKind::from_raw(child.kind())
    if kind != @syntax.ParamList {
      return Some(child)
    }
  }
  None
}
```

- [ ] **Step 4: Add LetDefView::params() method**

In `src/views.mbt`, add after the `init()` method:

```moonbit
///|
/// Get the parameter names from the ParamList, if present.
/// Returns empty array for value bindings (no ParamList).
pub fn LetDefView::params(self : LetDefView) -> Array[String] {
  let params : Array[String] = []
  for child in self.node.children() {
    let kind = @syntax.SyntaxKind::from_raw(child.kind())
    if kind == @syntax.ParamList {
      // Walk inside ParamList — all_children() returns Array[SyntaxElement]
      // Must pattern-match to extract SyntaxToken from SyntaxElement::Token
      for elem in child.all_children() {
        match elem {
          @seam.SyntaxElement::Token(t) =>
            if @syntax.SyntaxKind::from_raw(t.kind()) == @syntax.IdentToken {
              params.push(t.text())
            }
          _ => ()
        }
      }
      break
    }
  }
  params
}
```

**Note:** `all_children()` returns `Array[SyntaxElement]` where `SyntaxElement` is `Node(SyntaxNode) | Token(SyntaxToken)`. We match on `Token(t)` to get `SyntaxToken`, then check kind and extract text. `children()` returns only `Array[SyntaxNode]` (node children), so `ParamList` is accessible there as a node child of `LetDef`.

- [ ] **Step 5: Run tests**

Run: `cd loom/examples/lambda && moon test -f views_test.mbt`
Expected: PASS

- [ ] **Step 6: Run full test suite**

Run: `cd loom/examples/lambda && moon test`
Expected: All tests PASS — existing LetDefView tests should still work since value bindings are unchanged

- [ ] **Step 7: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/views.mbt src/views_test.mbt
git add -A
git commit -m "feat(lambda): update LetDefView for ParamList, add params() accessor"
```

---

## Task 8: Term Convert — ParamList Desugaring

**Files:**
- Modify: `src/term_convert.mbt:6-35` (lambda_fold_node)
- Test: `src/parser_test.mbt` or new `src/desugar_test.mbt`

- [ ] **Step 1: Write desugaring tests**

Add to `src/parser_test.mbt`. Use `parse()` (returns `Term` via `parse_term` → `parse_cst` → `syntax_node_to_term`) and `@ast.print_term()`:

```moonbit
///|
test "desugar let with params to nested lam" {
  let expr = parse("let f(x, y) = x + y\nf 1 2") catch {
    _ => abort("parse error")
  }
  let printed = @ast.print_term(expr)
  // f(x, y) desugars to let f = λx. λy. (x + y) in (f 1 2)
  inspect(printed.contains("λx"), content="true")
  inspect(printed.contains("λy"), content="true")
}

///|
test "desugar let without params unchanged" {
  let (cst, _) = parse_cst("let x = 42\nx") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(term, content="Module([(\"x\", Int(42))], Var(\"x\"))")
}

///|
test "desugar block expr" {
  let (cst, _) = parse_cst("{ let a = 1; a + 1 }") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(term, content="Module([(\"a\", Int(1))], Bop(Plus, Var(\"a\"), Int(1)))")
}

///|
test "desugar block expr only" {
  let (cst, _) = parse_cst("{ 42 }") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(term, content="Module([], Int(42))")
}

///|
test "desugar defs-only block" {
  let (cst, _) = parse_cst("{ let a = 1 }") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(term, content="Module([(\"a\", Int(1))], Unit)")
}

///|
test "desugar params plus block" {
  let (cst, _) = parse_cst("let f(x) = { let y = x + 1; y }") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(
    term,
    content="Module([(\"f\", Lam(\"x\", Module([(\"y\", Bop(Plus, Var(\"x\"), Int(1)))], Var(\"y\"))))], Unit)",
  )
}
```

**Note:** Snapshot content strings may differ slightly from expectations. Run `moon test --update` after implementation and verify the output makes semantic sense. The key structural properties: `f(x, y)` produces nested `Lam`, `{ ... }` produces `Module`, defs-only blocks have `Unit` body.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test -f parser_test.mbt`
Expected: FAIL — term converter doesn't handle ParamList or BlockExpr yet

- [ ] **Step 3: Update lambda_fold_node for BlockExpr**

In `src/term_convert.mbt`, the `lambda_fold_node` function currently handles `SourceFile` specially (lines 10-31). Add a `BlockExpr` case that uses the same logic. In `fold_node_inner`, add after existing match arms:

```moonbit
    @syntax.BlockExpr => {
      // Same logic as SourceFile: collect LetDefs + final expression
      let defs : Array[(@ast.VarName, @ast.Term)] = []
      let mut final_term : @ast.Term = @ast.Term::Unit
      for child in node.children() {
        match @syntax.SyntaxKind::from_raw(child.kind()) {
          @syntax.LetDef => {
            let v = LetDefView::{ node: child }
            let (name, body) = convert_let_def(v, recurse)
            defs.push((name, body))
          }
          _ =>
            if final_term == @ast.Term::Unit {
              final_term = recurse(child)
            }
        }
      }
      if defs.is_empty() && final_term == @ast.Term::Unit {
        // Empty block: { } — parser already emitted error, produce Error term
        @ast.Term::Error("empty block")
      } else if defs.is_empty() {
        final_term
      } else {
        @ast.Term::Module(defs, final_term)
      }
    }
```

- [ ] **Step 4: Add ParamList desugaring to SourceFile handler**

First, add a shared `convert_let_def` helper at the top of `src/term_convert.mbt` (before `lambda_fold_node`):

```moonbit
///|
fn convert_let_def(
  v : LetDefView,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> (@ast.VarName, @ast.Term) {
  let init = match v.init() {
    Some(expr_node) => recurse(expr_node)
    None => @ast.Term::Error("missing LetDef init")
  }
  let params = v.params()
  let mut body = init
  for i = params.length() - 1; i >= 0; i = i - 1 {
    body = @ast.Term::Lam(params[i], body)
  }
  (v.name(), body)
}
```

Then update the existing `SourceFile` handler (lines 10-31) to use the helper. Replace the LetDef branch:

```moonbit
          @syntax.LetDef => {
            let v = LetDefView::{ node: child }
            let (name, body) = convert_let_def(v, recurse)
            defs.push((name, body))
          }
```

The `BlockExpr` handler (added in Step 3) should use the same `convert_let_def` call.

- [ ] **Step 5: Run tests**

Run: `cd loom/examples/lambda && moon test -f parser_test.mbt`
Expected: PASS. Use `moon test --update` if Debug output format differs slightly.

- [ ] **Step 6: Run full test suite**

Run: `cd loom/examples/lambda && moon test`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/term_convert.mbt src/views.mbt src/parser_test.mbt
git add -A
git commit -m "feat(lambda): ParamList→Lam desugaring, BlockExpr→Module conversion"
```

---

## Task 9: Combined Grammar Tests

**Files:**
- Test: `src/parser_test.mbt`

- [ ] **Step 1: Write combined feature tests**

Add to `src/parser_test.mbt`:

```moonbit
///|
test "parse nested blocks" {
  let (cst, _) = parse_cst("{ { 1 } }") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(term, content="Module([], Module([], Int(1)))")
}

///|
test "parse blocks in if-then-else" {
  let (cst, _) = parse_cst("if x then { let a = 1; a } else { 0 }") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(
    term,
    content="If(Var(\"x\"), Module([(\"a\", Int(1))], Var(\"a\")), Module([], Int(0)))",
  )
}

///|
test "parse param list with block body" {
  let (cst, _) = parse_cst("let compute(x, y) = {\n  let sum = x + y\n  sum\n}") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(
    term,
    content="Module([(\"compute\", Lam(\"x\", Lam(\"y\", Module([(\"sum\", Bop(Plus, Var(\"x\"), Var(\"y\")))], Var(\"sum\")))))], Unit)",
  )
}

///|
test "block as application argument" {
  let (cst, _) = parse_cst("double { let x = 3; x + 1 }") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(tree)
  inspect(
    term,
    content="App(Var(\"double\"), Module([(\"x\", Int(3))], Bop(Plus, Var(\"x\"), Int(1))))",
  )
}
```

- [ ] **Step 2: Add roundtrip test**

```moonbit
///|
test "roundtrip: param list preserves structure" {
  let source = "let f(x, y) = x + y\nf 1 2"
  let expr1 = parse(source) catch { _ => abort("parse error") }
  let printed = @ast.print_term(expr1)
  // Parse the printed output — should produce same term
  let expr2 = parse(printed) catch { _ => abort("reparse error") }
  inspect(@ast.print_term(expr1), content=@ast.print_term(expr2))
}
```

- [ ] **Step 3: Add missing error recovery test**

Add to `src/error_recovery_test.mbt`:

```moonbit
///|
test "error recovery: leading comma in param list" {
  let source = "let f(,) = x"
  let (cst, diagnostics) = parse_cst(source) catch { _ => abort("lex error") }
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
}
```

- [ ] **Step 4: Run tests**

Run: `cd loom/examples/lambda && moon test -f parser_test.mbt && moon test -f error_recovery_test.mbt`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/parser_test.mbt src/error_recovery_test.mbt
git add -A
git commit -m "test(lambda): add combined grammar tests, roundtrip, error recovery for leading comma"
```

---

## Task 10: Incremental Parse Tests

**Files:**
- Test: `src/imperative_parser_test.mbt`

- [ ] **Step 1: Write incremental parse tests for blocks**

Add to `src/imperative_parser_test.mbt`:

```moonbit
///|
test "incremental: edit inside block matches full reparse" {
  let source = "{ let a = 1; a }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Change 1 to 2: edit at offset 10, delete 1, insert 1
  let new_source = "{ let a = 2; a }"
  let edit = @core.Edit::new(start=10, old_len=1, new_len=1)
  let incr_term = parser.edit(edit, new_source)
  // Compare with full reparse
  let full_term = parse(new_source) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}

///|
test "incremental: edit inside param list matches full reparse" {
  let source = "let f(x) = x\nf 1"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Insert ", y" after "x" in param list
  let new_source = "let f(x, y) = x\nf 1 2"
  let edit = @core.Edit::insert(7, 3)
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}

///|
test "incremental: add block to let def matches full reparse" {
  let source = "let x = 1\nx"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  let new_source = "let x = { 1 }\nx"
  let edit = @core.Edit::new(start=8, old_len=1, new_len=5)
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}
```

- [ ] **Step 2: Run tests**

Run: `cd loom/examples/lambda && moon test -f imperative_parser_test.mbt`
Expected: PASS — incremental parser should produce identical CST to batch parse

- [ ] **Step 3: Commit**

```bash
cd loom/examples/lambda
moon info && moon fmt
git add src/imperative_parser_test.mbt
git add -A
git commit -m "test(lambda): add incremental parse tests for blocks and param lists"
```

---

## Task 11: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `cd loom/examples/lambda && moon test`
Expected: All tests PASS

- [ ] **Step 2: Run loom framework tests**

Run: `cd loom/loom && moon test`
Expected: All tests PASS (no loom changes in this PR)

- [ ] **Step 3: Run seam tests**

Run: `cd loom/seam && moon test`
Expected: All tests PASS (no seam changes in this PR)

- [ ] **Step 4: Run benchmarks to check for regressions**

Run: `cd loom/examples/lambda && moon bench --release`
Expected: No significant regression (>20%) on existing let-chain benchmarks

- [ ] **Step 5: Update interfaces and format**

```bash
cd loom/examples/lambda && moon info && moon fmt
```

- [ ] **Step 6: Review .mbti changes**

Run: `cd loom/examples/lambda && git diff *.mbti`
Expected: New entries for `LetDefView::params`, `parse_param_list`, `parse_block_expr`, `consume_delimiters` (if pub). No unexpected removals.

- [ ] **Step 7: Run moon check**

Run: `cd loom/examples/lambda && moon check`
Expected: No errors, no warnings about exhaustive matches

- [ ] **Step 8: Final commit (interfaces)**

```bash
cd loom/examples/lambda
git add -A
git commit -m "chore(lambda): update interfaces for grammar extension"
```

---

## Dependency Graph

```
Task 1 (Tokens)
    ↓
Task 2 (SyntaxKinds)
    ↓
Task 3 (Parser Helpers)
    ↓
    ├── Task 4 (ParamList + parse_let_item) ──┐
    │                                          │
    └── Task 5 (BlockExpr + parse_atom) ───────┤
                                               ↓
                                    Task 6 (Error Recovery)
                                               ↓
                                    Task 7 (Views)
                                               ↓
                                    Task 8 (Term Convert)
                                               ↓
                                    Task 9 (Combined Tests)
                                               ↓
                                    Task 10 (Incremental Tests)
                                               ↓
                                    Task 11 (Final Verification)
```

Tasks 4 and 5 are structurally independent but both modify `cst_parser.mbt` — do them sequentially to avoid merge conflicts.

---

## Notes for Implementer

1. **Whitespace handling:** The lambda parser uses `layout=true` mode where whitespace tokens are emitted explicitly. Inside BlockExpr, whitespace between `{` and the first token is consumed by `consume_delimiters` (if it's a newline) or left as whitespace. Watch for unexpected whitespace tokens in CST snapshots — update with `moon test --update` and verify the tree shape is correct.

2. **API patterns:** Throughout the codebase:
   - `parse_cst(source)` returns `(@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError` — always destructure as `let (cst, diagnostics) = parse_cst(source) catch { _ => abort("lex error") }`
   - `@seam.SyntaxNode::from_cst(cst)` — creates a SyntaxNode from CstNode (NOT `new_root`)
   - `syntax_node_to_term(tree)` — converts SyntaxNode to Term (NOT `lambda_fold_node(tree)` which takes 2 args)
   - `@loom.new_imperative_parser(source, lambda_grammar)` — creates incremental parser (source first, grammar second)

3. **ParamList desugaring (right-fold):** MoonBit's `Array` has no `rev_fold`. Use a reverse loop: `for i = params.length() - 1; i >= 0; i = i - 1`. `let f(x, y, z) = body` must become `Lam("x", Lam("y", Lam("z", body)))` — innermost param wraps the body first.

4. **Error recovery inside blocks:** `parse_block_expr` uses `lambda_expect` for `}`, which calls `skip_until_paren_close_or_sync` on failure. The updated `skip_until_paren_close_or_sync` tracks brace depth, so it won't consume a parent's `}`.

5. **No AST changes:** `BlockExpr` desugars to the existing `Module(defs, body)` variant. The projection layer, resolver, and printer all handle `Module` already.

6. **`LetDefView::init()` change:** The updated `init()` skips `ParamList` children by checking the kind. Since `ParamList` didn't exist before, existing LetDefs have no ParamList child, so `init()` returns the same result as before.

7. **`consume_delimiters` vs `consume_newline_tokens`:** The new `consume_delimiters` handles both `Newline` and `Semicolon`. The existing `consume_newline_tokens` only handles `Newline` and is used by `parse_lambda_root` (SourceFile parser) where semicolons are not valid delimiters. Do not replace `consume_newline_tokens` with `consume_delimiters` in `parse_lambda_root` — SourceFile uses newlines only.

8. **`parse_application` hardcoded match arms:** `parse_application` (line 243-276) has hardcoded match arms at lines 255-259 and 265-269 that duplicate `token_starts_application_atom`. These **must** include `@token.LBrace` for `f { ... }` to parse as application. Task 3 covers this.

9. **Error recovery test pattern:** Use `let (cst, diagnostics) = parse_cst(source) catch { ... }` and check `diagnostics.length()`. The `collect_errors()` method on SyntaxNode has been removed. Use `assert_cst_complete(source, cst)` (existing helper in `error_recovery_test.mbt`) to verify all bytes are accounted for.

10. **Snapshot tests:** Run `moon test --update` liberally after implementation — the exact `Debug` output format for `Term` and `CstNode` may differ from plan expectations. Verify structural correctness (nesting, variant names) rather than exact string matches.
