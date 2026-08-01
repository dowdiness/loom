# Diagnostic

`dowdiness/diagnostic` is a parser-independent structured diagnostics library
for MoonBit tools. It keeps UTF-16 source coordinates, labels, notes, fixes,
and rendering as data, so terminal, editor, and future machine-readable views
can share one canonical `Diagnostic` value.

The production package depends on `dowdiness/moji` for Unicode display-cell
measurement. It does not depend on Loom, a syntax tree, a lexer, a terminal,
or a filesystem.

## Install

Add the module dependency:

```mbt nocheck
import {
  "dowdiness/diagnostic@0.1.0",
}
```

Import the package where it is used:

```mbt nocheck
import {
  "dowdiness/diagnostic" @diagnostic,
}
```

## Construct, Render, and Apply a Fix

Canonical positions are half-open UTF-16 code-unit ranges. A resolver returns
one coherent `SourceSnapshot` containing its display name, text, and matching
`LineIndex`. The source may be a file, virtual document, or in-memory buffer.
Plain rendering converts those offsets to display cells for marker alignment.
East Asian Ambiguous characters use narrow width, and tabs are deterministically
expanded to four-column stops in the rendered source line. A non-empty
zero-width span still receives a one-cell marker so the label remains visible.

```mbt check
///|
struct ReadmeResolver {
  id : @diagnostic.SourceId
  snapshot : @diagnostic.SourceSnapshot
}

///|
impl @diagnostic.SourceResolver for ReadmeResolver with fn resolve_source(
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
test "render and apply a structured diagnostic" {
  let id = @diagnostic.SourceId("memory://main")
  let source = "let ____ = 1"
  let range = try @diagnostic.TextRange::from_offsets(4, 8) catch {
    _ => abort("expected a valid range")
  } noraise {
    range => range
  }
  let fix = try
    @diagnostic.DiagnosticFix(
      "insert a name",
      @diagnostic.FixApplicability::Always,
      [@diagnostic.TextReplacement(@diagnostic.SourceSpan(id, range), "main")],
    )
  catch {
    _ => abort("expected a valid fix")
  } noraise {
    fix => fix
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("typechecker"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    code=Some(@diagnostic.DiagnosticCode("E-NAME")),
    message="missing entry-point name",
    labels=[
      @diagnostic.DiagnosticLabel(
        @diagnostic.LabelStyle::Primary,
        @diagnostic.SourceSpan(id, range),
        Some("name required here"),
      ),
    ],
    fixes=[fix],
  )
  let resolver = ReadmeResolver::{
    id,
    snapshot: @diagnostic.SourceSnapshot(
      "main.mbt",
      source,
      @diagnostic.LineIndex::new(source),
    ),
  }
  inspect(
    diagnostic.render_plain(resolver),
    content=(
      #|error[E-NAME]: missing entry-point name
      #|--> main.mbt
      #|primary 1:5-1:9: name required here
      #|  1 | let ____ = 1
      #|    |     ^^^^
    ),
  )
  let fixed = try diagnostic.fixes()[0].apply(id, source) catch {
    _ => abort("expected the fix to apply")
  } noraise {
    fixed => fixed
  }
  inspect(fixed, content="let main = 1")
}
```

## Convert an Application Error

`ToDiagnostic` is an open fixed-projection trait. Applications keep their own
error types and convert them at the presentation or reporting boundary.

```mbt check
///|
enum ReadmeBuildError {
  MissingEntryPoint
}

///|
impl @diagnostic.ToDiagnostic for ReadmeBuildError with fn to_diagnostic(self) {
  match self {
    MissingEntryPoint =>
      @diagnostic.Diagnostic(
        origin=@diagnostic.DiagnosticOrigin("builder"),
        severity=@diagnostic.DiagnosticSeverity::Error,
        message="missing entry point",
      )
  }
}

///|
test "convert an external error" {
  let diagnostic = @diagnostic.ToDiagnostic::to_diagnostic(
    ReadmeBuildError::MissingEntryPoint,
  )
  inspect(diagnostic.origin().name(), content="builder")
  inspect(diagnostic.message(), content="missing entry point")
}
```

## Boundaries

- `DiagnosticOrigin` identifies the producer; `SourceId` identifies source text.
- `SourceResolver` owns lookup and lifecycle; rendering only consumes snapshots.
- `DiagnosticFix` is atomic and single-source. It rejects empty, overlapping,
  duplicate-position, wrong-source, out-of-bounds, and invalid UTF-16 edits.
- Public arrays are defensive copies.
- `LineCol` is derived presentation data; offsets remain canonical.
- Parser replay, invalidation, recovery, and collection lifecycle are deliberately
  outside this package.
