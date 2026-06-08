# ADR: JSON role-span editor export shape

**Date:** 2026-06-08
**Status:** Accepted
**Issue:** [#259](https://github.com/dowdiness/loom/issues/259)
**Implementation plan:** N/A — issue-scoped JSON example additive API, no plan document.

## Context

The JSON example now has two parser-backed role-span layers:

- a pure CST projection, `project_json_roles`, that classifies JSON tokens into
  JSON-local `JsonRoleSpan` values; and
- `JsonRoleSpansAttachment`, which attaches that projection to a
  `SyntaxParser` runtime so editors can read current spans after parser edits.

Canopy's CodeMirror integration needs source ranges plus stable role names, but
Loom should not depend on CodeMirror or commit to a broader editor-artifact
model before other languages validate the shape. Parser diagnostics also need to
remain separate from highlighting spans so malformed input can be highlighted
without hiding current parser errors.

## Decision

Add a minimal JSON-local editor export surface:

- `JsonRole::export_name()` maps each JSON role to a documented lower-kebab
  string vocabulary.
- `JsonRoleSpanExport` is the editor-neutral span shape with private fields and
  public `start`, `end`, and `role` accessors.
- `JsonRoleSpanExport` implements `ToJson`, producing objects with
  `{ "start", "end", "role" }` fields for JSON/JS-facing consumers.
- `export_json_role_spans(spans)` converts existing typed `JsonRoleSpan` arrays
  to the export shape.
- `JsonRoleSpansAttachment::export_spans()` converts the attachment's current
  parser-backed spans without adding parser-core APIs.

Keep the export in `dowdiness/json`. Do not add a CodeMirror dependency, shared
`LanguageModel` interface, TextMate/Monarch generation, or parser-core role-span
abstraction as part of this decision.

## Rationale

The existing `JsonRole` and `JsonRoleSpan` remain the source of truth for JSON
classification. A tiny export wrapper gives editor code the stable data shape it
needs while preserving the typed local role enum for tests and future JSON
projection work.

Lower-kebab role names are simple to consume from JavaScript and avoid exposing
MoonBit enum constructor spelling as the external contract. Keeping the struct
fields private preserves room for validation or representation changes while the
accessors and `ToJson` output define the public shape.

Staying JSON-local avoids prematurely extracting a cross-language editor model.
Markdown and future languages can validate whether the same role-span pattern is
enough before Loom grows a shared API.

## Consequences

CodeMirror-facing consumers can read parser-backed JSON highlights as stable
`{ start, end, role }` objects and map the role strings to editor-specific tags
outside Loom.

Parser diagnostics remain available from `parser.diagnostics()` and are not
bundled into the role-span export. Error spans are syntax-role information only,
not a replacement for diagnostics.

The `dowdiness/json` public API grows by a small additive export surface. Any
future shared editor artifact API should treat this JSON shape as evidence, not
as a commitment that Loom core will own all language role exports.
