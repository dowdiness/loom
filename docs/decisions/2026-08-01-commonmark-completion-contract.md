# ADR: CommonMark 0.31.2 Completion Contract and Parser Seams

**Date:** 2026-08-01
**Status:** Accepted
**Issues:** [#800](https://github.com/dowdiness/loom/issues/800), [#801](https://github.com/dowdiness/loom/issues/801), [#803](https://github.com/dowdiness/loom/issues/803)
**Supporting decisions:** [#786](https://github.com/dowdiness/loom/issues/786), [#485](https://github.com/dowdiness/loom/issues/485), [#487](https://github.com/dowdiness/loom/issues/487), [#482](https://github.com/dowdiness/loom/issues/482), [#486](https://github.com/dowdiness/loom/issues/486)
**Ordered handoff:** [#799](https://github.com/dowdiness/loom/issues/799)
**Related decisions:** [MarkdownIR target contract](2026-06-15-markdown-ir-target-contract.md), [recovery adapter contract](2026-06-17-markdown-ir-recovery-adapter-contract.md), [native inline ownership](2026-07-06-markdown-inline-native-only.md), [block reparse ancestor widening](2026-07-15-block-reparse-ancestor-widening.md)
**Implementation plan:** [CommonMark completion handoff](../plans/2026-08-01-commonmark-completion-handoff.md)

## Context

The hermetic CommonMark 0.31.2 audit completes at 437 of 652 examples. The
remaining 215 examples are all mapped to existing feature areas, but their
owners did not share an exact completion definition, a single block-container
decision boundary, or a common direct-versus-incremental acceptance matrix.
Without those contracts, feature PRs could match HTML while retaining recovery,
duplicate container dispatch, or prove only direct parsing.

## Decision

### Completion means one clean semantic pipeline

The normative corpus is the checked-in CommonMark 0.31.2 specification fixture,
including its pinned checksum. Completion is exactly 652 of 652 expected HTML
results through this pipeline:

```text
official Markdown source
  -> CST + diagnostics
  -> MarkdownIR
  -> HTML adapter with RawHtmlPolicy::Passthrough
  -> exact official HTML
```

Every official example must also satisfy all of the following:

- lexing and parsing complete without process failure;
- parser diagnostics are empty;
- CST structure is valid and retains the original source text;
- MarkdownIR satisfies its origin and tree-shape invariants;
- no `Unsupported`, malformed `Raw`, or `Recovered` node assists the result;
- no skip, xfail, opaque-output equivalence, or locally waived example remains.

The official corpus is normative. Third-party parser comparisons are diagnostic
signals only. Canonical Markdown formatting and round-trip equality are not part
of this completion claim.

The audit must report parser diagnostics, `Unsupported`, malformed `Raw`,
`Recovered`, adapter-policy rejection, and HTML mismatch as separate
machine-readable categories. A matching output produced through recovery is not
a pass.

### Raw HTML policy is explicit and adapter-owned

Valid CommonMark block and inline HTML are semantic `HtmlBlock` and
`InlineHtml` nodes. They are distinct from malformed recovery `Raw` nodes.
MarkdownIR records syntax meaning and origins, not trust or sanitization.

HTML rendering adapters take an explicit `RawHtmlPolicy`:

- `Escape` is the safe default for product-facing HTML;
- `Omit` intentionally removes valid raw HTML;
- `Reject` returns a structured adapter failure;
- `Passthrough` emits raw HTML and is selected explicitly by the CommonMark
  conformance harness.

No sanitizer is introduced by this effort. mdast export is a semantic
interchange adapter, not an HTML rendering adapter: valid `HtmlBlock` and
`InlineHtml` always export as mdast `html` nodes, independent of
`RawHtmlPolicy`. A downstream mdast-to-HTML renderer must make its own explicit
raw-HTML policy choice. Malformed `Raw` and `Recovered` nodes continue to follow
the separate recovery adapter contract and never masquerade as valid mdast
`html`.

### Inline semantic distinctions remain typed

MarkdownIR distinguishes:

- `SoftBreak`, whose origin covers the source newline;
- `HardBreak`, whose typed surface records trailing-space or backslash form;
- `Autolink`, including URI/email kind, display value, destination, and origins;
- `InlineHtml`, distinct from `HtmlBlock`, literal text, and malformed `Raw`;
- `Image`, distinct from `Link`;
- inline, full-reference, collapsed-reference, and shortcut-reference link/image
  forms through typed surface metadata.

Invalid candidates remain literal text. Malformed parser structure uses explicit
recovery only when diagnostics actually exist. The editor projection may map
new semantic distinctions onto its current smaller `Inline` model for
compatibility; adapters consume MarkdownIR directly.

### Reference resolution is a two-pass document lowering

The block parser recognizes complete link-reference definitions as typed CST
blocks. Document lowering first collects them in source order into an immutable
definition table, using CommonMark label normalization and first-definition-wins
semantics. Duplicate definitions remain lossless in the CST but do not replace
the first semantic definition. Definitions do not render as flow output.

The second pass lowers inline content using that table. Resolved links and
images carry destination, optional title, semantic children or alt content,
reference form, and relevant origins. Unresolved references remain literal
content. Target adapters never rediscover definitions or inspect raw tokens to
resolve references.

### Block containers use one private Functional Core

Before widening block feature support, Markdown introduces a private
Markdown-local decision seam. Its deterministic core accepts container state
and non-consuming line facts and returns next state plus a typed block decision:

```text
BlockContainerState + BlockLineFacts
  -> (BlockContainerState, BlockDecision)
```

The state records only CommonMark-relevant container frames and continuation
facts. Observations include blankness, indentation columns, marker/fence facts,
and current block context. Decisions cover container continuation/closure, lazy
continuation, paragraph continuation, and typed block starts.

The imperative parser shell owns lookahead, token consumption, diagnostics, and
CST emission. MarkdownIR lowering consumes structural CST children in source
order; it does not repeat container dispatch. The seam is private, preserves
existing CST kinds and public parser APIs, and may initially decline to existing
behavior for unsupported cases.

This decision does not authorize a generic parser-core API, public container
IR, broad package split, lexer replacement, or unrelated parser rewrite.

### Incremental parity is a feature gate

Each remaining feature slice proves the same post-edit source through both:

```text
old parse + incremental edit    fresh parse of edited source
```

The comparison includes CST shape/source text, diagnostics with source ranges,
MarkdownIR semantics and origins, and explicit-policy HTML output. Each slice
covers construction, destruction, boundary movement, content edits, and a
malformed intermediate where applicable. Container slices additionally cover
indentation, blank lines, and lazy continuation; reference slices cover
definition add/change/remove/duplicate and label edits; inline slices cover
delimiter or raw-HTML boundaries.

Reuse counts and performance thresholds are not semantic acceptance criteria.
They may be added only after parity passes. Boundary-changing edits must prove
conservative fallback; supported fast paths may separately prove reuse.

Final evidence is the direct 652-of-652 corpus audit plus a checked-in
representative incremental matrix spanning every implemented feature family.
Running every possible edit over every corpus example is not required.

## Consequences

- Feature PRs can be small because the private container core and reference
  table define ownership without changing Loom's public parser API.
- Product-facing HTML is safe by default while conformance remains exact and
  explicitly unsafe.
- The audit can no longer hide semantic incompleteness inside a combined opaque
  category.
- M5 owns block recognition, container behavior, and reference-definition
  collection; M6 owns inline semantics and reference consumption; M7 owns the
  shared parity policy and final exit audit.
- Formatter work, editor/Canopy migration, loomgen, extensions, sanitization,
  and speculative caching remain outside this completion handoff.
