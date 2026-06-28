# loomgen

Code generator for loom language plumbing files.

Phase 1: reads `#loom.*`-annotated `Token` enum, emits `syntax_kind.g.mbt` and `token_impls.g.mbt`.

Phase 2 (deferred): `#loom.term` enum support — emits `SyntaxKind` entries for CST node types.

Phase 3: `#loom.view` annotation on term variants — emits `views.g.mbt` with typed `*Proj`
accessor structs wrapping projection_shape helpers.

Phase 4 (`--lexer`, #521): `#loom.pattern("regex")` / `#loom.custom_lex("fn")` on token
variants — emits `lexer.g.mbt`, a longest-match step lexer. Each candidate matches with an
anchored compile-time regex literal `cursor.view() =~ (re"^PATTERN" as m)`; the maximal
match wins and declaration order breaks ties. `#loom.keyword(...)` variants are
post-classified from the `#loom.ident` match (no separate branch), and `#loom.custom_lex`
names a hand-written `(String, Int) -> LexStep[Token]` escape hatch that runs before the
regex pass. Patterns are emitted **verbatim** into the `re"..."` literal (which does not
process string escapes), so write engine-valid MoonBit `re`-dialect regex — e.g. a literal
hyphen in a class is `\-`, not a bare `-`. A pattern that can match the empty string is
rejected at generation time.

**Supported `#loom.pattern` subset:** literals, escapes, character classes `[..]`, plain
groups `(..)`, anchors `^`/`$`, and quantifiers `* + ? {m,n}`. Non-capturing/flag/lookaround
groups `(?...)` and zero-width assertion escapes (`\b`, `\B`, `\A`, `\z`, `\Z`) are rejected
at generation time — the nullability analyzer cannot soundly classify `(?:..)`, and the `re`
dialect rejects the others at compile time anyway. Use a plain group `(..)` instead of `(?:..)`.

**`#loom.custom_lex` rules:** it is a *modifier* that must pair with a role annotation (the
role gives the variant a kind for `token_impls`/`syntax_kind`; `custom_lex` overrides only
*how* the token is lexed) — a roleless `custom_lex` variant is rejected. It may not sit on
the `#loom.eof` variant (EOF is detected at scanner entry, never lexed), and its argument
must be a valid function reference (`ident` or `@pkg.ident`), since it is emitted verbatim
as a call.

## Fixtures

- `fixtures/term_kind.mbt` — combined token+term enum for CI regression (no view variants)
- `fixtures/view_fixture.mbt` — token+term enum with `#loom.view` annotations
- `fixtures/views_fixture.g.mbt` — expected output for view fixture regression
- `fixtures/spec_fixture.g.mbt` — expected output for spec generation regression
- `fixtures/pattern_lexer_fixture.mbt` — token enum with `#loom.pattern` lexer annotations
- `fixtures/pattern_lexer_fixture.g.mbt` — expected `--lexer` output (golden)

Generate and verify:
```bash
moon run loomgen --target native -- loomgen/fixtures/view_fixture.mbt token_out syntax_out
```
Diff `syntax_out/views.g.mbt` against `loomgen/fixtures/views_fixture.g.mbt` to verify.

Generate a lexer (independent of syntax-kind output):
```bash
moon run loomgen --target native -- loomgen/fixtures/pattern_lexer_fixture.mbt token_out \
  syntax_out --skip-syntax --lexer token_out/lexer.g.mbt
```
Diff `token_out/lexer.g.mbt` against `loomgen/fixtures/pattern_lexer_fixture.g.mbt` to verify.
