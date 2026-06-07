# ADR: Harden seam Source-Span Token and Parser Reuse APIs

**Date:** 2026-05-30
**Status:** Accepted

## Context

Issue #61 moved `CstToken` to source-span storage, which made backing-buffer
ownership observable through `CstToken::source()`. Issue #187 then added a
parser-owned unchecked rebase path so the generic parser could skip a redundant
text-match pass after `ReuseCursor` had already validated a reused subtree.

Both APIs are sharp at the seam stabilization boundary:

- application code should depend on token content and offsets, not the identity
  of the `String` that happens to back a token view;
- application code should use `ParseEvent::ReuseNode` for public subtree reuse,
  because that path copies/canonicalizes token text and avoids retaining old
  source buffers;
- parser-owned rebase hooks must remain available because `loom` parser
  internals live outside the `seam` package.

## Decision

Keep the parser-owned capabilities, but move sharp parser-owned storage/recovery
hooks behind explicit unstable names and deprecate accidental-looking names:

- `CstToken::is_source_backed()` is the stable token-provenance predicate for
  distinguishing lexer/source-span tokens from parser-synthetic zero-width
  recovery placeholders. A richer provenance enum remains deferred; the boolean
  predicate is intentionally enough for the current source-backed vs synthetic
  split and can coexist with a future enum.
- `CstToken::unsafe_backing_source()` exposes backing storage identity for
  parser/source-retention white-box checks only.
- `CstToken::source()` remains as a deprecated compatibility alias.
- `EventBuffer::push_parser_reuse_node_rebased(...)` is the checked parser-owned
  source-span rebase hook.
- `EventBuffer::push_parser_reuse_node_rebased_unchecked(...)` is the validated
  parser-owned rebase hook used after `ReuseCursor` proves the old subtree still
  matches the current token stream.
- `EventBuffer::push_parser_synthetic_zero_width_token(...)` is the unstable,
  trusted parser-owned recovery hook for parser-synthetic zero-width tokens.
  `EventBuffer::push_synthetic_zero_width_token(...)` remains as a deprecated
  compatibility alias.
- `EventBuffer::push_reuse_node_at(...)` and
  `EventBuffer::push_reuse_node_at_unchecked(...)` remain as deprecated
  compatibility aliases.
- `ParseEvent::ReuseNode` remains the stable application-facing reuse API.
- `ParseEvent` intentionally does not grow a synthetic-token variant before
  seam stabilization; synthetic emission stays on `EventBuffer` and remains
  zero-width-only until a concrete non-zero-width use case exists.

## Rationale

A visibility-only change would either break the generic parser boundary or force
parser internals into `seam`. A docs-only change would leave stable-looking API
names for backing-source identity and trusted parser machinery. The new names
make the intended audience visible at call sites while preserving source
compatibility during the pre-stabilization window. `is_source_backed()` keeps
stable vocabulary at the token-inspection boundary without exposing backing
storage identity or tree-position ownership.

## Consequences

- Public application code should use `CstToken::text()` for content,
  `is_source_backed()` for provenance, and `SyntaxToken`/structural offsets for
  tree position.
- `start_offset()` / `end_offset()` remain backing-source span coordinates, not
  structural position in a containing tree.
- Backing-source identity is explicitly unstable and may change before seam
  stabilization.
- Parser-owned rebase remains available for #187's validated fast path and still
  rebuilds fresh current-source-backed CST objects; it does not direct-splice old
  nodes or retain old source buffers.
- Parser-owned synthetic emission remains intentionally narrow: zero-width
  recovery placeholders only, through `EventBuffer` rather than public
  `ParseEvent`.
- The deprecated compatibility names can be removed before a future stable seam
  release once downstream callers have migrated.
