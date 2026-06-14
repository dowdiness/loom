# dowdiness/loom

Generic incremental parser framework for MoonBit.

`loom` turns `Grammar[T, K, Ast]` or `SyntaxGrammar[T, K]` values into
incremental parsers that give you edit-aware lexing, a lossless green tree
(CST), validated CST subtree reuse at grammar boundaries, error recovery, and
reactive pipelines published as [`@incr`](../incr) input / derived cells.

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

For CST/diagnostics-only integrations, use `SyntaxGrammar` and
`new_syntax_parser`:

```mbt nocheck
let parser = @loom.new_syntax_parser(source, syntax_grammar)
let syntax = parser.syntax_tree().read_or_abort()
let diagnostics = parser.diagnostics().read_or_abort()
```

See [`examples/lambda`](../examples/lambda/) for the full grammar used above.
For smaller references, see [`examples/json`](../examples/json/),
[`examples/markdown`](../examples/markdown/), and
[`examples/moonbit`](../examples/moonbit/).

## Public API (one import)

```mbt nocheck
// Consumers
@loom.Parser              // reactive parser handle with an AST view
@loom.SyntaxParser        // reactive CST/diagnostics handle, no AST required
@loom.SyntaxSnapshot      // source/syntax/diagnostics/reuse snapshot
@loom.ImperativeParser    // lower-level edit-driven engine
@loom.new_parser          // build Parser[Ast] from a Grammar
@loom.new_syntax_parser   // build SyntaxParser from a SyntaxGrammar
@loom.new_imperative_parser
@loom.Edit                // edit descriptor (start, old_len, new_len)
@loom.Diagnostic

// Grammar authors
@loom.Grammar             // grammar description with AST fold
@loom.SyntaxGrammar       // grammar description without AST fold
@loom.LanguageSpec        // token-level hooks
@loom.LocatedToken        // external positioned lexer adapter input
@loom.ParserContext       // parse combinators
@loom.CstNode             // immutable green tree
@loom.SyntaxNode          // positioned CST view
@loom.AstView             // typed view trait
@loom.CstFold             // memoized CST → AST

// Authoring projection helpers
@loom.ProjectionIdentityBaseline
@loom.ProjectionIdentityTracker
@loom.ProjectionLeaf
@loom.StableProjectionLeaf
@loom.ProjectionStringIdAllocator
@loom.realign_projection_identities
@loom.realign_projection_items

// Test support
@loom.assert_incremental_edit_matches_full_parse
```

Full signatures: [`src/pkg.generated.mbti`](src/pkg.generated.mbti).

## Choosing a Parser

Use **`Parser[Ast]`** when callers need an AST view. Use **`SyntaxParser`**
when callers only need CST/diagnostics, or when the AST is not naturally `Eq`.
Both handles support `apply_edit` and `set_source`. Both publish `@incr` cells
that downstream `Derived` cells can compose with.

Reach for `ImperativeParser` only when you do not need the reactive graph.

See [`docs/api/choosing-a-parser.md`](../docs/api/choosing-a-parser.md)
for the full decision.

## Incremental-vs-Full Parse Tests

When a language example exercises an optimized incremental path, compare the
incremental result against a fresh full parse of the edited source. The shared
test helper checks both the CST and structured diagnostics, then returns the
incremental reuse count for optional optimization assertions:

```mbt nocheck
let reuse_count = @loom.assert_incremental_edit_matches_full_parse(
  "case label for failure messages",
  old_source,
  edit,
  new_source,
  my_syntax_grammar,
)
```

If you have an AST grammar, pass `my_grammar.to_syntax_grammar()` so the
helper stays focused on CST and diagnostics. Layer AST or rendered-output
assertions at the call site when a grammar exposes a useful semantic value. Use
reuse-count assertions only when the test is intentionally proving that a
specific optimized path fired, such as block reparse or sibling reuse. For
ordinary correctness tests, avoid asserting reuse counts: they are sensitive to
valid implementation changes in reuse thresholds, grammar boundaries, and
relexing strategy.

## Learn More

- [Docs index](../docs/README.md) — navigation for everything below
- [Architecture overview](../docs/architecture/overview.md) — layer
  diagram and design principles
- [ROADMAP](../ROADMAP.md) — phase status and what is next

## License

Apache-2.0.
