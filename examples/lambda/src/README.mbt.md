# `dowdiness/lambda`

Concrete lambda-calculus implementation of [`dowdiness/loom`](../../loom/).
Serves as the reference grammar — any other language plugs in the same
way.

Two responsibilities: **grammar description** and **Term/DOT
visualization**.

## Public API

```mbt nocheck
// ── Grammar ───────────────────────────────────────────────────────────────────

pub let lambda_grammar : @loom.Grammar[@token.Token, @syntax.SyntaxKind, @ast.Term]
pub let lambda_grammar_no_threshold : @loom.Grammar[...]   // reuse size threshold disabled

// ── High-level parsing ────────────────────────────────────────────────────────

pub fn parse(String) -> @ast.Term raise
pub fn parse_cst(String) -> (@seam.CstNode, Array[@core.Diagnostic[...]]) raise @core.LexError
pub fn new_imperative_parser(String) -> @incremental.ImperativeParser[@ast.Term]

// ── Visualization ─────────────────────────────────────────────────────────────

pub fn term_to_dot(@ast.Term) -> String
```

For the full signature list, see [`pkg.generated.mbti`](pkg.generated.mbti).

## Grammar

`lambda_grammar` is the single integration surface. Pass it to the
[`@loom`](../../loom/) factories to get an `ImperativeParser` or the
unified reactive `Parser[@ast.Term]`:

```mbt check
///|
test "grammar example: imperative parser" {
  let imp = @loom.new_imperative_parser("42", lambda_grammar)
  let term = imp.parse()
  inspect(@ast.print_term(term), content="42")
}

///|
test "grammar example: reactive parser + set_source" {
  let parser = @loom.new_parser("1 + 2", lambda_grammar)
  parser.set_source("42")
  inspect(
    @ast.print_term(parser.runtime().read(parser.ast())),
    content="42",
  )
}
```

`@loom.Grammar[T, K, Ast]` is the description any language provides —
`spec`, `tokenize`, `fold_node`, `on_lex_error`. The factories erase
`T`/`K` internally, so consumers only see `Ast`. Grammar authors never
write vtable wiring (`ImperativeLanguage`) by hand.

See [`@loom`'s Quick Start](../../loom/README.md#quick-start) for the
full consumer-side flow, including `apply_edit`.

## Visualization

`term_to_dot` converts an `@ast.Term` to a Graphviz DOT string by
delegating to `@viz.to_dot`.

### Orphan rule — why `TermDotNode` exists

MoonBit requires that you own either the trait or the type to implement
it. `@viz.DotNode` is foreign (defined in `loom/viz`) and `@ast.Term` is
foreign (defined in `ast/`), so `lambda` cannot `impl DotNode for Term`
directly.

The fix: a private newtype wrapper in this package:

```mbt nocheck
priv struct TermDotNode {
  id : Int
  term : @ast.Term
  child_nodes : Array[TermDotNode]
  resolution : Resolution?
}
impl @viz.DotNode for TermDotNode with ...
```

`TermDotNode` is local, so the impl is legal. `term_to_dot` wraps and
unwraps transparently — callers always work with plain `@ast.Term`.

The same pattern applies whenever you need to bridge two foreign
packages. See `src/viz/README.md` in the loom package for the `DotNode`
trait contract.

## Roadmap

Grammar expansion plans and CRDT exploration live in
[ROADMAP.md](../ROADMAP.md) alongside this README.

## Learn More

- [`@loom` Quick Start](../../loom/README.md#quick-start) — consumer-side
  flow including `apply_edit`
- [Architecture overview](../../docs/architecture/overview.md) — layer
  diagram and design principles
- [`examples/json`](../json/) — step-based `prefix_lexer` +
  `block_reparse_spec`
- [`examples/markdown`](../markdown/) — mode-aware lexing via
  `ModeLexer`
