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

## Grammar file input (`.loomgrammar`, #523)

When a grammar outgrows annotation strings, the same notation can live in a
standalone `.loomgrammar` file passed via `--grammar-file`. It feeds the *same*
`--grammar-ir` emitter — only the input parsing differs — so the generated
`grammar_ir.g.mbt` is identical to the annotation path for an equivalent grammar.

```text
// css.loomgrammar — '=' separates a production name from its body.
DeclarationList = Declaration* Eof

// A leading '|' lines alternatives up vertically; '//' starts a line comment.
Declaration =
  | Property Colon Value Semicolon
  | Property Colon Value

Value = (Ident | Number | Hash)+
```

The file uses the exact `#loom.rule` notation subset (`Seq`, `Choice` via `|`,
`Ref`, `*`/`+`/`?`, terminal refs, `@fragment` refs) and adds only `//` line
comments and multi-line bodies. A body runs from its `=` to the next `Name =`
header (or EOF). Each production name must be a `#loom.term` variant — the
variant's `#loom.node`/`#loom.root`/`#loom.leaf` role supplies its CST kind, and
the `#loom.root` variant still designates the grammar root. A production that also
carries a `#loom.rule` annotation is overridden by the file (with a warning), so a
language can migrate off annotations incrementally. Both parse errors AND
emission-stage rejections (a production naming a non-term variant, an `@fragment`
body, a roleless variant, left recursion, an ambiguous alternation) carry the
production's `line N:` prefix rather than an annotation offset, so every
`.loomgrammar` diagnostic points at a real file position. The parser fails closed:
duplicate names, empty bodies, stray `=`, unbalanced groups, and unknown
characters all abort the whole file. `@fragment` references parse but are rejected
at emission by the shared closed-GrammarIr guard until fragment binding lands (the
same deferred gap as the annotation path).

```bash
# .loomgrammar requires --grammar-ir to name the generated output.
moon run loomgen --target native -- token.mbt token_out syntax_out \
  --term term.mbt --grammar-ir syntax_out/grammar_ir.g.mbt \
  --grammar-file grammar/css.loomgrammar --language css
```

## Fixtures

- `fixtures/parens.loomgrammar` — smallest `.loomgrammar` file; the differential
  parity test asserts it emits the same GrammarIr as the equivalent annotation
- `fixtures/file_only_grammar.mbt` + `fixtures/file_only.loomgrammar` — a
  roles-only `#loom.term` enum (no `#loom.rule`) plus the file that bodies it;
  drives the file-only emission path (multi-production, cross-rule `Ref`,
  root-from-file) and the file-path fail-closed cases. `fixtures/file_only.g.mbt`
  is the golden the file-only test asserts against (full output, not substring)
- `fixtures/term_kind.mbt` — combined token+term enum for CI regression (no view variants)
- `fixtures/view_fixture.mbt` — token+term enum with `#loom.view` annotations
- `fixtures/views_fixture.g.mbt` — expected output for view fixture regression
- `fixtures/lexmode_fixture.mbt` — token+term enum with `#loom.lexmode` annotations
- `fixtures/lexmode_fixture.g.mbt` — expected output for lexmode fixture regression
- Spec generation is drift-checked against its compiled consumer,
  `examples/lambda/spec.g.mbt` (see the CI step "Verify spec generation
  matches compiled consumer"); `fixtures/multi_trivia_spec.g.mbt` covers the
  multi-trivia emitter branch
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
