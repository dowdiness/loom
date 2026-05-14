# ADR: Use Moji At Unicode Boundary Layers

**Date:** 2026-05-11
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-05-11-post-112-follow-ups.md](../archive/completed-phases/2026-05-11-post-112-follow-ups.md)

## Context

`dowdiness/moji` provides Unicode 15.1 UAX #29 grapheme-cluster and word-boundary
segmentation for MoonBit. Its public API uses UTF-16 code-unit offsets, matching
Loom's canonical parser coordinates and CodeMirror-style editor offsets.

Loom also has small lexer helpers such as `LexCursor::advance_char` and
`next_char_offset`. Those helpers only need scalar-width progress so lexers and
recovery paths do not split surrogate pairs. They do not need grapheme or word
boundary semantics.

## Decision

Keep Loom parser, token, CST, diagnostic, and edit spans as UTF-16 code-unit
offsets and lengths.

Use `moji` for Unicode semantic boundaries at editor, diff, and presentation
layers: grapheme-aware edits, cursor movement, word movement, selection
snapping, and user-facing boundary calculations.

Do not add a direct `dowdiness/loom/core -> dowdiness/moji` dependency merely to
replace scalar stepping helpers. `next_char_offset` remains the canonical Loom
helper for lexer scalar progress. A direct `moji` dependency is acceptable later
only when Loom itself needs grapheme or word semantics, or if scalar UTF-16
decoding is split into a small leaf dependency with no Unicode table cost.

## Rationale

UTF-16 offsets are the shared coordinate contract across MoonBit strings,
`TokenInfo.len`, token starts, CST widths, diagnostics, and `Edit` ranges.
Changing that contract to grapheme counts would break parser invariants and make
incremental reuse harder to reason about.

`moji` is the right tool for Unicode user interactions. It is intentionally more
semantic than a lexer progress helper, and its grapheme/word tables should not
become a core parser dependency unless Loom needs those semantics directly.

The existing `dowdiness/text_change` package already depends on `moji`, so Loom
receives grapheme-safe contiguous text changes through that layer without adding
another core dependency edge.

## Consequences

Lexer and recovery code should use `LexCursor::advance_char` or
`next_char_offset`, not ad hoc `pos + 1`, when consuming arbitrary text.

Line/column APIs remain derived presentation helpers with UTF-16 columns.
Grapheme-aware visual columns or cursor movement should be added as separate
presentation/editor helpers instead of changing `LineIndex`.

Future work that introduces direct `moji` usage in Loom must document why UAX
#29 semantics are needed in Loom itself and add tests for non-BMP and combining
mark inputs.
