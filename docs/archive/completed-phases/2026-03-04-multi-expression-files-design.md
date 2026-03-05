# Multi-Expression Files — Design

**Status:** Approved — ready for implementation

---

## Goal

Add a `parse_source_file` entry point to the lambda example that handles files
containing sequences of top-level `let x = e` definitions followed by an
optional final expression. Each top-level definition is an independent CST
subtree, making incremental reuse genuinely impactful: editing one binding
does not re-parse any other.

---

## Syntax

```
SourceFile → LetDef* Expression?

LetDef     → 'let' IDENT '=' Expression   // no 'in'
Expression → (existing expression grammar)
```

Top-level `let x = e` is a **declaration** (no `in` keyword), distinct from
the nested `let x = e in body` **expression** (`LetExpr`). This is the
standard PL-theory distinction between module-level definitions and local
bindings. The flat structure is what enables per-definition incremental reuse.

---

## Breaking changes

None. `parse_cst` and `parse` are untouched. All existing tests continue
to pass unchanged.

---

## SyntaxKind changes

**File:** `src/syntax/syntax_kind.mbt`

Add one node kind:

```moonbit
LetDef   // top-level: let IDENT = Expression (no 'in')
```

`LetDef` CST shape:
```
LetDef
├── LetKeyword
├── IdentToken    (variable name)
├── EqToken
└── Expression    (init — any expression)
```

Compare to `LetExpr` (6 children: `let IDENT = init in body`). `LetDef` has
4 children and no `in`/body.

---

## Grammar changes

**File:** `src/cst_parser.mbt`

Add `parse_let_def` and `parse_source_file_root`. `parse_lambda_root`
(single-expression grammar) is **not modified**.

```moonbit
fn parse_let_def(ctx : ParserContext[Token, SyntaxKind]) -> Unit {
  node(LetDef, () => {
    emit_token(LetKeyword)
    expect(Ident, IdentToken)
    expect(Eq, EqToken)
    parse_expression(ctx)
  })
}

fn parse_source_file_root(ctx : ParserContext[Token, SyntaxKind]) -> Unit {
  while ctx.peek() == Let {
    parse_let_def(ctx)
  }
  match ctx.peek() {
    EOF => ()
    _ => parse_expression(ctx)   // optional final expression
  }
  ctx.flush_trivia()
}
```

A new `LanguageSpec` binds `parse_source_file_root` as the grammar entry:

```moonbit
let source_file_spec : LanguageSpec[Token, SyntaxKind] = { ... }
```

---

## Entry points

**File:** `src/cst_parser.mbt`

```moonbit
pub fn parse_source_file(
  source : String,
) -> (CstNode, Array[Diagnostic[Token]])
```

Returns the raw CST + diagnostics. This is the primary entry point for
incremental use (combine with `ReuseCursor` for incremental re-parsing).

**File:** `src/parser.mbt`

```moonbit
pub fn parse_source_file_term(
  source : String,
) -> (Term, Array[Diagnostic[Token]])
```

Parses and converts to `Term` in one call. Delegates to `parse_source_file`
then `convert_source_file`.

---

## Term changes

**File:** `src/ast/term.mbt` (or wherever `Term` is defined)

Add `Unit` variant:

```moonbit
Unit
```

**`print_term`:**

```moonbit
Unit => "()"
```

**`convert_source_file`** in `term_convert.mbt`:

Right-fold the `LetDef` children with the optional final expression (or
`Unit` if absent) as the terminal:

```moonbit
fn convert_source_file(node : SyntaxNode) -> Term {
  // collect LetDef children and final Expression child
  // right-fold: Let(x1, e1, Let(x2, e2, ... final_or_unit))
}
```

Example: `let id = λx.x\nlet const = λx.λy.x` converts to:
```
Let("id", Lam("x", Var("x")), Let("const", Lam("x", Lam("y", Var("x"))), Unit))
```
Which prints as: `let id = λx.x in let const = λx.λy.x in ()`

---

## CST shape

```
SourceFile
├── LetDef              ← independent subtree
│   ├── LetKeyword
│   ├── IdentToken "id"
│   ├── EqToken
│   └── LambdaExpr
├── LetDef              ← independent subtree
│   ├── LetKeyword
│   ├── IdentToken "const"
│   ├── EqToken
│   └── LambdaExpr
└── (optional Expression child)
```

Each `LetDef` is a sibling child of `SourceFile`. The `ReuseCursor` can skip
any unchanged `LetDef` node when an edit touches only a neighbouring binding.

---

## Testing

### CST structure tests (`src/cst_tree_test.mbt`)

- `SourceFile` with two definitions has exactly two `LetDef` children
- Each `LetDef` has four children: `LetKeyword`, `IdentToken`, `EqToken`, expression
- Final expression appears as last child when present
- Empty file (no definitions, no expression) produces `SourceFile` with zero children

### Term conversion tests (`src/parser_test.mbt`)

- Two definitions → `let id = λx.x in let const = λx.λy.x in ()`
- One definition + final expression → `let f = λx.x in f 1`
- Empty file → `()`

### Incremental reuse test

- Parse `let id = λx.x\nlet const = λx.λy.x`
- Edit `id`'s body (`λx.x` → `λx.x x`)
- Re-parse incrementally
- Assert `reuse_count > 0` — `const`'s `LetDef` node reused unchanged

### Differential fuzz extension (`src/imperative_differential_fuzz_test.mbt`)

Extend existing oracle to multi-expression source files: random sequences of
`let` definitions + optional final expression, random edits, incremental vs
full reparse must produce identical trees.

---

## Approach

Single commit (or small sequence of TDD commits):
1. Add `LetDef` to `SyntaxKind`
2. Add `parse_let_def` + `parse_source_file_root` + new `LanguageSpec`
3. Add `parse_source_file` entry point
4. Add `Unit` to `Term`, update `print_term`
5. Add `convert_source_file` + `parse_source_file_term`
6. Add tests (CST structure, term conversion, reuse, fuzz extension)

Verification: `cd examples/lambda && moon test` passes; reuse test confirms
`reuse_count > 0`; fuzz test extended and passing.

---

## References

- [lambda ROADMAP](../../ROADMAP.md) — multi-expression files exit criteria
- [seam/docs/design.md](../../../../seam/docs/design.md) — three-layer API,
  same independent-subtree philosophy applied to SyntaxNode
- [loom/docs/architecture/seam-model.md](../../../../docs/architecture/seam-model.md)
  — CstNode structural sharing; why flat siblings enable reuse
