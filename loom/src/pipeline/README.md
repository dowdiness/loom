# `dowdiness/loom/pipeline`

Reactive parser handle: wraps `ImperativeParser` with `@incr` signal/memo
outputs so downstream consumers can subscribe to source, syntax tree,
AST, and diagnostics without managing the engine directly.

## Pipeline shape

```
Signal[String] → Memo[CstStage] → Memo[Ast]
                              ↘ Memo[SyntaxNode?]
                              ↘ Memo[Array[String]]  // diagnostics
```

Each memo re-runs only when its upstream value has changed (checked via
`Eq`). `CstStage::Eq` uses a structural hash for O(1) rejection;
`Ast::Eq` is structural equality.

## Public API

```moonbit
pub(all) struct CstStage {
  cst          : @seam.CstNode
  diagnostics  : Array[String]
  is_lex_error : Bool
}

pub struct Parser[Ast] { /* private */ }
pub fn[Ast : Eq] Parser::new(String, @incremental.ImperativeLanguage[Ast], runtime?) -> Self
pub fn[Ast : Eq] Parser::set_source(Self, String)                        -> Unit
pub fn[Ast : Eq] Parser::apply_edit(Self, @core.Edit, String)            -> Unit
pub fn[Ast]      Parser::source(Self)                                    -> @cells.Memo[String]
pub fn[Ast]      Parser::syntax_tree(Self)                               -> @cells.Memo[@seam.SyntaxNode?]
pub fn[Ast]      Parser::ast(Self)                                       -> @cells.Memo[Ast]
pub fn[Ast]      Parser::diagnostics(Self)                               -> @cells.Memo[Array[String]]
pub fn[Ast]      Parser::runtime(Self)                                   -> @cells.Runtime
```

`set_source` and `apply_edit` both batch all four signal updates under
`Runtime::batch` so consumers never observe a half-updated graph.

## Implementing a new language

Grammar authors don't construct `Parser` directly. Define a `Grammar[T, K, Ast]`
(see `dowdiness/loom` crate root) and call `new_parser(source, grammar)`;
the factory builds the `ImperativeLanguage[Ast]` vtable and wraps it in
a `Parser`.

## Lex-error handling

- Lex failure → `syntax_tree()` returns `None`, `diagnostics()` carries
  the error message, `ast()` returns whatever the grammar's
  `on_lex_error` callback produces (typically a sentinel AST node).
- Parse error → `syntax_tree()` returns `Some(tree)` (error-recovered),
  `diagnostics()` lists the problems, `ast()` runs on the recovered tree.
- Valid input → `syntax_tree()` returns `Some(tree)`, `diagnostics()` is empty.

## `Ast : Eq` requirement

`Eq` is required on `Ast` for backdating. When `CstStage` is equal to the
cached value, the AST memo re-runs but skips downstream work if the new
`Ast` is also equal to the cached one. Use structure-only equality (ignore
positions and node IDs) for maximum backdating benefit.

## Reference implementation

`examples/lambda/src/` — `LambdaGrammar` shows the full pattern,
including `on_lex_error` routing and the `AstNode::Eq` structure-only
definition.

## Full API contract

`docs/api/pipeline-api-contract.md` — stability levels, invariants, and
backdating chain documentation for every public symbol.
