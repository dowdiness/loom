# loomgen

Code generator for loom language plumbing files.

Phase 1: reads `#loom.*`-annotated `Token` enum, emits `syntax_kind.g.mbt` and `token_impls.g.mbt`.

Phase 2 (deferred): `#loom.term` enum support — emits `SyntaxKind` entries for CST node types.

Phase 3: `#loom.view` annotation on term variants — emits `views.g.mbt` with typed `*Proj`
accessor structs wrapping projection_shape helpers.

Phase 4: `#loom.lexmode("ModeName")` annotation on term variants — emits `lexmode.g.mbt`
with a `LexMode` enum and `lexmode_for_kind(kind: SyntaxKind) -> LexMode?` dispatch function.

## Fixtures

- `fixtures/term_kind.mbt` — combined token+term enum for CI regression (no view variants)
- `fixtures/view_fixture.mbt` — token+term enum with `#loom.view` annotations
- `fixtures/views_fixture.g.mbt` — expected output for view fixture regression
- `fixtures/lexmode_fixture.mbt` — token+term enum with `#loom.lexmode` annotations
- `fixtures/lexmode_fixture.g.mbt` — expected output for lexmode fixture regression
- `fixtures/spec_fixture.g.mbt` — expected output for spec generation regression
Generate and verify:
```bash
moon run loomgen --target native -- loomgen/fixtures/view_fixture.mbt token_out syntax_out
```
Diff `syntax_out/views.g.mbt` against `loomgen/fixtures/views_fixture.g.mbt` to verify.

Lexmode fixture:
```bash
moon run loomgen --target native -- loomgen/fixtures/lexmode_fixture.mbt token_out syntax_out
```
Diff `syntax_out/lexmode.g.mbt` against `loomgen/fixtures/lexmode_fixture.g.mbt` to verify.
