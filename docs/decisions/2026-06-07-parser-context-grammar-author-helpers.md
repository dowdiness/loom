# ADR: ParserContext Grammar-Author Convenience Helpers

**Date:** 2026-06-07
**Status:** Accepted
**Issue:** [#219](https://github.com/dowdiness/loom/issues/219)
**Follow-up:** [#251](https://github.com/dowdiness/loom/issues/251)
**Implementation plan:** N/A — issue-scoped additive API, no plan document.

## Context

`ParserContext[T, K]` is the grammar-author interface for hand-written Loom
recursive-descent parsers. The framework already owns token cursor movement,
trivia skipping, diagnostic counting, event emission, and source-span lookup.
Before this decision, several examples still reached into `ParserContext` fields
or repeated cursor scaffolding for common grammar tasks:

- bounded max-error guards read `ctx.error_count` directly;
- grammar code scanned `position`, `token_count`, and token access closures to
  get current token text;
- simple token-stream skeletons needed a local helper to emit the current token
  using the token's own raw kind.

Issue #219 collected these repeated patterns from the Lambda, JSON, Graph DSL,
and MoonBit examples. The MoonBit skeleton also showed a larger preserving-token
balanced-scan pattern while parsing coarse top-level items, but that pattern has
not yet repeated across independent grammars.

The architecture docs say `ParserContext` internals are not the grammar-author
contract, but MoonBit currently exposes struct fields in generated interfaces.
That broader boundary needs a separate stabilization decision.

## Decision

Add a small, additive `ParserContext` helper set for repeated grammar-author
operations:

- `ctx.too_many_errors(max)` returns whether parser diagnostics have reached the
  max-error threshold (`>= max`).
- `ctx.current_token_text()` returns a zero-copy `StringView` for the current
  non-trivia token, or an empty view at EOF/invalid spans.
- `ctx.current_token_range()` returns the current non-trivia token range, or a
  zero-width range at source end at EOF/invalid spans.
- `ctx.emit_current_token()` consumes and emits the current token using the
  token's own raw kind.

Keep `current_token_position` internal. It exists to share cursor logic inside
`ParserContext`; it is not a public grammar-author API.

Document `emit_current_token()` as valid only when `T.to_raw()` is also the CST
leaf kind. Grammars with a separate syntax-kind layer should map `ctx.peek()` to
`K` and keep using `emit_token(kind)`.

Do not add a preserving-token balanced-scan helper yet. `skip_until_balanced` is
recovery-oriented and emits skipped tokens under an error node. Grammar scans
that preserve normal token leaves while tracking delimiter depth should remain
local scaffolding until at least one more grammar repeats the same need.

Track the remaining `ParserContext` field-visibility/stability boundary in
follow-up issue #251 rather than solving it in this additive helper PR.

## Rationale

The accepted helpers each correspond to repeated, low-level access patterns that
belong to the parser cursor owner rather than individual grammars. They reduce
copy-paste cursor code while keeping the public surface small.

`too_many_errors(max)` intentionally exposes the policy grammar authors already
use without exposing the raw counter as the preferred API. Returning `>= max`
keeps existing loop and guard behavior source-compatible.

`current_token_text()` and `current_token_range()` centralize trivia skipping and
invalid-span fallback at the layer that owns token indexing. Returning views and
ranges keeps them cheap and consistent with Loom's UTF-16 source-span model.

`emit_current_token()` is useful for token-stream skeleton grammars, but it would
be wrong for languages whose token enum and syntax-kind enum differ. The method
is accepted because the documentation makes that boundary explicit and existing
examples with a separate syntax-kind layer continue to use `emit_token(kind)`.

The preserving balanced-scan helper is deliberately deferred. The MoonBit
skeleton is real evidence, but a general helper would need a carefully designed
contract around boundaries, delimiter depth, token preservation, diagnostics,
and incomplete placeholders. One grammar is not enough evidence for that public
shape.

## Consequences

Grammar examples can avoid direct reads of parser error and cursor state for the
common cases covered by these helpers. Future grammar-author documentation should
teach the helper methods first.

The public `ParserContext` surface grows, but remains additive and narrow.
Existing grammars remain source-compatible.

The project still needs to decide how strongly to enforce the documented
`ParserContext` boundary before stabilization. Today the examples move in the
right direction, but generated interfaces can still expose raw parser fields;
issue #251 tracks that larger API-boundary work.

Future helper proposals should follow the same bar: require concrete repeated
grammar-author use, keep internal cursor machinery private where possible, and
prefer documenting grammar-local scaffolding over prematurely stabilizing broad
combinators.
