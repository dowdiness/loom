# Moji display-cell width

**Status:** Complete

Decision record: No ADR needed: this change adds a self-contained `moji`
measurement API without changing Loom's architectural boundaries; the public
contract and exclusions are recorded in this completed plan.

## Goal

Extend `dowdiness/moji` with deterministic display-cell measurement while
keeping ANSI output, terminal capability detection, wrapping, and diagnostic
layout outside the package. Text positions remain half-open UTF-16 code-unit
offsets.

## Public seam

- `display_width` returns the number of terminal cells consumed by one display
  run.
- `display_units` returns opaque units that map UTF-16 ranges to absolute
  display-column ranges. A unit contains one or more grapheme clusters when
  width composition is non-additive.
- `AmbiguousWidth` selects narrow or wide treatment for East Asian Ambiguous
  characters.
- `start_column` and `tab_width` are explicit labeled arguments. Tabs advance
  to the next tab stop; invalid negative start columns and non-positive tab
  widths raise a typed error.
- `display_width_unicode_version` exposes the version of the reused width
  tables rather than implying that it equals moji's Unicode 15.1 segmentation
  data version.

The input is one display run. Callers own hard-line splitting and control
character escaping.

## Existing API first

### Reused project APIs

- `grapheme_clusters` supplies legal UTF-16 grapheme boundaries.
- `String::view` creates zero-copy views for width measurement.
- `moonbit-community/unicodewidth::str_width` supplies UAX #11, emoji,
  combining-mark, ligature, and Ambiguous-width behavior.

### Checked but not selected

- `moonbit-community/displaytext` already combines graphemes and display width,
  but it owns a second grapheme implementation and version, does not expand
  tabs from an arbitrary starting column, and exposes a different opaque
  position model. Depending on it would make `moji` publish two potentially
  different grapheme boundaries.
- `String::char_length`, `String::iter`, and `decode_codepoint_at` do not supply
  terminal-cell width. Reimplementing East Asian Width tables locally would
  duplicate the existing `unicodewidth` package.
- `Map` and `Set` are unnecessary. Units are produced in source order by one
  pass and returned as an owning array.

### New responsibility boundary

The new composition layer first combines adjacent graphemes when measuring the
combined view is non-additive, then reconciles each complete tab-delimited
segment with the width library's state machine. If longer context changes the
total, the segment becomes one unit. Tabs are hard unit boundaries whose width
depends on the current absolute display column. The function has no terminal,
filesystem, locale, environment-variable, or renderer access.

## Behavioral boundary matrix

| Case | Required observation |
| --- | --- |
| Empty run | Width zero and no units |
| ASCII | One UTF-16 unit and one cell per scalar |
| CJK wide character | One UTF-16 unit and two cells |
| Combining sequence | One grapheme unit and one cell |
| ZWJ emoji / flag | One grapheme unit and two cells |
| Zero-width grapheme | Stable UTF-16 unit with equal cell start/end |
| Ambiguous character | One cell in `Narrow`, two in `Wide` |
| Tab at column zero | Advances to `tab_width` |
| Tab after content / nonzero start | Advances to the next absolute tab stop |
| Multiple tabs | Each width is derived from the preceding absolute column |
| Non-additive graphemes | Merge the smallest detected run; collapse the tab-delimited segment if longer context changes the total |
| Negative start column | Typed `InvalidStartColumn` failure |
| Zero/negative tab width | Typed `InvalidTabWidth` failure |
| Returned units | Source order, half-open UTF-16 and cell ranges |

## Non-goals

- Unicode segmentation data upgrade
- ANSI, color, themes, TTY or `NO_COLOR` detection
- hard-line splitting, bidi, shaping, pixels, or soft wrapping
- source sanitization or control-character rendering policy

## Follow-up integration

`dowdiness/diagnostic_moji` consumes this API through the core-only
`dowdiness/diagnostic` display capability. The adapter provides Unicode marker
alignment and deterministic four-column tab expansion while retaining UTF-16
coordinates in diagnostic headers and structured values. The base diagnostic
module keeps its MoonBit-core-only production boundary and code-unit-compatible
default renderer.
