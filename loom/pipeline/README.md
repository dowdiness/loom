# `dowdiness/loom/pipeline`

Reactive parser handles: wrap `ImperativeParser` with an `@incr` snapshot
input so downstream consumers can subscribe to coherent parse views without
managing the engine directly. `Parser[Ast]` publishes source, syntax tree, AST,
diagnostics, and reuse count; `SyntaxParser` publishes the same CST/diagnostic
surface without an AST fold.

## `Parser[Ast]` pipeline shape

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

pub struct SyntaxSnapshot { source; syntax; diagnostics; reuse_count }
pub struct SyntaxParser { /* private */ }
pub fn SyntaxParser::new(String, @incremental.ImperativeLanguage[Unit], runtime?) -> Self
pub fn SyntaxParser::set_source(Self, String)                        -> Unit
pub fn SyntaxParser::apply_edit(Self, @core.Edit, String)            -> Unit
pub fn SyntaxParser::snapshot(Self)                                  -> @cells.Derived[SyntaxSnapshot]
pub fn SyntaxParser::source(Self)                                    -> @cells.Derived[String]
pub fn SyntaxParser::syntax_tree(Self)                               -> @cells.Derived[@seam.SyntaxNode]
pub fn SyntaxParser::diagnostics(Self)                               -> @cells.Derived[@core.DiagnosticSet]
pub fn SyntaxParser::runtime(Self)                                   -> @cells.Runtime
```

Outside a tracked compute closure, read these views with `.read()` /
`.read_or_abort()`. Inside another derived cell, use `.get()` /
`.get_or_abort()` so the dependency is tracked.

`set_source` and `apply_edit` both update the snapshot input under
`Runtime::batch` so consumers never observe a half-updated graph.

## Runtime and attachment lifecycle

Runtime rules:

- Omitting `runtime?` creates a parser-owned runtime.
- Passing `runtime?` joins a caller-owned graph.
- Parser-attached pipelines should build their own `Scope` on
  `parser.runtime()`.
- Those pipelines own their `Watch` / priming / `dispose()` lifecycle.

See
[`docs/api/choosing-a-parser.md`](../../docs/api/choosing-a-parser.md#runtime-ownership-and-attachments)
for the full pattern and example.

## Implementing a new language

Grammar authors don't construct these handles directly. Define a
`Grammar[T, K, Ast]` and call `new_parser(source, grammar)` when you have an
AST fold and `Ast : Eq`; the factory builds the `ImperativeLanguage[Ast]`
vtable and wraps it in a `Parser`.

For CST/diagnostics-only integrations, define `SyntaxGrammar[T, K]` and call
`new_syntax_parser(source, grammar)`. If you already have a `Grammar` whose AST
is not `Eq`, use `grammar.to_syntax_grammar()` to reuse its lexer/spec without
running the AST fold.

## Error Handling

- Lexer recovery → `syntax_tree()` returns the recovered tree,
  `diagnostics()` carries structured lexer diagnostics, and `Parser[Ast].ast()`
  runs on that recovered tree.
- Parse recovery → `syntax_tree()` returns the recovered tree,
  `diagnostics()` carries structured parser diagnostics, and `Parser[Ast].ast()`
  runs on that recovered tree.
- Valid input → `syntax_tree()` returns the tree and `diagnostics()` is empty.

`SyntaxParser` follows the same syntax/diagnostic rules and simply has no
`ast()` view.

These are current parse views. The parser does not retain semantic documents or
reuse baselines across malformed input. That policy belongs in a downstream
attachment rooted on `parser.runtime()`.

For the authoring pattern where diagnostics update immediately while the last
successful semantic document is retained until projection succeeds again, see the
[last-good semantic attachment guide](../../docs/api/last-good-semantic-attachment.md).

## `Ast : Eq` requirement

`Parser[Ast]` requires `Eq` on `Ast` for snapshot and view backdating. Use
structure-only equality (ignore positions and node IDs) for maximum
backdating benefit.

`SyntaxParser` has no `Ast` parameter and no AST equality requirement. Its
snapshot backdates on source, syntax tree, diagnostics, and reuse count only.

## Reference implementation

`examples/lambda/src/` — `lambda_grammar` shows the full pattern, including
total lexing and the `Term::Eq` structure-only definition.

## Full API contract

`docs/api/pipeline-api-contract.md` — stability levels, invariants, and
backdating chain documentation for every public symbol.
