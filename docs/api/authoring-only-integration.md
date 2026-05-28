# Authoring-only Loom Integration

Use this guide when a downstream project wants Loom for editor diagnostics,
CST projection, or authoring tools, but does **not** want Loom to become part
of its runtime or browser-reachable dependency graph.

This boundary is optional. Applications that are happy to use Loom at runtime
can call `@loom.new_parser` directly from their production packages.

## Intended boundary

Keep parsing responsibilities split by consumer:

```text
runtime module / package
  owns the shipped one-shot parser or evaluator
  has no dependency on dowdiness/loom or dowdiness/seam
  is reachable from browser, audio worklet, CLI runtime, or published API

optional authoring module / package
  depends on dowdiness/loom and dowdiness/seam
  builds parser diagnostics, CST projections, outlines, rename facts, etc.
  exposes a language-owned authoring facade to editor tooling
```

The authoring facade is the important seam. Editor callers should depend on
language-owned result types, not on Loom internals, unless the editor package is
explicitly part of the authoring-only surface.

```mbt nocheck
// authoring facade package
pub struct AuthoringSnapshot {
  diagnostics : Array[AuthoringDiagnostic]
  outline : Array[OutlineItem]
}

pub fn analyze_for_editor(source : String) -> AuthoringSnapshot {
  let parser = @loom.new_parser(source, my_language_grammar)
  let diagnostics = lower_diagnostics(parser.diagnostics().read_or_abort())
  let syntax = parser.syntax_tree().read_or_abort()
  let outline = project_outline(syntax)
  { diagnostics, outline }
}
```

Runtime callers can keep using an independent parser or loader:

```mbt nocheck
// runtime package; no @loom or @seam imports
pub fn parse_for_runtime(source : String) -> RuntimeProgram raise RuntimeParseError {
  parse_runtime_program(source)
}
```

This lets existing runtime callers stay stable while the authoring side adopts
Loom incrementally.

## Dependency-shape examples

### Exploratory spike

A spike can live in a nested module with local path dependencies while the team
proves grammar shape and projection value:

```text
my-language/
  moon.mod or moon.mod.json          # production module; no Loom/Seam deps
  src/runtime/                       # shipped parser/evaluator
  experiments/loom-authoring-spike/
    moon.mod or moon.mod.json        # local-only module
    src/                             # @loom parser/projection prototype
```

The spike manifest may use path dependencies such as `../loom` while iterating.
That is not a release plan: path dependencies are machine- and repository-layout
specific, and they should not enter published runtime modules by accident.

### Production authoring package

For a production authoring package, make the dependency boundary explicit and
publishable:

```text
my-language-runtime/
  moon.mod or moon.mod.json          # published runtime package; no Loom/Seam
  src/

my-language-authoring/
  moon.mod or moon.mod.json          # editor/authoring package
  src/authoring_facade.mbt           # language-owned API over Loom results
```

The authoring package may depend on the runtime package plus Loom/Seam, but the
runtime package should not depend back on the authoring package. In production,
prefer versioned registry dependencies for Loom/Seam. If Loom or Seam is only
available through local path dependencies in your setup, keep that module out of
the release path until the dependency story is publishable for your project.

## Audit checklist

Before shipping an authoring-only integration, check the boundary from the
runtime side outward:

1. **Manifest isolation** — runtime `moon.mod` / `moon.mod.json` files do not
   list `dowdiness/loom` or `dowdiness/seam` unless the runtime intentionally
   adopts Loom.
2. **Package import isolation** — runtime or browser-reachable `moon.pkg` files
   do not import the authoring package, spike module, `@loom`, or `@seam`.
3. **Facade ownership** — editor-facing APIs return language-owned types such
   as `AuthoringSnapshot`, `AuthoringDiagnostic`, or private projection results;
   Loom `Parser`, `SyntaxNode`, and raw diagnostics remain behind the facade
   unless the authoring API intentionally exposes them.
4. **Publishability** — if any published package depends on Loom or Seam, run
   the same packaging/publish checks used for release and confirm local path
   dependencies are not required.
5. **Browser or wasm-gc reachability** — if Loom enters a package reachable from
   browser, audio worklet, or other wasm-gc targets, run that downstream build
   before treating the integration as production-ready.
6. **Runtime parity** — existing one-shot runtime parsing tests still exercise
   the runtime parser, not the authoring facade, unless the project explicitly
   chose to move runtime parsing to Loom.

Useful local searches while reviewing a downstream diff:

```bash
rg 'dowdiness/(loom|seam)|@loom|@seam' --glob 'moon.mod' --glob 'moon.mod.json' --glob 'moon.pkg' --glob '*.mbt'
rg 'authoring|loom-authoring-spike' --glob 'moon.pkg' --glob '*.mbt'
```

Adjust the searched directories to match the downstream repository. A match is
not automatically wrong, but every match in a runtime-reachable path should be
intentional and reviewed as a production dependency change.

## What this guide does not require

- It does not require every Loom user to maintain two parsers.
- It does not prescribe a specific downstream package layout.
- It does not forbid using Loom in runtime packages when the project accepts the
  dependency and verifies publish/browser builds.
- It does not make path-dependency spikes publishable; it only gives them a safe
  place to live while the production boundary remains clean.
