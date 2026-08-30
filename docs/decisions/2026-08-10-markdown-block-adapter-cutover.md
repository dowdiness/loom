# ADR: Markdown Block projection cutover follows staged parity gates

**Date:** 2026-08-10
**Status:** Superseded by the 2026-08-30 Markdown library API cutover
**Related:** [MarkdownIR architecture and target contract](../architecture/markdown-ir.md), [MarkdownIR performance policy](2026-06-16-markdown-ir-performance-policy.md), [Markdown projection attachment](2026-08-03-markdown-projection-attachment-boundary.md), [MarkdownIR exhaustive read view](2026-08-04-markdown-ir-exhaustive-read-view.md)
**Implementation plan:** Issue-scoped; implement with a parity-first, two-commit migration slice.

## Supersession note

The parity gates described below passed and the later cutover is now complete.
The common `parse(source, source_id?, extensions?)` entry point returns a
detached `MarkdownDocument`; the old `parse` Block signature and
`parse_markdown` were removed. `parse_block_ast` remains the explicit advanced
Block projection oracle, while `parse_cst`, `markdown_grammar`, and
`markdown_fold_node` remain available for structural consumers. The rest of
this ADR records the staged pre-cutover decision in its historical tense.

## Context

The Markdown package currently has two one-shot paths that produce the editor-facing
`Block` view:

- `parse` and `parse_markdown` fold the CST directly through
  `markdown_fold_node_with_source`.
- MarkdownIR target adapters lower `SyntaxNode` to MarkdownIR and then project the
  result through `experimental_markdown_ir_to_block`.

The MarkdownIR target contract already defines the intended internal shape as
`SyntaxNode -> MarkdownIR -> Block/Inline`, while retaining `parse`,
`parse_markdown`, `parse_cst`, `markdown_grammar`, and `markdown_fold_node` as
compatibility surfaces until parity is proven.

The two paths do not currently have identical policy for every existing `Block`
value. The direct path intentionally preserves legacy text projections for
`BlockQuoteNode` and `ThematicBreakNode`, while the current IR adapter reports
those semantic variants as `Block::Error`. The direct path also owns source-aware
code payload extraction and caller-specific soft-break behavior. MarkdownIR
stores origins rather than a copy of the complete source, so a legacy-compatible
projection needs the current source snapshot as private adapter context.

The MarkdownIR lowering path cannot be replaced with a position-independent
`CstFold`: it performs a direct recursive walk because absolute source origins
must be rebuilt after position-shifting edits. Changing the grammar's `CstFold`
contract at the same time would mix a semantic migration with parser and
performance contract changes.

## Decision

The current implementation remains on the direct high-level path:

- `parse` and `parse_markdown` currently fold through
  `fold_markdown_syntax_with_source`.
- `parse_cst`, `markdown_grammar`, `markdown_fold_node`, and the
  `Parser[Block]` compatibility path remain unchanged.
- The private source-aware MarkdownIR-to-`Block` projection is the candidate
  replacement and is not yet selected by a high-level caller.

The accepted migration is staged:

- preserve the existing parser entry points, return shapes, and error modes;
- preserve legacy `Block` semantics, including block-quote and thematic-break
  text projections, soft-break spacing, list-item newline behavior, ordered-list
  marker metadata, source-aware code values, and explicit recovery/error values;
- keep the public experimental IR adapter surface unchanged while the private
  source-aware projection reuses its semantic mapping;
- establish the direct-CST versus existing IR-backed parity fixture matrix in
  commit one without changing high-level callers;
- apply that same matrix to the source-bound document-backed projection in
  commit two; and
- defer any high-level cutover until both parity gates pass in a later,
  independently reviewable change.

Gate one compares the direct `Block` result with the existing source-aware
IR-backed projection for current parser snapshots. Gate two compares the same
direct result with the `MarkdownDocument`-backed projection. Both gates cover
block quotes, thematic breaks, soft breaks, nested lists, ordered markers,
fenced-code indentation, malformed links, escaped delimiters, recovered nodes,
CRLF/CR/EOF endings, and source-aware diagnostics. `parse_markdown` must retain
its diagnostic set and `parse` must retain its existing lex-error behavior.

The high-level switch is therefore a follow-up condition, not an effect of
this ADR or of the source-bound document commit.

## Rationale

This is the smallest parity-first slice that removes uncertainty before
changing the public high-level parse path. It follows the accepted MarkdownIR
target shape while respecting the absolute-origin and performance constraints
of direct IR lowering.

Keeping the source snapshot private to the compatibility projection preserves
the anti-CST-cloning rule: MarkdownIR remains semantic data plus origins, and
exact legacy text is recovered only by an adapter that already owns the
current source. Keeping `markdown_fold_node` and `markdown_grammar` intact
avoids forcing position-sensitive MarkdownIR through the position-independent
`CstFold` cache.

## Consequences

- Current high-level one-shot parsing still has the direct fold as its
  observable implementation; the source-aware IR-backed projection is the
  parity candidate.
- The source-bound document commit adds no editor-consumer switch. A later
  cutover may select the IR-backed path only after both parity gates pass.
- A future high-level cutover would allocate MarkdownIR, so the full-parse
  performance contract must be measured before that change.
- Existing grammar and editor-facing parser consumers do not change in this
  migration.
- The direct `markdown_fold_node` path remains an intentional compatibility
  path until a separate decision proves projection, origin, and performance
  parity.
- A future migration of `markdown_grammar` or `markdown_fold_node` requires a
  new compatibility decision rather than being inferred from this ADR.
