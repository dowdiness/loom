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

Phase 4: `#loom.lexmode("ModeName")` annotation on term variants — emits `lexmode.g.mbt`
with a `LexMode` enum and `lexmode_for_kind(kind: SyntaxKind) -> LexMode?` dispatch function.

Phase 5 (`--lexer`, #521): `#loom.pattern("regex")` / `#loom.custom_lex("fn")` on token
variants — emits `lexer.g.mbt`, a longest-match step lexer. Each candidate matches with an
anchored compile-time regex literal `view =~ (re"^(?:PATTERN)", after=rest)`; the maximal
match wins and declaration order breaks ties. `#loom.keyword(...)` variants are
post-classified from the `#loom.ident` match (no separate branch), and `#loom.custom_lex`
names a hand-written `(String, Int) -> LexStep[Token]` escape hatch that runs before the
regex pass. Patterns are emitted **verbatim** into the `re"..."` literal (which does not
process string escapes), so write engine-valid MoonBit `re`-dialect regex — e.g. a literal
hyphen in a class is `\-`, not a bare `-`. A pattern that can match the empty string is
rejected at generation time.

**Supported `#loom.pattern` subset:** literals, *literal-meta* escapes (`\.`, `\-`, `\+`,
`\xHH`, …), character classes `[..]` (including POSIX `[[:digit:]]`), plain groups `(..)`,
anchors `^`/`$`, and *greedy* quantifiers `* + ? {m,n}`. Rejected at generation time:
non-capturing/flag/lookaround groups `(?...)` (the nullability analyzer cannot soundly
classify `(?:..)`; use a plain `(..)`); zero-width assertion escapes (`\b`, `\B`, `\A`, `\z`,
`\Z`) and Perl class-shorthand escapes (`\d`, `\s`, `\w`, …) (the `re` dialect rejects both
at compile time — use a POSIX class like `[[:digit:]]`); lazy quantifiers (`*?`, `+?`, …, a
longest-match lexer needs greedy ones); and **alternation `|`** (regex alternation is
leftmost-match, not longest-match, so `foo|foobar` would match `foo` and split the token —
use separate token variants or a character class). A pattern that can match the empty string
is also rejected.

**`#loom.custom_lex` rules:** it is a *modifier* that must pair with a role annotation (the
role gives the variant a kind for `token_impls`/`syntax_kind`; `custom_lex` overrides only
*how* the token is lexed) — a roleless `custom_lex` variant is rejected. It may not sit on
the `#loom.eof` variant (EOF is detected at scanner entry, never lexed) or a `#loom.keyword`
variant (keywords are post-classified from the `#loom.ident` match, never lexed directly),
and its argument must be a valid function reference (`ident` or `@pkg.ident`), since it is
emitted verbatim as a call.

## Fixtures

- `fixtures/term_kind.mbt` — combined token+term enum for CI regression (no view variants)
- `fixtures/view_fixture.mbt` — token+term enum with `#loom.view` annotations
- `fixtures/views_fixture.g.mbt` — expected output for view fixture regression
- `fixtures/lexmode_fixture.mbt` — token+term enum with `#loom.lexmode` annotations
- `fixtures/lexmode_fixture.g.mbt` — expected output for lexmode fixture regression
- `fixtures/spec_fixture.g.mbt` — expected output for spec generation regression
- `fixtures/pattern_lexer_fixture.mbt` — token enum with `#loom.pattern` lexer annotations
- `fixtures/pattern_lexer_fixture.g.mbt` — expected `--lexer` output (golden)

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

Generate a lexer (independent of syntax-kind output):
```bash
moon run loomgen --target native -- loomgen/fixtures/pattern_lexer_fixture.mbt token_out \
  syntax_out --skip-syntax --lexer token_out/lexer.g.mbt
```
Diff `token_out/lexer.g.mbt` against `loomgen/fixtures/pattern_lexer_fixture.g.mbt` to verify.
