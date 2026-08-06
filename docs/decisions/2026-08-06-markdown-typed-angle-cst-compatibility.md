# ADR: Markdown typed angle CST compatibility

**Date:** 2026-08-06
**Status:** Accepted
**Implementation plan:** [GitHub issue #891](https://github.com/dowdiness/loom/issues/891)

## Context

Markdown's inline-plan migration will eventually emit typed CST nodes for URI
autolinks, email autolinks, and inline HTML. The production lexer and parser
still own the legacy collapsed `TextToken` representation until #893 and #894.
Consumers nevertheless need a compatibility surface that can read fixtures and
future typed CSTs without changing Loom's generic parser contracts.

## Decision

Append these `SyntaxKind` values after the existing raw-kind registry:

- `UriAutolinkNode` — raw kind 42
- `EmailAutolinkNode` — raw kind 43
- `InlineHtmlNode` — raw kind 44

Typed nodes preserve their original source-backed children and origins. Markdown
IR lowering reads the typed node kind directly and projects it to the existing
`Autolink` or `InlineHtml` IR variants. It continues to read legacy `TextToken`
angle spellings during the expand phase; that path remains temporary compatibility,
not a second typed-node authority. The legacy Block adapter receives the same
projection through its existing inline conversion seam.

No token, MarkdownIR variant, parser entry point, generic Loom API, or public
Markdown role is added. The typed fixtures are standalone constructed
compatibility inputs, using the exact metadata domain produced by
`LanguageSpec::new(ErrorToken, ErrorNode, ...)`: trivia
`[ErrorToken.to_raw()]`, error `ErrorNode`, and incomplete `ErrorNode`.
Their private test helper constructs an equivalent domain without exposing or
accessing generic policy internals. Canonical policy provenance remains owned
privately by `LanguageSpec` under #896; production composition and emission
remain owned by #893/#894.

## Rationale

The raw-kind append preserves stored CST compatibility and lets standalone
constructed fixtures enter at the highest existing MarkdownIR seam. Keeping
lowering as projection prevents consumers from reclassifying typed source text
and lets #893/#894 own production composition, emission, and removal of legacy
angle classification. The fixture's equivalent metadata domain preserves the
same CST composition contract as `markdown_spec` without taking ownership of
its private canonical policy. Existing role, canonicalization, adapter,
projection-identity, and reuse contracts remain language- or representation-
generic.

## Consequences

Typed CST fixtures can be lowered, adapted, rendered, and identity-tested now,
with exact child spelling and source origins. Production parsing remains
unchanged. Future production-emission work must keep raw kinds 0–44 stable and
must remove the temporary legacy read only under the migration tickets that own
that behavior.
