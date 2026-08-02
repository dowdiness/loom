# Diagnostic Pretty

`dowdiness/diagnostic_pretty` is the optional width-aware presentation adapter
for `dowdiness/diagnostic`. It returns a reusable
`@pretty.Layout[DiagnosticStyle]` while `dowdiness/moji` supplies Unicode
display-cell measurement, tab expansion, and UTF-16 marker projection.

The adapter does not emit ANSI or HTML and does not inspect terminal
capabilities. Consumers decide how to interpret the resolved text and semantic
annotations.

## Install

Add the three module dependencies:

```mbt nocheck
import {
  "dowdiness/diagnostic@0.1.0",
  "dowdiness/diagnostic_pretty@0.1.0",
  "dowdiness/pretty@0.1.0",
}
```

Import their packages:

```mbt nocheck
import {
  "dowdiness/diagnostic" @diagnostic,
  "dowdiness/diagnostic_pretty" @diagnostic_pretty,
  "dowdiness/pretty" @pretty,
}
```

## Construct and Resolve a Layout

Options are explicit. The default uses four-column tab stops and narrow East
Asian Ambiguous width; callers may choose another positive tab width or wide
ambiguous characters.

```mbt check
///|
struct ReadmePrettyResolver {
  id : @diagnostic.SourceId
  snapshot : @diagnostic.SourceSnapshot
}

///|
impl @diagnostic.SourceResolver for ReadmePrettyResolver with fn resolve_source(
  self,
  id,
) {
  if id == self.id {
    Some(self.snapshot)
  } else {
    None
  }
}

///|
test "construct resolve and inspect a diagnostic layout" {
  let id = @diagnostic.SourceId("memory://main")
  let source = "let x = 界"
  let range = try @diagnostic.TextRange::from_offsets(8, 9) catch {
    _ => abort("expected a valid README range")
  } noraise {
    range => range
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("typechecker"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    code=Some(@diagnostic.DiagnosticCode("E-TYPE")),
    message="unexpected value",
    labels=[
      @diagnostic.DiagnosticLabel(
        @diagnostic.LabelStyle::Primary,
        @diagnostic.SourceSpan(id, range),
        Some("expected Int"),
      ),
    ],
    notes=["convert the value explicitly"],
  )
  let resolver = ReadmePrettyResolver::{
    id,
    snapshot: @diagnostic.SourceSnapshot(
      "main.mbt",
      source,
      @diagnostic.LineIndex::new(source),
    ),
  }
  let options = try @diagnostic_pretty.DiagnosticPrettyOptions() catch {
    _ => abort("default diagnostic pretty options must be valid")
  } noraise {
    options => options
  }
  let report = @diagnostic_pretty.layout(diagnostic, resolver, options)
  inspect(
    @pretty.render_string(report, width=80),
    content=(
      #|error[E-TYPE]: unexpected value
      #|--> main.mbt
      #|primary 1:9-1:10: expected Int
      #|  1 | let x = 界
      #|    |         ^^
      #|= note: convert the value explicitly
    ),
  )
  inspect(
    @pretty.render_string(report, width=16),
    content=(
      #|error[E-TYPE]:
      #|  unexpected value
      #|--> main.mbt
      #|primary 1:9-1:10:
      #|  expected Int
      #|  1 | let x = 界
      #|    |         ^^
      #|= note:
      #|  convert the value explicitly
    ),
  )
  inspect(@pretty.resolve(80, report).length() > 0, content="true")
  let spans = @pretty.render_spans(report, width=80)
  inspect(
    spans.any(item => {
      item.1 ==
      @diagnostic_pretty.DiagnosticStyle::Severity(
        @diagnostic.DiagnosticSeverity::Error,
      )
    }),
    content="true",
  )
  inspect(
    spans.any(item => item.1 == @diagnostic_pretty.DiagnosticStyle::Primary),
    content="true",
  )
}
```

`render_string` is a plain interpretation that ignores annotations.
`resolve` exposes the annotated command stream, while `render_spans` returns
UTF-16 output spans paired with `DiagnosticStyle`. A later terminal or web
adapter can map those roles to its own theme without changing this package.

