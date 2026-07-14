# Markdown Code Span and Authoring Contract Design

**Date:** 2026-07-14  
**Issue:** [#484](https://github.com/dowdiness/loom/issues/484)  
**Status:** Approved — 2026-07-14; authoring-fact delivery deferred pending a concrete editor host

## Goal

Make CommonMark code spans semantically correct while retaining lossless syntax
needed to define future editor assistance; fact delivery waits for a concrete
block-editor host that owns a parser/source snapshot identity.

This design separates three concerns:

1. **CommonMark semantics:** a successful code span has a normalized rendered
   value; an unmatched backtick run is ordinary literal text.
2. **Source fidelity:** raw delimiters and raw content remain recoverable from
   existing source origins for rewrites and formatting.
3. **Deferred authoring assistance:** a future Markdown-local facade may report
   unmatched backtick runs as neutral facts only after a concrete block-editor
   host supplies the snapshot identity that owns their ranges.

## Scope

### Included

- CommonMark 0.31.2 code span delimiter matching and content normalization.
- Existing `MarkdownIR::InlineCode` origin and content-origin policy.
- Literal fallback for unmatched backtick runs.
- Definition—but not delivery—of a future Markdown-local parser-result fact for
  unmatched backtick runs and its snapshot-lifetime rule.
- Focused parser, MarkdownIR, adapter, and rewrite tests.
- A proposed amendment to the Markdown inline native-only ADR.

### Excluded

- `ParserContext` conditional-commit APIs or a change to `lookahead`.
- GrammarIr variants, loomgen annotations, and #603.
- Markdown authoring-fact delivery, a facade, or a snapshot/revision
  abstraction before a concrete block-editor host exists.
- Emphasis/strong-emphasis delimiter resolution.
- Inline links, images, and reference-link resolution.
- Generic Loom-core completion, diagnostic, or revision APIs.
- Automatic delimiter pairing, warning UX, quick fixes, and broad CommonMark
  fixture promotion; #395 remains the broad-fixture issue.

## Existing Boundaries to Preserve

`MarkdownIR::InlineCode(value, origin, content_origin)` keeps its existing
shape:

- `origin` is the contiguous source envelope from opening through closing
  delimiter, including any structural continuation bytes inside that envelope.
- `content_origin` is `Some` only when all logical raw code content occupies one
  contiguous source slice; it is `None` when a stripped structural prefix makes
  that content discontinuous.
- `value` is the rendered CommonMark code-span value.

No MarkdownIR field or public type changes. Delimiter spelling and length are
read from the lossless CST token text. When `content_origin` is `None`, the CST
is the raw-content authority and content-only source rewrites are disabled; no
consumer may pretend the envelope is an exact content slice.

`Block` / `Inline` remain the compact editor projection. They do not gain
editor interaction state. Any future `UnmatchedBacktickRun` fact remains outside
MarkdownIR and outside `Block` / `Inline`.

## Code Span Semantic Contract

### Delimiter runs

The lexer produces one existing `Backtick` token for every maximal contiguous
backtick run, including a run preceded by backslashes. The token enum stays
payload-free; the parser derives run length from that token's source slice
through `ParserContext::current_token_text()`. It must not reconstruct a run
from a sequence of single-backtick tokens.

This is a required lexer/parser change, not a statement of current behavior.
Text lexing must stop before every backtick run instead of absorbing an escaped
run into generic `Text`.

### Container delimiter index

Before consuming an inline container, the native Markdown parser runs one
pure `ParserContext::lookahead` prepass over its token range. The prepass tracks
trailing-backslash parity for each immediately preceding `Text` token and
records every maximal run's source start, length, and outer-inline opener
eligibility. It resets that parity after any other token, newline, or inline
boundary. Parser state is restored unconditionally when the prepass returns.

The prepass builds a Markdown-local successor index: for each run, its next
equal-length run in the same inline container, if any. Actual parse dispatch
uses the current run's source start to query this index. An eligible opener
with no successor emits its whole maximal source as literal `TextToken` content;
it does not checkpoint-scan and then reparse the container. For a successful
pair, the parser emits raw interior tokens through the indexed closer once.
The closer is valid regardless of preceding backslashes; those backslashes,
unequal runs, and line endings are raw interior content because escape
processing does not apply within code spans.

This gives each container $O(T + R)$ delimiter work and $O(R)$ temporary
Markdown-local memory, where $T$ is token count and $R$ is backtick-run count.

### Inline container boundary

An inline container is one Markdown semantic inline region, not one call of the
current line-bound parser. It includes all soft-line continuations of a
paragraph, setext heading, list-item paragraph (including lazy continuation),
or block-quote paragraph. The CST block parser continues to own the
block-specific continuation decision, but it must provide one internal
container parse that uses that same decision for both delimiter indexing and
token emission. An ATX heading remains line-bound. A blank line or true block
boundary ends the container and cannot supply a code-span closer.

The baseline line-start lexer replaces opaque `IndentedCodeText` with an exact
`Indentation` token followed by normal tokens for the rest of that source line.
The indentation token preserves its exact spaces/tabs and absolute span; column
width continues to use the existing tab rules. The remaining line uses the
ordinary line-start marker classifier, preserving heading, block-quote, list,
and fence candidates after indentation.

Before classifying the remaining tokens, the CST parser captures the current
`IndentationToken` into a Markdown-local `LinePrefix` record without advancing
or emitting it. The selected block or container parser emits that exact token
as its first structural child, then uses the captured source span and column
width for list-marker indentation/width, heading and setext checks, block-quote
continuation, and nested-container minimum-indent rules. Those calculations
must not read indentation from the current marker token after decomposition.
The record resets at each physical line boundary.

The CST block parser then classifies indentation relative to its current root
or list-item context. A paragraph continuation exposes the normal inline
tokens—including maximal backtick runs—and retains `IndentationToken` as a
structural prefix. An indented-code node emits its `IndentationToken` followed
by every direct non-newline child for that physical line. Both indented-code
lowerers collect those token texts in source order, retain the existing
`line_parts` join/deindent behavior, and do not predicate collection on the
removed `IndentedCodeTextToken`. The legacy token has no compatibility path
after callers migrate.
A code span is formed by a left-to-right parse of the inline token stream:

- an eligible outer-inline backtick run of length `n` begins a code span only
  when the parser finds the next backtick run of the same length `n`;
- backtick runs of another length inside a successful span are raw content;
- after a successful pair is consumed, its interior is not reconsidered as
  inline syntax;
- a run that is not consumed by any successful code-span delimiter pair is
  emitted as literal text, after which ordinary inline parsing continues.

### CST delimiter positions

For each successful `InlineCodeNode`, the first and last direct
`BacktickToken` children are the opening and closing delimiters. They alone are
excluded by semantic conversion and MarkdownIR lowering. Every intervening
`BacktickToken` is an unequal-length raw-content run and contributes
`token.text()` exactly like other interior content.

When a code span crosses a structural continuation, the container parser keeps
the `InlineCodeNode` open while emitting the continuation newline and prefix
token (such as `BlockQuoteMarkerToken` or `IndentationToken`) as direct node
children. The CST therefore remains lossless and contiguous. Lowering skips
those structural prefix tokens from code content and returns
`content_origin = None`; it retains the full node envelope as `origin`.
Conversion must classify tokens by direct-child position and structural role,
not discard every `BacktickToken`.

Both semantic projections share the code-span normalization rule. They append
each interior raw-content token's actual source text, then normalize exactly
once. This preserves unequal interior runs while preventing projection drift.

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

This code-span-specific normalizer never calls `strip_backslash_escapes`.
Backslashes are preserved verbatim in successful code-span content, including a
backslash immediately before a closing backtick run; only the three rules above
may change the raw interior.

The `InlineCode` semantic value is this normalized result. `content_origin`
continues to identify the unnormalized raw content range. Every successful code
span has a nonempty raw content interval: adjacent delimiters form one maximal
backtick run rather than an opening and closing pair. A raw interval containing
only spaces remains nonempty because the boundary-space rule does not trim it.

### Literal fallback

An unmatched backtick run is valid CommonMark input. The parser emits the
whole maximal run as literal content, and the concatenated semantic text of
both MarkdownIR and the existing `Inline` projection preserves its actual
source text:

```text
``foo  →  "``foo"
```

This is a semantic-content example, not a requirement to coalesce the delimiter
and following text into one AST node. Neither projection may synthesize literal
backticks from the token kind: it must append the unmatched token's actual
source text, so a maximal run is not collapsed to one character.

Because uniform tokenization splits an outer escape pair at the backtick,
literal-text normalization operates on each contiguous literal-token segment
before applying backslash escapes:

```text
source:   \`
semantic: `
HTML:     <p>`</p>
```

The implementation may choose its text-node grouping, but must not strip escapes
independently from the preceding `TextToken` and the literal `BacktickToken`;
their raw origins remain source-preserving.

An unmatched run does not produce an `ErrorNode`, `Recovered` MarkdownIR node,
parser diagnostic, or `Inline::Error` solely because it is unmatched.

## Deferred Block Editor Authoring Contract

The concrete block-editor integration is not present in this repository. This
issue therefore implements no authoring facade, fact carrier, or revision
abstraction. Inventing one would assign snapshot ownership to the parser rather
than the editor host and violate the native-only boundary.

When a concrete host exists, it must derive this neutral fact from a completed
parser result:

```text
UnmatchedBacktickRun {
  range
  run_length
}
```

The fact means that a maximal unescaped outer-inline run was eligible to open,
found no equal-length closer, and was interpreted as literal text. It is not an
opener, parser error, warning, or completion command. Its range covers the run
alone; escaped or matched runs do not produce it.

The future host, not MarkdownIR or Loom core, owns the association with its
parser/source snapshot. Consumers discard facts when their source snapshot no
longer matches the editor document and request fresh facts rather than
translating stale offsets. The first editor policy remains neutral decoration
plus an explicit matching-run completion—never autopairing, diagnostics, or
automatic edits.

The implementation plan for #484 is intentionally limited to native code-span
semantics, lossless CST/source behavior, and semantic projections. A future
host-integration issue must map this fact onto the real editor snapshot type
before it may add delivery code. No shared cross-language fact abstraction is
introduced until another consumer establishes the same lifecycle contract.

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
Loom/Seam internals behind language-owned integration. If a concrete editor host
is added, its facade may inspect CST internally; no direct-CST editor API is
introduced by this issue.

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

1. Matching delimiter runs require equal length. The successful span
   `` `a``b` `` lowers to semantic code content `a``b`: its interior
   two-backtick run is preserved. Unmatched runs remain literal text.
2. Normalization replaces each line ending with one ASCII space, removes exactly
   one boundary ASCII space only when non-space content remains, preserves
   all-space content, and preserves interior and Unicode whitespace.
3. A code span across a permitted paragraph, block-quote, or list-item
   soft-line continuation is indexed as one container and normalizes its line
   ending to one ASCII space. A blank line or true block boundary cannot supply
   its closer; the preceding eligible run then follows literal fallback.
4. Baseline indentation decomposition exposes backtick runs in a valid
   list-paragraph continuation, while root- and list-relative indented code
   reassembles exact same-line text before deindent. Post-indent heading,
   block-quote, list, and fence candidates retain their block classification,
   including when they are the first indented-code content token. Parity tests
   cover marker indentation/body offsets, setext recognition, block-quote
   continuation, nested lists, and lossless `IndentationToken` parent/span
   ownership after a captured `LinePrefix`.
5. The escaped-pair example above is literal text and cannot open a code span.
   It produces the specified MarkdownIR/`Inline` semantic text and CommonMark
   HTML; its maximal token remains visible and preserves every backtick.
6. Within a successful span, a matching run preceded by a backslash closes the
   span and the backslash is preserved verbatim except for code-span line and
   boundary-space normalization.
7. A maximal unmatched run preserves every backtick in concatenated MarkdownIR
   and `Inline` semantic text; it emits no parser diagnostic or `Inline::Error`.
8. An unmatched run does not prevent subsequent inline syntax from being parsed.
9. A contiguous code span has `content_origin = Some(...)`; one crossing a
   stripped continuation prefix has `content_origin = None`, skips that prefix
   in semantic content, and rejects content-only source rewrites.
10. MarkdownIR, mdast, CommonMark HTML, canonical formatting, and
    source-preserving rewrite consume the semantic value and permitted origins
    through their established responsibilities.
11. No Markdown authoring-fact facade, snapshot/revision abstraction, or editor
    behavior is added before a concrete host supplies ownership.
12. No touched public Loom-core API or Grammar IR interface changes.
13. A stress test with many distinct, unmatched backtick runs verifies one
    delimiter-index prepass and linear token/run traversal, rejecting repeated
    scan-to-boundary work.

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

The amendment will also state that native Markdown code-span support is
compatible with the no-generation boundary. It will not authorize a new Grammar
IR feature or an authoring-fact delivery API.
