# Diagnostic Moji

`dowdiness/diagnostic_moji` is the Unicode display adapter for
`dowdiness/diagnostic`. It keeps the structured diagnostic model core-only
while opting plain terminal output into `dowdiness/moji` grapheme and
display-cell measurement.

The adapter preserves UTF-16 coordinates in diagnostic values and headers. In
rendered source lines it uses narrow East Asian Ambiguous width, expands tabs
to deterministic four-column stops, expands ranges inside a combined display
unit to that unit, and keeps a one-cell marker for a non-empty zero-width span.

## Install

Add the module dependency:

```mbt nocheck
///|
import {
  "dowdiness/diagnostic_moji@0.1.0",
}
```

Import the package together with the core diagnostic package:

```mbt nocheck
///|
import {
  "dowdiness/diagnostic",
  "dowdiness/diagnostic_moji",
}
```

## Render

Use `render_plain` for one value or `render_diagnostics_plain` for an ordered
view. Both accept the same `SourceResolver` capability as the core renderer.

```mbt nocheck
///|
let output = @diagnostic_moji.render_plain(diagnostic, resolver)
```

Use `@diagnostic.Diagnostic::render_plain` instead when code-unit-compatible
plain output is required. ANSI styling, terminal detection, wrapping, bidi,
shaping, and control-character escaping remain presentation-layer concerns.
