# Markdown Code Span and Authoring Contract Design

**Date:** 2026-07-14  
**Issue:** [#484](https://github.com/dowdiness/loom/issues/484)  
**Status:** Draft — review required

## Goal

Make CommonMark code spans semantically correct while retaining enough lossless,
snapshot-scoped syntax information for the planned block editor to assist an
author typing an unmatched backtick run.

This design separates three concerns:

1. **CommonMark semantics:** a successful code span has a normalized rendered
   value; an unmatched backtick run is ordinary literal text.
2. **Source fidelity:** raw delimiters and raw content remain recoverable from
   existing source origins for rewrites and formatting.
3. **Authoring assistance:** a Markdown-local facade reports unmatched
   backtick runs as neutral facts. The block editor decides whether to decorate
   them or offer a completion.

## Scope

### Included

- CommonMark 0.31.2 code span delimiter matching and content normalization.
- Existing `MarkdownIR::InlineCode` origin and content-origin policy.
- Literal fallback for unmatched backtick runs.
- A Markdown-local, parser-result-based authoring fact for unmatched backtick
  runs.
- Snapshot-lifetime rules for authoring fact ranges.
- Focused parser, MarkdownIR, adapter, rewrite, and authoring-fact tests.
- A proposed amendment to the Markdown inline native-only ADR.

### Excluded

- `ParserContext` conditional-commit APIs or a change to `lookahead`.
- `GrammarIr` variants, loomgen annotations, and #603.
- Emphasis/strong-emphasis delimiter resolution.
- Inline links, images, and reference-link resolution.
- Generic Loom-core completion, diagnostic, or revision APIs.
- Automatic delimiter pairing, warning UX, quick fixes, and broad CommonMark
  fixture promotion; #395 remains the broad-fixture issue.

## Existing Boundaries to Preserve

`MarkdownIR::InlineCode(value, origin, content_origin)` already separates the
normalized semantic value from raw source locations:

- `origin` covers the full source span, including both delimiter runs.
- `content_origin` covers the raw source between delimiters.
- `value` is the rendered CommonMark code-span value.

No extra MarkdownIR field is introduced for delimiter length or normalized
source. Delimiter spelling and length remain derivable from the original
source slice described by `origin`; the raw interior remains derivable from
`content_origin`.

`Block` / `Inline` remain the compact editor projection. They do not gain
editor interaction state. `UnmatchedBacktickRun` facts remain outside
MarkdownIR and outside `Block` / `Inline`.

## Code Span Semantic Contract

### Delimiter runs

The lexer produces one existing `Backtick` token for a maximal contiguous
backtick run. The token enum stays payload-free; the parser derives run length
from that token's source slice through `ParserContext::current_token_text()`.
It must not reconstruct a run from a sequence of single-backtick tokens.

A code span is formed by a left-to-right parse of the inline token stream:

- a backtick run of length `n` begins a code span only when the parser finds
  the next eligible backtick run of the same length `n` for that parse;
- backtick runs of another length inside a successful span are raw content;
- after a successful pair is consumed, its interior is not reconsidered as
  inline syntax;
- a run that is not consumed by any successful code-span delimiter pair is
  emitted as literal text, after which ordinary inline parsing continues.

The final clause is essential. An unmatched run owns only its own source range;
it never owns the remaining inline container. For example, the unmatched
backtick in `` `foo *bar* `` is literal text while the following emphasis still
parses under the applicable emphasis rules.

### Normalized value

For a successful span:

1. Replace every line ending in raw content with one ASCII space.
2. If the resulting content starts and ends with an ASCII space and contains at
   least one non-space character, remove exactly one leading and exactly one
   trailing ASCII space.
3. Preserve every other character and interior space exactly.

The `InlineCode` semantic value is this normalized result. `content_origin`
continues to identify the unnormalized raw content range. Every successful code
span has a nonempty raw content interval: adjacent delimiters form one maximal
backtick run rather than an opening and closing pair. A raw interval containing
only spaces remains nonempty because the boundary-space rule does not trim it.

### Literal fallback

An unmatched backtick run is valid CommonMark input. The concatenated semantic
text of the MarkdownIR and existing `Inline` projection preserves the literal
source text:

```text
`foo  →  "`foo"
```

This is a semantic-content example, not a requirement to coalesce the delimiter
and following text into one AST node.

It does not produce an `ErrorNode`, `Recovered` MarkdownIR node, parser
diagnostic, or `Inline::Error` solely because it is unmatched.

## Block Editor Authoring Contract

### Neutral syntax fact

The block editor needs interaction assistance without changing document
semantics. A Markdown authoring facade therefore derives this fact from the
completed parser result:

```text
UnmatchedBacktickRun {
  range
  run_length
}
```

The fact means:

> In this inline parse result, this maximal backtick run was not consumed by
> any successful code-span delimiter pair and was interpreted as literal text.

It does not claim that the run is a code-span opener, a parser error, a warning,
or a completion command. The fact range covers the run alone, never following
inline content.

### Snapshot lifetime

Facts are delivered by the Markdown authoring integration as part of one
parser/source snapshot. Their ranges are valid only for that snapshot's source
revision.

The authoring integration, not MarkdownIR, owns the revision association.
Before implementation, the integration must map these facts onto the concrete
host snapshot identity used by the block-editor pipeline; it must not introduce
a second universal `Revision` or snapshot abstraction in Loom.

Consumers must discard facts when their source snapshot no longer matches the
current editor document. They must request facts from the latest parser result
rather than translating stale offsets themselves.

### Initial editor policy

The initial block-editor policy is deliberately conservative:

- show a neutral, non-error decoration only while the cursor is relevant to an
  unmatched run;
- offer an explicit completion that inserts a closing run with the same length;
- do not auto-pair on typing;
- do not show a parser warning or problem-list diagnostic;
- do not add source changes without an explicit editor action.

The fact is data, so later editor features—hover help, accessibility narration,
quick fixes, or team-specific lint—can consume it without changing parser
semantics. A shared cross-language authoring-fact abstraction is deferred until
another language proves the same range, lifecycle, and state contract.

## Alternatives Considered

### Treat unmatched runs as parser errors

Rejected. Every character sequence is valid CommonMark. An unmatched run is
literal text, not malformed syntax. Mapping it to `Inline::Error` would make
semantic projections, HTML, formatting, and source transforms disagree with
CommonMark.

### Put editor candidate state in `Block` / `Inline`

Rejected. These are compact editor projections, not interaction-state storage.
Embedding completion or decoration state would couple Markdown semantics to one
editor UX and enlarge a compatibility surface without a second consumer.

### Expose raw CST directly to the block editor

Rejected. The existing architecture keeps `SyntaxNode`, parser diagnostics, and
Loom/Seam internals behind language-owned authoring integration. The facade may
inspect CST internally, but editor consumers receive language-owned facts.

### Add a generic conditional-commit primitive

Rejected. Code-span parsing is Markdown-local. It supplies no second
policy-independent consumer for #560 and does not justify a `ParserContext` or
Grammar IR API.

### Add a generic `InlineAuthoringFact` type now

Rejected. Only unmatched backtick runs have a demonstrated consumer. A generic
union before a second compatible syntax fact would be a premature abstraction.

## Compatibility

- `parse`, `parse_markdown`, `parse_cst`, and `markdown_grammar` signatures stay
  unchanged.
- `ParserContext::lookahead` remains unconditional rollback lookahead.
- `GrammarIr` remains closure-free and data-only.
- Existing `Block` / `Inline` APIs do not gain authoring metadata.
- Source-preserving rewrite continues to use existing `MarkdownIR` origins.

## Validation Contract

Focused tests must establish:

1. Matching delimiter runs require equal length; unequal runs remain raw content
   within a successful span or literal text when unmatched.
2. Line endings, boundary-space removal, and interior spaces follow CommonMark
   normalization exactly; inputs that only appear to be empty delimiter pairs
   are literal maximal runs, not successful spans.
3. An unmatched run becomes text and does not emit a parser diagnostic or
   `Inline::Error`.
4. An unmatched run does not prevent subsequent inline syntax from being parsed.
5. `InlineCode.origin` covers raw delimiters and `content_origin` covers the
   nonempty raw interior of every successful span.
6. MarkdownIR, mdast, CommonMark HTML, canonical formatting, and
   source-preserving rewrite consume the semantic value and raw origins through
   their established responsibilities.
7. The authoring facade reports only runs classified as literal by the parser
   result; its fact range covers the run alone.
8. An authoring fact from an older parser/source snapshot is not applied after
   an editor source update.
9. No touched public Loom-core API or Grammar IR interface changes.

## Proposed ADR Amendment

The implementation phase proposes an update to
[Markdown Inline Parsing Stays `@native`](../../decisions/2026-07-06-markdown-inline-native-only.md),
subject to design review and explicit approval.

The amended ADR will retain the current boundary: Markdown inline parsing is
not a current loomgen generation target, and `GrammarIr` remains data-only and
closure-free. It will correct two over-broad claims:

1. Runtime mutable algorithm state does not itself imply that an immutable,
   reified IR configuration is impossible; runtime state and IR data are
   separate concerns.
2. Code spans, emphasis, links, and reference links have different generation
   constraints and must be evaluated separately.

The amendment will also state that native Markdown code-span and authoring
support is compatible with the no-generation boundary. It will not authorize a
new Grammar IR feature.
