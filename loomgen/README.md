# loomgen

Code generator for loom language plumbing files.

Phase 1: reads `#loom.*`-annotated `Token` enum, emits `syntax_kind.g.mbt` and `token_impls.g.mbt`.

Phase 2 (deferred): `#loom.term` enum support — emits `SyntaxKind` entries for CST node types.

Phase 3: `#loom.view` annotation on term variants — emits `views.g.mbt` with typed `*Proj`
accessor structs wrapping projection_shape helpers.

## Grammar IR Emitter

`emit_grammar.mbt` converts a `@grammar.GrammarIr[T, K]` value to a `parse_root`/`parse_<rule>`
MoonBit source file matching the semantics of `@grammar.interpret`.

The emitter is library-only: there is no `--grammar <file.mbt>` CLI flag because
loomgen cannot dynamically evaluate arbitrary MoonBit data from a file.
Callers construct a `GrammarIr` in memory and pass it to `emit_grammar(...)`.

Fixture parity packages (`fixtures/grammar_parity/`, `fixtures/grammar_parity_reuse/`)
verify emitted parsers produce the same CST and diagnostics as `@grammar.interpret`.

## Fixtures

- `fixtures/term_kind.mbt` — combined token+term enum for CI regression (no view variants)
- `fixtures/view_fixture.mbt` — token+term enum with `#loom.view` annotations
- `fixtures/views_fixture.g.mbt` — expected output for view fixture regression
- `fixtures/spec_fixture.g.mbt` — expected output for spec generation regression

Generate and verify:
```bash
moon run loomgen --target native -- loomgen/fixtures/view_fixture.mbt token_out syntax_out
```
Diff `syntax_out/views.g.mbt` against `loomgen/fixtures/views_fixture.g.mbt` to verify.
