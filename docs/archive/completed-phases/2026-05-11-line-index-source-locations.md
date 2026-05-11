# Line Index Source Locations Plan

**Status:** Complete

Completed by PR #112 on 2026-05-11. The merge added public `LineIndex`,
`LineCol`, and `LineRange` helpers; diagnostic line/column formatting helpers;
recoverable lexer error-token messages; JSON/Lambda grammar wiring for
message-preserving lexer errors; and Unicode-safe JSON string recovery fixes
from follow-up review.

Decision record:

- [ADR 2026-05-11: Derived Source Locations](../../decisions/2026-05-11-derived-source-locations.md)
- [ADR 2026-05-11: Major Plan Closure Decision Records](../../decisions/2026-05-11-major-plan-closure-decision-records.md)

## Goal

Add a small, derived source-location layer that maps loom's canonical
UTF-16/code-unit offsets to line/column positions for diagnostics and editor
display.

The parser, token buffer, CST, and edit machinery should continue to use
offsets and lengths as the canonical coordinate system. Line/column data should
be computed from source text at presentation boundaries.

## Coordinate Semantics

- Lines are 0-based.
- Columns are UTF-16/code-unit offsets within a line.
- Source offsets are clamped to `[0, source.length()]`.
- `\n`, `\r\n`, and lone `\r` each count as one line break.
- Non-BMP characters such as emoji advance the column by 2 because MoonBit
  string offsets and loom token lengths are UTF-16 code-unit offsets.

These semantics match `Edit`, `TokenInfo.len`, token starts, CST text lengths,
and common LSP position conventions.

## Non-Goals

- Do not store line/column on `TokenInfo`.
- Do not store line/column on `Diagnostic`.
- Do not store line/column on CST nodes or syntax nodes.
- Do not change parser reuse decisions or CST span computation.
- Do not add parser-level diagnostic APIs in the first patch.
- Do not implement incremental `LineIndex::apply_edit` in the first patch.

## Implementation Steps

1. Add `loom/src/core/line_index.mbt`.

   Public API:

   ```mbt
   pub(all) struct LineCol {
     line : Int
     column : Int
   }

   pub(all) struct LineRange {
     start : LineCol
     end : LineCol
   }

   pub struct LineIndex {
     // private fields
   }

   pub fn LineIndex::new(source : String) -> LineIndex
   pub fn LineIndex::line_col(self : LineIndex, offset : Int) -> LineCol
   pub fn LineIndex::line_range(
     self : LineIndex,
     start : Int,
     end : Int,
   ) -> LineRange
   ```

2. Implement `LineIndex::new`.

   Build an array of line starts:

   - always include `0`
   - for `\n`, push the next offset
   - for `\r\n`, push the offset after the `\n`
   - for lone `\r`, push the next offset
   - advance through all other characters with the shared Unicode-safe offset
     helper where appropriate

3. Implement offset lookup.

   `LineIndex::line_col(offset)` should:

   - clamp the input offset
   - find the greatest line start `<= offset`
   - return `{ line, column: offset - line_start }`

   A binary search is preferred. A linear implementation is acceptable only if
   the API is kept private until optimized; because this is a public helper,
   implement binary search from the start.

4. Add diagnostic helpers in `loom/src/core/diagnostics.mbt`.

   Keep existing `format_diagnostic(d)` unchanged.

   Add:

   ```mbt
   pub fn[T] diagnostic_line_range(
     d : Diagnostic[T],
     index : LineIndex,
   ) -> LineRange

   pub fn[T] format_diagnostic_with_line_col(
     d : Diagnostic[T],
     index : LineIndex,
   ) -> String
   ```

   The string format can be simple and stable, for example:

   ```text
   <message> [<start-line>:<start-column>,<end-line>:<end-column>]
   ```

5. Add focused tests in `loom/src/core/line_index_wbtest.mbt`.

   Cover:

   - empty source
   - single-line offsets
   - LF newline
   - CRLF newline
   - lone CR newline
   - non-BMP UTF-16 column width
   - negative, EOF, and out-of-range clamping
   - diagnostic line-range formatting

6. Export the API from `loom/src/loom.mbt`.

   Re-export:

   - `LineCol`
   - `LineRange`
   - `LineIndex`
   - `diagnostic_line_range`
   - `format_diagnostic_with_line_col`

7. Regenerate generated interfaces.

   Run `moon info` in the `loom/` module so `loom/src/pkg.generated.mbti` and
   `loom/src/core/pkg.generated.mbti` reflect the new public API.

## Deferred Follow-Up

Parser-level convenience APIs should be a separate design; see the active
follow-up plan:

- [../../plans/2026-05-11-post-112-follow-ups.md](../../plans/2026-05-11-post-112-follow-ups.md)

`Parser::diagnostics()` and `ImperativeParser::diagnostics()` currently expose
`Array[String]`, so structured diagnostic spans are erased at that boundary.
Adding `Parser::line_index()` or `diagnostics_with_line_col()` is useful only
after deciding whether parser APIs should retain structured diagnostics.

If line-index construction shows up in profiles, add an incremental
`LineIndex::apply_edit(old_source, new_source, edit)` later. The first patch
should rebuild from source text for simplicity and correctness.

## Verification

Run:

```bash
rtk moon fmt
rtk moon check
rtk moon test
rtk moon info
rtk git diff --check
```

Also run focused tests from the `loom/` module:

```bash
cd loom
rtk moon test
rtk moon info
```
