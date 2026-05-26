# `dowdiness/loom/pipeline`

Reactive parser handle: wraps `ImperativeParser` with an `@incr` snapshot
input so downstream consumers can subscribe to coherent source, syntax tree,
AST, diagnostics, and reuse-count views without managing the engine directly.

## Pipeline shape

```
Input[ParseSnapshot[Ast]] → Derived[ParseSnapshot[Ast]]
                         ↘ Derived[String]
                         ↘ Derived[SyntaxNode]
                         ↘ Derived[Ast]
                         ↘ Derived[DiagnosticSet]
```

Each derived cell re-runs only when its upstream value has changed (checked via `Eq`).
`ParseSnapshot[Ast]` keeps the parse products together, so consumers do not
observe source, syntax, AST, and diagnostics from different parse passes.

## Public API

```moonbit
pub struct Parser[Ast] { /* private */ }
pub fn[Ast : Eq] Parser::new(String, @incremental.ImperativeLanguage[Ast], runtime?) -> Self
pub fn[Ast : Eq] Parser::set_source(Self, String)                        -> Unit
pub fn[Ast : Eq] Parser::apply_edit(Self, @core.Edit, String)            -> Unit
pub fn[Ast]      Parser::snapshot(Self)                                  -> @cells.Derived[@incremental.ParseSnapshot[Ast]]
pub fn[Ast]      Parser::source(Self)                                    -> @cells.Derived[String]
pub fn[Ast]      Parser::syntax_tree(Self)                               -> @cells.Derived[@seam.SyntaxNode]
pub fn[Ast]      Parser::ast(Self)                                       -> @cells.Derived[Ast]
pub fn[Ast]      Parser::diagnostics(Self)                               -> @cells.Derived[@core.DiagnosticSet]
pub fn[Ast]      Parser::runtime(Self)                                   -> @cells.Runtime
```

`set_source` and `apply_edit` both update the snapshot input under
`Runtime::batch` so consumers never observe a half-updated graph.

## Implementing a new language

Grammar authors don't construct `Parser` directly. Define a `Grammar[T, K, Ast]`
(see `dowdiness/loom` crate root) and call `new_parser(source, grammar)`;
the factory builds the `ImperativeLanguage[Ast]` vtable and wraps it in
a `Parser`.

## Error Handling

- Lexer recovery → `syntax_tree()` returns the recovered tree,
  `diagnostics()` carries structured lexer diagnostics, and `ast()` runs on
  that recovered tree.
- Parse recovery → `syntax_tree()` returns the recovered tree,
  `diagnostics()` carries structured parser diagnostics, and `ast()` runs on
  that recovered tree.
- Valid input → `syntax_tree()` returns the tree and `diagnostics()` is empty.

## `Ast : Eq` requirement

`Eq` is required on `Ast` for snapshot and view backdating. Use
structure-only equality (ignore positions and node IDs) for maximum
backdating benefit.

## Reference implementation

`examples/lambda/src/` — `lambda_grammar` shows the full pattern, including
total lexing and the `Term::Eq` structure-only definition.

## Full API contract

`docs/api/pipeline-api-contract.md` — stability levels, invariants, and
backdating chain documentation for every public symbol.
