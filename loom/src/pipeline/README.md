# `dowdiness/loom/pipeline`

Language-agnostic two-memo incremental pipeline. Define a language once;
get reactive, backdating-aware parsing for free.

## Pipeline shape

```
Signal[String] → Memo[CstStage] → Memo[Ast]
```

`Signal` propagates source changes. Each `Memo` re-runs only when its
upstream value has changed (checked via `Eq`). `CstStage::Eq` uses a
structural hash for O(1) rejection; `Ast::Eq` is structural equality.

## Public API

```moonbit
pub(open) trait Parseable {
  parse_source(Self, String) -> CstStage
}

pub(all) struct CstStage {
  cst          : @seam.CstNode
  diagnostics  : Array[String]
  is_lex_error : Bool
}

pub struct Language[Ast] { /* private vtable */ }
pub fn[T : Parseable, Ast] Language::from(
  T,
  to_ast~      : (@seam.SyntaxNode) -> Ast,
  on_lex_error~: (String) -> Ast,
) -> Language[Ast]

pub struct ReactiveParser[Ast] { /* private */ }
pub fn[Ast : Eq] ReactiveParser::new(String, Language[Ast]) -> Self
pub fn[Ast]      ReactiveParser::set_source(Self, String)   -> Unit
pub fn[Ast]      ReactiveParser::cst(Self)                  -> CstStage
pub fn[Ast]      ReactiveParser::diagnostics(Self)          -> Array[String]
pub fn[Ast : Eq] ReactiveParser::term(Self)                 -> Ast
```

## Implementing a new language

**Step 1 — implement `Parseable`:**

```moonbit
pub struct MyLanguage {}

pub impl @pipeline.Parseable for MyLanguage with parse_source(_, s) {
  // combine lex + parse; set is_lex_error if lexer fails
  @pipeline.CstStage::{ cst, diagnostics, is_lex_error: false }
}
```

**Step 2 — build a `Language[Ast]` vtable:**

```moonbit
pub fn my_language() -> @pipeline.Language[MyAst] {
  @pipeline.Language::from(
    MyLanguage::{},
    to_ast=      fn(n) { my_syntax_to_ast(n) },
    on_lex_error=fn(msg) { MyAst::error(msg) },
  )
}
```

**Step 3 — create a `ReactiveParser`:**

```moonbit
let db = @pipeline.ReactiveParser::new("initial source", my_language())
db.set_source("updated source")
let ast = @pipeline.ReactiveParser::term(db)
```

## `Parseable` contract

- Lex failure → `is_lex_error = true`, at least one diagnostic, minimal valid `cst`
- Parse error → `is_lex_error = false`, diagnostics populated, error-recovery `cst`
- Valid input → `is_lex_error = false`, empty diagnostics
- **Never panic** — called inside a `Memo` closure

## `Ast : Eq` requirement

`Eq` is required on `Ast` for backdating. When `CstStage` is equal to the
cached value, the term memo re-runs but skips downstream work if the new
`Ast` is also equal to the cached one. Use structure-only equality (ignore
positions and node IDs) for maximum backdating benefit.

## Reference implementation

`examples/lambda/src/` — `LambdaLanguage` + `LambdaReactiveParser` show the full pattern,
including lex-error routing and the `AstNode::Eq` structure-only definition.

## Full API contract

`docs/api/pipeline-api-contract.md` — stability levels, invariants, and
backdating chain documentation for every public symbol.
