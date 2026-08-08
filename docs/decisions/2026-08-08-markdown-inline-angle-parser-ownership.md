# ADR: Markdown inline-angle parser ownership

**Date:** 2026-08-08
**Status:** Accepted
**Implementation plan:** [GitHub issue #895](https://github.com/dowdiness/loom/issues/895)
**Related decision:** [Markdown typed-angle CST compatibility](2026-08-06-markdown-typed-angle-cst-compatibility.md)

## Context

The typed-angle migration added append-only CST nodes for URI autolinks, email
autolinks, and inline HTML, then moved their production emission into the
container-local inline plan. During that migration the lexer still classified
complete inline HTML, collapsed it into one `Text` token, and built a
source-wide delimiter index after the first `<`. The parser consequently kept a
compatibility branch that upgraded those collapsed tokens to `InlineHtmlNode`.

That temporary path gave the lexer and parser overlapping semantic ownership,
made raw tokenization depend on complete angle classification, and paid for an
index broader than the inline container that consumed it. MarkdownIR lowering
already treats typed CST nodes as authoritative and does not need a generic-text
angle classifier.

## Decision

The Markdown lexer emits source-faithful facts only:

- unescaped `<` and every `>` are individual `Text` token boundaries in inline mode;
- an odd-backslash-escaped `<` stays in its maximal literal text run and cannot
  open an angle candidate;
- backtick runs retain their existing `Backtick` token shape;
- ordinary text remains maximal between semantic boundaries;
- block-HTML opening remains lexer-owned because it selects a lexical mode.

The container-local inline plan is the sole production authority that classifies
URI autolinks, email autolinks, and inline HTML. It reconstructs only the current
inline container, builds its bounded delimiter index only when that container
contains `<`, resolves code/link conflicts, and emits the existing typed CST
nodes. Parser branches that recognize lexer-collapsed `<...>` tokens are removed.
MarkdownIR and legacy `Block` conversion project typed nodes and never upgrade
generic `TextToken` angle spelling.

No token kind, syntax raw kind, MarkdownIR variant, public role, parser entry
point, cache, or generic Loom API is added or renumbered.

## Behavioral boundary matrix

| Axis | Required cases |
| --- | --- |
| Syntax form | URI autolink, email autolink, open/close/self-closing tag, comment, processing instruction, declaration, CDATA, malformed angle text, backtick-bearing HTML |
| Terminator | LF, CRLF, CR, EOF; multiline candidate ending before a Setext boundary |
| Operation | raw tokenization; fresh CST/diagnostics; MarkdownIR and HTML conversion; incremental construct, destroy, boundary move, content edit, and restore |
| Ownership context | top-level paragraph, block quote, list continuation with excess indentation, link/image label, valid and literal link destination, invalid reference-definition fallback, code span, and block HTML |

Acceptance is fail-closed: CST spelling must equal the source, diagnostics and
semantic origins must stay valid, shared CommonMark examples must not pass via
`Unsupported`, malformed `Raw`, `Recovered`, skip, or xfail assistance, and
fresh/incremental results must agree at every observable seam.

## Rationale

Angle meaning depends on code-span opacity, link/image boundaries, destinations,
and container continuation. Those facts are available together in the existing
inline plan but not at the raw lexer boundary. Keeping classification in that
deterministic functional core gives one precedence authority while leaving the
lexer and parser shell responsible only for token and CST emission.

The existing `InlineAngleDelimiterIndex` remains private and container-local.
Its bounded lookup behavior prevents repeated scans of long malformed angle
candidates without reintroducing a document-wide cache or a second semantic
authority.

## Consequences

`tokenize` now exposes valid inline HTML as source-faithful angle and text facts
instead of a collapsed `Text("<...>")` token. This is an intentional observable
raw-token change; all existing token and syntax raw IDs remain stable.

The source-wide lexer angle index, lexer inline-HTML classifier call, and parser
collapsed-token compatibility branches are removed. Block HTML lexing is
unchanged. Typed CST consumers, canonicalization, adapters, projection identity,
and reuse continue through their existing generic or typed-node paths.

Migration performance is certified on JavaScript and wasm-gc with paired
comparisons from the pre-inline-HTML base and from the immediately preceding
migration commit. Release contract gates remain separate from diagnostic
microbenchmarks; unstable measurements cannot establish acceptance.
