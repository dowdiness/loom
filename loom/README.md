# dowdiness/loom

Generic incremental parser framework for MoonBit.

`loom` turns a single `Grammar[T, K, Ast]` value into an incremental
parser that gives you edit-aware lexing, a lossless green tree (CST),
validated CST subtree reuse at grammar boundaries, error recovery, and a
reactive pipeline that publishes source / syntax / AST / diagnostics as
[`@incr`](../incr) input / derived cells.

> **Status:** framework stable. See [../ROADMAP.md](../ROADMAP.md) for
> in-flight work.

## Install

Add to your `moon.mod.json`:

```json
{
  "deps": {
    "dowdiness/loom": "0.1.0",
    "dowdiness/seam": "0.1.0",
    "dowdiness/incr": "0.1.0"
  }
}
```

`seam` owns the CST types and `incr` is the reactive runtime `loom`
publishes into. All three ship together.

## Quick Start

```mbt nocheck
// Any grammar value works — the lambda example is a complete reference
// implementation of Grammar[T, K, Ast].
let parser = @loom.new_parser("λx.x + 1", @lambda.lambda_grammar)

// Read the parsed AST outside the reactive graph.
let term = parser.ast().read_or_abort()

// Whole-source reset (simplest update path):
parser.set_source("λx.x + 2")

// Edit-driven update: TokenBuffer splice + validated CST subtree reuse.
let edit = @loom.Edit::new(0, 0, 1)          // start, old_len, new_len
parser.apply_edit(edit, " λx.x + 2")

// Diagnostics are published as a reactive cell.
let diagnostics = parser.diagnostics().read_or_abort()
```

See [`examples/lambda`](../examples/lambda/) for the full grammar used
above, or [`examples/json`](../examples/json/) and
[`examples/markdown`](../examples/markdown/) for smaller references.

## Public API (one import)

```mbt nocheck
// Consumers
@loom.Parser              // reactive parser handle
@loom.ImperativeParser    // lower-level edit-driven engine
@loom.new_parser          // build Parser[Ast] from a Grammar
@loom.new_imperative_parser
@loom.Edit                // edit descriptor (start, old_len, new_len)
@loom.Diagnostic

// Grammar authors
@loom.Grammar             // grammar description
@loom.LanguageSpec        // token-level hooks
@loom.ParserContext       // parse combinators
@loom.CstNode             // immutable green tree
@loom.SyntaxNode          // positioned CST view
@loom.AstView             // typed view trait
@loom.CstFold             // memoized CST → AST

// Authoring projection helpers
@loom.ProjectionIdentityBaseline
@loom.ProjectionLeaf
@loom.StableProjectionLeaf
@loom.realign_projection_identities
```

Full signatures: [`src/pkg.generated.mbti`](src/pkg.generated.mbti).

## Choosing a Parser

Most callers want **`Parser`** — it handles both `apply_edit` and
`set_source` and publishes the result as `@incr` cells that downstream
Derived cells can compose with. Reach for `ImperativeParser` only when you do
not need the reactive graph.

See [`docs/api/choosing-a-parser.md`](../docs/api/choosing-a-parser.md)
for the full decision.

## Learn More

- [Docs index](../docs/README.md) — navigation for everything below
- [Architecture overview](../docs/architecture/overview.md) — layer
  diagram and design principles
- [ROADMAP](../ROADMAP.md) — phase status and what is next

## License

Apache-2.0.
