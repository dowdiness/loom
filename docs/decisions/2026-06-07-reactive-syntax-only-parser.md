# ADR: Reactive syntax-only parser for non-`Eq` AST integrations

**Date:** 2026-06-07
**Status:** Accepted
**Issue:** [#218](https://github.com/dowdiness/loom/issues/218)
**Qualifies:** [2026-04-17: Unified Parser](2026-04-17-unified-parser-proposal.md)
**Implementation plan:** N/A — issue-scoped additive API, no plan document.

## Context

The unified reactive parser introduced by the 2026-04-17 ADR publishes a
coherent source, CST, AST, and diagnostics snapshot through `Parser[Ast]`. That
snapshot is backed by `@incr` inputs and derived views, so `Parser[Ast]` requires
`Ast : Eq` for structural backdating at the snapshot and AST-view boundaries.

That constraint is acceptable for grammars whose ASTs are designed for Loom. It
blocks integrations with production parser payloads that do not expose or
naturally derive equality.

The MoonBit parser skeleton exposed this problem. The official MoonBit AST and
token payloads are not naturally `Eq`, so the skeleton had to publish a coarse
`MoonbitParseShell` placeholder merely to access Loom's reactive CST and
diagnostics surface.

Downstream consumers that only need source, CST, diagnostics, and reuse metadata
should not have to invent placeholder ASTs. Existing `Parser[Ast]` behavior for
`Ast : Eq` grammars should remain stable.

## Decision

Add a syntax-only reactive parser path alongside `Parser[Ast]`:

- `SyntaxGrammar[T, K]` describes the lexer, language spec, and incremental
  relex/block-reparse configuration without an AST fold.
- `SyntaxParser` wraps the same `ImperativeParser` engine with `Ast = Unit` and
  publishes `source`, `syntax_tree`, `diagnostics`, and a `SyntaxSnapshot` view.
- `SyntaxSnapshot` keeps source, recovered syntax tree, diagnostics, and reuse
  count coherent, but has no AST field.
- `new_syntax_parser(source, syntax_grammar, runtime?)` is the public factory.
- `Grammar::to_syntax_grammar()` projects an AST grammar to its syntax-only
  facade, reusing the same lexer/spec/reparse configuration while intentionally
  dropping the fold.

Keep `Parser[Ast]` and `new_parser` unchanged for grammars whose AST satisfies
`Eq`. `SyntaxParser` is not a replacement for `Parser[Ast]`; it is the reactive
CST/diagnostics specialization for integrations that do not have an `Eq` AST or
do not need an AST view.

The token type bound remains `T : Eq` for syntax-only parsing because the
incremental buffer and reuse code compare token sequences.

For external lexers with rich non-`Eq` payloads, adapt them at the Loom boundary.
Use a lightweight stable wrapper that keeps the official kind or class required
by the grammar. CST spans keep the source text, and downstream projection code
can rebuild richer payloads when needed.

## Rationale

A user-supplied AST equality or fingerprint strategy would solve some
integrations, but it still forces every reactive CST/diagnostics consumer to
provide an AST fold. That keeps placeholder ASTs in the common syntax-only case
and expands the parser backdating contract before there is a clear need.

A documented wrapper-only pattern would avoid new API surface, but it would make
non-`Eq` integrations carry boilerplate just to discard it. The framework can
provide a clearer boundary: if callers need an AST view, use `Parser[Ast]`; if
they need only syntax and diagnostics, use `SyntaxParser`.

This decision qualifies, but does not reverse, the unified parser ADR. The
single edit/reset parser engine remains the source of incremental reuse. The new
reactive handle is a view specialization over that engine, not a return to the
old split between imperative and reactive parsers.

## Consequences

Integrations with non-`Eq` official ASTs can publish reactive CST and diagnostics
without placeholder ASTs. Downstream semantic projections can attach to
`parser.runtime()` and derive their own last-good or non-`Eq` state policy from
`syntax_tree()` and `diagnostics()`.

Existing `Parser[Ast]` users keep their current API and backdating behavior. The
new syntax-only path adds public API surface that must be documented and kept in
sync with the generated `.mbti` interfaces.

The token equality requirement is still explicit. Non-`Eq` token payloads need a
stable wrapper at the Loom grammar boundary; this is narrower than requiring the
full official AST or token payload graph to implement equality.
