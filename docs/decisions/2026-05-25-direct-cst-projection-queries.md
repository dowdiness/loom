# ADR: Projection-friendly Direct CST Queries

**Date:** 2026-05-25
**Status:** Accepted
**Issue:** [#153](https://github.com/dowdiness/loom/issues/153)
**Implementation:** [PR #154](https://github.com/dowdiness/loom/pull/154)

## Context

Loom and seam are library surfaces for language authors, not just parser
internals. Projection authors often validate concrete syntax before lowering a
CST into a semantic model or private projection IR. That validation needs to
ask questions about the immediate shape of a syntax node.

A common footgun is using a recursive token search for semantic validation. For
nested callback or method syntax, a recursive search can accept invalid input by
finding a token inside a descendant node. For example, a projection that should
accept `.fast(2)` can accidentally accept `.fast(slow(2))` if it searches for
any descendant `NumberToken` instead of a direct argument token.

The existing `SyntaxNode` helpers already operate on direct visible children,
with `RepeatGroup` nodes flattened as transparent structure. However, names
such as `find_token` and `tokens_of_kind` do not make the direct-child boundary
obvious enough for library users reading or writing projection code.

## Decision

Add explicit projection-oriented direct-child query helpers on `SyntaxNode`:

- `direct_tokens_of_kind(kind : RawKind) -> Array[SyntaxToken]`
- `direct_token_of_kind(kind : RawKind) -> SyntaxToken?`
- `direct_children_of_kind(kind : RawKind) -> Array[SyntaxNode]`

Document the direct-visible-child contract:

- `RepeatGroup` nodes are transparent, so repeated grammar elements appear as
  direct siblings.
- Ordinary interior nodes are not searched.
- Projection and semantic-validation code should prefer the explicit
  `direct_*` names when checking argument shape.

Keep `find_token` and `tokens_of_kind` available for compatibility, and document
that they are direct-visible-child helpers rather than recursive descendant
queries.

Do not introduce a larger CST query DSL for this issue. Add arity-enforcing
helpers, recursive traversal helpers, or a broader query language only after
smaller direct-child helpers prove insufficient.

## Rationale

Library UX should make the safe path obvious. The `direct_*` names encode the
shape boundary at the call site, which makes projection code easier to write and
easier to review.

The small helper set solves the immediate validation bug pattern without
requiring language authors to adopt a new abstraction. It also preserves seam's
current simple traversal model: direct navigation remains cheap and explicit,
while recursive extraction remains possible when a caller writes that traversal
intentionally.

Flattening `RepeatGroup` keeps the API aligned with the visible CST shape that
language authors already work with. The helpers ask about direct semantic
siblings, not parser-internal repetition scaffolding.

## Consequences

`SyntaxNode` gains a small additive public API. Existing callers do not need to
migrate, but new projection code should prefer `direct_*` helpers for semantic
validation and argument-shape checks.

Documentation must avoid implying that token queries are recursive unless a
future helper is explicitly designed and named for recursive descendant search.
If recursive query helpers are added later, their names should make recursion
visible, for example with a `descendant_*` or `recursive_*` prefix.

Future arity helpers such as `expect_one_direct_token` can build on this API if
projection authors need stronger validation ergonomics.
