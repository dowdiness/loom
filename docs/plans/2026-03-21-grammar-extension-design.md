# Lambda Grammar Extension — ParamList + BlockExpr

**Date:** 2026-03-21
**Status:** Draft
**Scope:** loom/examples/lambda (lexer, token, syntax, parser, AST, term_convert, tests)

---

## Goal

Extend the lambda calculus grammar with function parameter lists and block expressions to:
1. Enable block reparse (Phase 3) via `{}`-delimited BlockExpr
2. Provide richer projections for the editor (function definitions vs value bindings)
3. Preserve the lambda calculus identity (curried core, `λ` for anonymous functions)

---

## Grammar

### Current

```ebnf
SourceFile   ::= (LetDef Newline)* Expression?
LetDef       ::= 'let' Identifier '=' Expression
Expression   ::= BinaryOp
BinaryOp     ::= Application (('+' | '-') Application)*
Application  ::= Atom+
Atom         ::= Integer | Variable | Lambda | IfThenElse | '(' Expression ')'
Lambda       ::= ('λ' | '\') Identifier '.' Expression
IfThenElse   ::= 'if' Expression 'then' Expression 'else' Expression
```

### Extended

```ebnf
SourceFile   ::= (LetDef Newline)* Expression?
LetDef       ::= 'let' Identifier ParamList? '=' Expression
ParamList    ::= '(' Identifier (',' Identifier)* ')'
Expression   ::= BinaryOp
BinaryOp     ::= Application (('+' | '-') Application)*
Application  ::= Atom+
Atom         ::= Integer | Variable | Lambda | IfThenElse
               | '(' Expression ')' | BlockExpr
BlockExpr    ::= '{' (LetDef BlockDelim)* Expression? '}'
BlockDelim   ::= Newline | ';'
Lambda       ::= ('λ' | '\') Identifier '.' Expression
IfThenElse   ::= 'if' Expression 'then' Expression 'else' Expression
```

### New tokens

| Token | Text | Example |
|-------|------|---------|
| `LBrace` | `{` | `{ let a = 1; a }` |
| `RBrace` | `}` | |
| `Comma` | `,` | `let f(x, y) = ...` |
| `Semicolon` | `;` | `{ let a = 1; a }` |

### New syntax kinds

| Kind | Description |
|------|-------------|
| `ParamList` | `( Ident , Ident , ... )` — parameter list on LetDef |
| `BlockExpr` | `{ LetDef* Expression? }` — block expression |
| `CommaToken` | `,` separator in ParamList |
| `LBraceToken` | `{` block delimiter |
| `RBraceToken` | `}` block delimiter |
| `SemicolonToken` | `;` statement separator (alternative to Newline inside blocks) |

---

## Examples

### Function definitions with parameters

```
let double(x) = x + x
let add(x, y) = x + y
let apply(f, x) = f x
let const(x, y) = x
```

Application stays juxtaposition:
```
add 3 4           -- 7
let inc = add 1   -- partial application: λy. 1 + y
double 5          -- 10
```

**Disambiguation rule:** `ParamList` is recognized only in LetDef position (after `let name`). The token sequence `f(x)` in expression position is juxtaposition: `f` applied to `(x)`.

### Block expressions

```
let result = {
  let a = double 5
  let b = add a 3
  a + b
}

-- Single-line with semicolons:
let quick = { let a = 1; a + 1 }

-- Blocks anywhere an Atom is valid:
double { let x = 3; x + 1 }

if condition then {
  let a = 1
  a + 1
} else {
  let b = 2
  b + 2
}
```

### Combined

```
let compute(x, y) = {
  let sum = add x y
  let product = x + y
  sum + product
}
```

### Empty ParamList

`let f() = x` is a parse error — `ParamList` requires at least one identifier. The grammar production `'(' Identifier (',' Identifier)* ')'` enforces this.

### Trailing commas

`let f(x, y,) = body` — not supported. Trailing comma is a parse error. May be added in the future if needed.

---

## Desugaring (CST → AST)

### ParamList → nested Lambda

`let f(x, y, z) = body` desugars to `Let("f", Lam("x", Lam("y", Lam("z", body))))`.

The term converter right-folds the parameter names over the body:

```
params.rev_fold(body, fn(acc, param) { Lam(param, acc) })
```

When `ParamList` is absent, behavior is unchanged:

```
let x = expr  →  Let("x", expr)
```

### BlockExpr → Module

`BlockExpr` desugars to the same AST as `SourceFile`: `Module(defs, body)`.

```
{ let a = 1; let b = 2; a + b }
→ Module([("a", Int(1)), ("b", Int(2))], BinOp(Add, Var("a"), Var("b")))
```

A block with only an expression: `{ expr }` → `Module([], expr)`.

A block with defs but no trailing expression: `{ let a = 1 }` → `Module([("a", Int(1))], Unit)`. This matches how `SourceFile` with defs and no trailing expression produces `Module(defs, Unit)` in the existing `term_convert.mbt`.

An empty block `{ }` → parse error. The parser emits "empty block expression" and produces a `BlockExpr` node with only `LBraceToken` and `RBraceToken` children. The term converter produces `Error("empty block")`.

### AST change

**No AST change needed.** `BlockExpr` desugars to `Module(defs, body)`, the same variant used for `SourceFile`. This means the projection layer, resolve, print_term, and all downstream code works without modification.

The semantic distinction between top-level modules and scoped blocks is not encoded in the AST. If needed later, a wrapper variant can be added.

---

## Parser implementation

### Helper function updates

The following existing helper functions must be updated to recognize new tokens:

| Function | Add | File | Purpose |
|----------|-----|------|---------|
| `token_starts_expression` | `@token.LBrace` | `cst_parser.mbt` | Recognize `{` as expression start |
| `token_starts_application_atom` | `@token.LBrace` | `cst_parser.mbt` | Allow `f { ... }` as application |
| `is_sync_point` | `@token.LBrace`, `@token.RBrace`, `@token.Semicolon` | `cst_parser.mbt` | Error recovery stops at braces and semicolons |

### Error recovery: brace tracking

`skip_until_paren_close_or_sync` must be generalized to track both `()` and `{}` depth, or a parallel `skip_until_brace_close_or_sync` must be created. Without this, error recovery inside a block could consume the closing `}`.

### parse_param_list

Called after the identifier in `parse_let_item` when the next token is `LParen`:

```
fn parse_param_list(ctx) {
  let mark = ctx.mark()
  ctx.emit_token(LParenToken)        -- (
  match ctx.peek() {                  -- first param (required)
    Identifier(_) => ctx.emit_token(IdentToken)
    _ => { ctx.error("Expected parameter name"); ctx.emit_error_placeholder() }
  }
  while ctx.peek() == Comma {
    ctx.emit_token(CommaToken)        -- ,
    match ctx.peek() {                -- next param
      Identifier(_) => ctx.emit_token(IdentToken)
      RParen => break                 -- trailing comma: stop (error already implicit)
      _ => { ctx.error("Expected parameter name"); ctx.emit_error_placeholder() }
    }
  }
  expect(ctx, RParen)                 -- )
  ctx.start_at(mark, ParamList)
  ctx.finish_node()
}
```

### parse_block_expr

Called from `parse_atom` when the next token is `LBrace`:

```
fn parse_block_expr(ctx) {
  ctx.start_node(BlockExpr)
  ctx.emit_token(LBraceToken)         -- {
  consume_delimiters(ctx)              -- newlines and semicolons
  if ctx.peek() == RBrace {            -- empty block: error
    ctx.error("Empty block expression")
    expect(ctx, RBrace)
    ctx.finish_node()
    return
  }
  while ctx.peek() == Let {
    parse_let_item(ctx)
    let delim_count = consume_delimiters(ctx)
    if delim_count == 0 && ctx.peek() != RBrace && ctx.peek() != EOF {
      ctx.error("Expected ';' or newline between definitions")
    }
  }
  consume_delimiters(ctx)
  if ctx.peek() != RBrace && ctx.peek() != EOF {
    parse_expression(ctx)
  }
  consume_delimiters(ctx)
  expect(ctx, RBrace)                  -- }
  ctx.finish_node()
}
```

`consume_delimiters` is a new helper that consumes both `Newline` and `Semicolon` tokens.

### Modification to parse_let_item

Insert `parse_param_list` call after identifier, before `=`:

```
fn parse_let_item(ctx) {
  let mark = ctx.mark()
  ctx.emit_token(LetKeyword)
  match ctx.peek() {
    Identifier(_) => ctx.emit_token(IdentToken)
    _ => { ctx.error("Expected variable name"); ctx.emit_error_placeholder() }
  }
  if ctx.peek() == LParen {           -- NEW: optional param list
    parse_param_list(ctx)
  }
  expect(ctx, Eq)
  parse_expression_with_mode(ctx, false)
  ctx.start_at(mark, LetDef)
  ctx.finish_node()
}
```

### Modification to parse_atom

Add BlockExpr case:

```
fn parse_atom(ctx) {
  match ctx.peek() {
    // ... existing cases ...
    LBrace => parse_block_expr(ctx)
    _ => { ctx.error("Expected expression"); ctx.emit_error_placeholder() }
  }
}
```

---

## LetDefView update

After adding `ParamList`, the CST for `let f(x, y) = body` has children:

```
LetDef [LetKeyword, IdentToken("f"), ParamList(...), EqToken, <body_expr>]
```

The existing `LetDefView` accessors must be updated:

| Accessor | Current | Updated |
|----------|---------|---------|
| `name()` | First `IdentToken` text | Unchanged (still first `IdentToken`) |
| `init()` | `nth_child(0)` | Skip `ParamList` — find first non-ParamList node child |
| `params()` | N/A | NEW: return `ParamList` child if present, else `None` |

Without this update, `init()` would return the `ParamList` node instead of the body expression, breaking `term_convert.mbt`.

---

## lambda_spec updates

### syntax_kind_to_token_kind

The token-matching table in `lambda_spec.mbt` must include new tokens for incremental reuse to work correctly:

| SyntaxKind | Token |
|------------|-------|
| `LBraceToken` | `LBrace` |
| `RBraceToken` | `RBrace` |
| `CommaToken` | `Comma` |
| `SemicolonToken` | `Semicolon` |

---

## Block reparse integration

`BlockExpr` is a reparseable container kind. The reparser function is `parse_block_expr`.

### Five properties satisfied

1. **Lexical containment**: `{` and `}` are unambiguous single-character tokens
2. **Syntactic independence**: `parse_block_expr` produces a complete CST without surrounding context
3. **Structural integrity**: bracket balance check — O(n) scan verifying `{}`s match
4. **Deterministic discovery**: `BlockExpr` is the reparseable kind. Walk ancestors until found.
5. **Boundary stability**: editing inside `{ ... }` doesn't move the braces

### Splice validation

After reparsing a block, the framework must verify:
- All non-trivia tokens consumed (no trailing unconsumed tokens)
- Result root kind matches the replaced node's kind (`BlockExpr`)

If either check fails, fall through to full incremental reparse.

**Note:** Block reparse implementation is a separate PR, after the grammar extension lands and the `BlockReparseSpec` framework API is built.

---

## Error recovery

### Missing closing brace

```
let x = {
  let a = 1
  a + 1
-- missing }
```

Parser emits error and closes `BlockExpr` at EOF or next top-level `let`.

### Nested unclosed blocks

```
let x = {
  let y = {
    let a = 1
    a + 1
  -- missing inner }
}
```

The inner block consumes until it finds a `}`, which matches the outer `}`. The outer block is then unclosed. This is standard brace-matching behavior — the parser reports the error at the inner block.

### Empty block

`{ }` — parse error "empty block expression." Parsed as `BlockExpr` with no children.

### Missing parameter name

`let f(, y) = body` — error recovery: emit error placeholder for missing identifier, continue parsing remaining params.

---

## Testing

### Parse tests

- `let f(x) = x + x` — single param
- `let f(x, y) = x + y` — multiple params
- `let f(x, y, z) = x` — three params
- `{ let a = 1; a }` — single-line block with semicolons
- `{ a + b }` — block with only expression
- Multi-line block with newlines
- `{ let a = 1; let b = 2; a + b }` — block with multiple lets
- `double { let x = 3; x + 1 }` — block in application
- `let f(x) = { let y = x + 1; y }` — params + block
- `{ { x } }` — nested blocks
- `if c then { a } else { b }` — blocks in if-then-else
- `{ }` — empty block (error)
- `let f(,) = x` — error recovery
- `let f() = x` — empty param list (error)
- `let f(x, y,) = x` — trailing comma (error)
- `{ let a = 1 }` — block with let but no trailing expression

### Desugaring tests

- `let f(x, y) = body` → `Module([("f", Lam("x", Lam("y", body)))], ...)`
- `{ let a = 1; a }` → `Module([("a", Int(1))], Var("a"))`
- `{ expr }` → `Module([], expr)`
- `{ let a = 1; let b = 2; a + b }` → `Module([("a", ...), ("b", ...)], ...)`
- `let f(x) = { let y = x + 1; y }` → nested Module inside Lam

### Incremental tests

- Edit inside BlockExpr → correct incremental reparse
- Edit ParamList (add/remove param) → correct reparse
- Edit value in multi-line block → RepeatGroup reuse works

### Roundtrip tests

- Parse → AST → print → parse → AST produces same result

---

## Implementation order

1. **Tokens + lexer**: Add `LBrace`, `RBrace`, `Comma`, `Semicolon` to token enum and lexer
2. **Syntax kinds**: Add `ParamList`, `BlockExpr`, `CommaToken`, `LBraceToken`, `RBraceToken`, `SemicolonToken`
3. **Parser helpers**: Update `token_starts_expression`, `token_starts_application_atom`, `is_sync_point`, add `consume_delimiters`, generalize brace tracking in error recovery
4. **Parser rules**: Add `parse_param_list`, `parse_block_expr`, modify `parse_let_item` and `parse_atom`
5. **LetDefView**: Update `init()` to skip ParamList, add `params()` accessor
6. **Term convert**: Handle `ParamList` desugaring (right-fold to nested Lam) and `BlockExpr` desugaring (to Module)
7. **lambda_spec**: Update `syntax_kind_to_token_kind` for new tokens
8. **Tests**: Parse tests, desugaring tests, incremental tests, error recovery tests
9. **Interfaces + format**: `moon info && moon fmt`

**Note:** Step 4 (AST change) is not needed — `BlockExpr` desugars to `Module`, no new variant required. All existing pattern matches on `Module` continue to work.

---

## Out of scope

- Match expressions (future extension)
- Record types/literals (future extension)
- Type annotations (future extension)
- Call syntax `f(x, y)` for application (keeps juxtaposition only)
- Empty param list `let f() = x` (requires at least one param)
- Trailing commas in ParamList
- Block reparse framework implementation (separate PR)
