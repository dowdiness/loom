# `dowdiness/lambda`

Concrete lambda calculus implementation of the generic parser infrastructure.
Two responsibilities: **grammar description** and **graphviz visualization**.

## Public API

```moonbit
// ── Grammar ───────────────────────────────────────────────────────────────────

pub let lambda_grammar : @bridge.Grammar[@token.Token, @syntax.SyntaxKind, @ast.AstNode]

// ── Low-level CST parsing (used by benchmarks and whitebox tests) ─────────────

pub fn make_reuse_cursor(...) -> @core.ReuseCursor[...]
pub fn parse_cst_with_cursor(...) -> (CstNode, Array[Diagnostic], Int)
pub fn parse_cst_recover_with_tokens(...) -> (CstNode, Array[Diagnostic], Int)

// ── Visualization ─────────────────────────────────────────────────────────────

pub fn to_dot(@ast.AstNode) -> String
```

## Grammar

`lambda_grammar` is the single integration surface. Pass it to bridge factories
to get an `ImperativeParser` or `ReactiveParser`:

```moonbit
let parser = @bridge.new_imperative_parser("λx.x + 1", @lambda.lambda_grammar)
let db     = @bridge.new_reactive_parser("λx.x + 1", @lambda.lambda_grammar)
db.set_source("λx.x + 2")
let node = db.term()  // @ast.AstNode
```

`Grammar[T,K,Ast]` holds three fields — `spec`, `tokenize`, `to_ast` — and the
bridge factories erase `T`/`K` internally. Grammar authors never write vtable
wiring (`ImperativeLanguage`, `Language`) by hand.

## Visualization

`to_dot` converts an `AstNode` tree to a Graphviz DOT string by delegating
to `@viz.to_dot[DotAstNode]`.

### Orphan rule — why `DotAstNode` exists

MoonBit requires that you own either the trait or the type to implement it.
`@viz.DotNode` is foreign (defined in `viz`) and `@ast.AstNode` is foreign
(defined in `ast`), so `lambda` cannot implement `DotNode for AstNode` directly.

The fix: define a private newtype wrapper in this package:

```moonbit
priv struct DotAstNode { node : @ast.AstNode }
impl @viz.DotNode for DotAstNode with ...
```

`DotAstNode` is local, so the impl is legal. `to_dot` wraps and unwraps
transparently — callers always work with plain `@ast.AstNode`.

The same pattern applies whenever you need to bridge two foreign packages.
See `src/viz/README.md` for the `DotNode` trait contract.
