# loomgen

Code generator for loom MoonBit plumbing files. Generates `syntax_kind.g.mbt`,
`token_impls.g.mbt`, `lexer.g.mbt`, `views.g.mbt`, `lexmode.g.mbt`,
`spec.g.mbt`, and `grammar_ir.g.mbt` from `#loom.*` annotated enums.
Parser execution is delegated to [`@grammar.interpret`](../loom/grammar/interpreter.mbt)
at runtime. See [ADR 2026-07-10](../docs/decisions/2026-07-10-remove-emit-grammar-code-generator.md)
for why the parser code generator (`emit_grammar.mbt`) was removed.

## LexMode (`#loom.lexmode`)

`#loom.lexmode("ModeName")` annotation on term variants — emits `lexmode.g.mbt`
with a `LexMode` enum and `lexmode_for_kind(kind: SyntaxKind) -> LexMode?` dispatch function.

## Lexer generation (`--lexer`, #521)

`#loom.pattern("regex")` / `#loom.custom_lex("fn")` on token variants — emits
`lexer.g.mbt`, a longest-match step lexer. Each candidate matches with an anchored
compile-time regex literal `view =~ (re"^(?:PATTERN)", after=rest)`; the maximal match
wins and declaration order breaks ties. `#loom.keyword(...)` variants are post-classified
from the `#loom.ident` match (no separate branch), and `#loom.custom_lex` names a
hand-written `(String, Int) -> LexStep[Token]` escape hatch that runs before the regex
pass. Patterns are emitted **verbatim** into the `re"..."` literal (which does not process
string escapes), so write engine-valid MoonBit `re`-dialect regex — e.g. a literal
hyphen in a class is `\-`, not a bare `-`. A pattern that can match the empty string is
rejected at generation time.

`#loom.pattern` and `#loom.line_pattern` are mutually exclusive on the same
variant — a token cannot be produced by both the character-level and line-mode
lexer. A variant annotated with both is rejected at generation time.


## Line-mode lexer generation (`--line-lexer`, #561)

`#loom.line_pattern("regex")` on token variants — emits `line_lexer.g.mbt` with
per-mode lexer functions for each `#loom.line_mode` `#loom.lexmode`. Each function
matches `#loom.line_pattern` regexes against the current line (pos → newline) in
declaration order. Patterns with a declared `#loom.lexmode("ModeName")` are only
emitted in that mode's function; patterns without one appear in all line_mode
functions. Nullary tokens are produced directly; payload-carrying tokens require
`#loom.custom_lex` for extraction.
Generated helpers are named `generated_lex_<mode>` in `line_lexer.g.mbt`,
reserving `lex_<mode>` for skeleton-owned dispatcher override points.

`--line-lexer` automatically integrates these helpers with
`lexer_skeleton.g.mbt`: a new skeleton delegates each line-mode
`lex_<mode>` function to `generated_lex_<mode>`, and regeneration upgrades only
the exact historical `abort` stub. Replace a delegate with handwritten
`lex_<mode>` code to override that mode; later regeneration preserves that
non-generated body byte-for-byte. `--force-lexer` is the explicit operation for
replacing the entire skeleton.

The `--line-lexer` output file must be directly under `syntax_out`, because its
helpers and the skeleton must compile in the same MoonBit package. Loom rejects
an output path in a different directory before writing generated files.

`#loom.fallback_lex("fn")` on a term variant with both `#loom.lexmode("Mode")`
and `#loom.line_mode` delegates no-match input to the named mode-compatible
lexer (`(String, Int) -> (@core.LexStep[Token], LexMode)`). Without this
annotation, the generated function keeps its `Invalid` no-match step for
backward compatibility.

Reuses the same supported regex subset, nullability checks, and structural
validation as `#loom.pattern`. Alternation `|` is rejected (leftmost-match, not
longest-match). Patterns are wrapped in `^(?:...)` so they should not include
their own `^` anchor.

`#loom.line_pattern` and `#loom.pattern` are mutually exclusive on the same
variant — a token cannot be produced by both the line-mode and character-level
lexer. A variant annotated with both is rejected at generation time.

Usage:
```bash
moon run loomgen --target native -- --line-lexer <path>/line_lexer.g.mbt \
  --term <term.mbt> <token.mbt> <token_out> <syntax_out>
```
### Supported `#loom.pattern` subset

Literals, *literal-meta* escapes (`\.`, `\-`, `\+`, `\xHH`, …), character classes `[..]`
(including POSIX `[[:digit:]]`), plain groups `(..)`, anchors `^`/`$`, and *greedy*
quantifiers `* + ? {m,n}`. Rejected at generation time:

- **non-capturing/flag/lookaround groups** `(?...)` — the nullability analyzer cannot
  soundly classify `(?:..)`; use a plain `(..)`
- **zero-width assertion escapes** (`\b`, `\B`, `\A`, `\z`, `\Z`) and **Perl
  class-shorthand escapes** (`\d`, `\s`, `\w`, …) — the `re` dialect rejects both at
  compile time; use a POSIX class like `[[:digit:]]`
- **lazy quantifiers** (`*?`, `+?`, …) — a longest-match lexer needs greedy ones
- **alternation `|`** — regex alternation is leftmost-match, not longest-match, so
  `foo|foobar` would match `foo` and split the token; use separate token variants or a
  character class
- a pattern that can match the empty string

### `#loom.custom_lex` rules

A *modifier* that must pair with a role annotation (the role gives the variant a kind
for `token_impls`/`syntax_kind`; `custom_lex` overrides only *how* the token is lexed)
— a roleless `custom_lex` variant is rejected. It may not sit on the `#loom.eof` variant
(EOF is detected at scanner entry, never lexed) or a `#loom.keyword` variant (keywords
are post-classified from the `#loom.ident` match, never lexed directly), and its argument
must be a valid function reference (`ident` or `@pkg.ident`), since it is emitted verbatim
as a call.

## Grammar file input (`.loomgrammar`, #523)

When a grammar outgrows annotation strings, the same notation can live in a
standalone `.loomgrammar` file passed via `--grammar-file`. It feeds the *same*
`--grammar-ir` emitter — only the input parsing differs — so the generated
`grammar_ir.g.mbt` is identical to the annotation path for an equivalent grammar.

```text
// css.loomgrammar — '=' separates a production name from its body.
DeclarationList = Declaration* Eof

// Alternatives need disjoint FIRST sets — a trailing '?' expresses an
// optional suffix instead of two Property-led alternatives.
Declaration = Property Colon Value Semicolon?

// A leading '|' lines alternatives up vertically; '//' starts a line comment.
Value =
  | Ident
  | Number
  | Hash
```

The file uses the exact `#loom.rule` notation subset (`Seq`, `Choice` via `|`,
`Ref`, `*`/`+`/`?`, terminal refs, `@fragment` refs) and adds only `//` line
comments and multi-line bodies. A body runs from its `=` to the next `Name =`
header (or EOF). Each production name must be a `#loom.term` variant — the
variant's `#loom.node`/`#loom.root`/`#loom.leaf` role supplies its CST kind, and
the `#loom.root` variant still designates the grammar root. A production that also
carries a `#loom.rule` annotation is overridden by the file (with a warning), so a
language can migrate off annotations incrementally. Both parse errors AND
emission-stage rejections (a production naming a non-term variant,
a roleless variant, left recursion, an ambiguous alternation, a nullable
alternative) carry the
production's `line N:` prefix rather than an annotation offset, so every
`.loomgrammar` diagnostic points at a real file position. The parser fails closed:
duplicate names, empty bodies, stray `=`, unbalanced groups, and unknown
characters all abort the whole file. `@fragment` references produce a mangled
`Ref("__loom_frag__<name>")` and the generated function accepts a `fragments~`
parameter to bind the fragment bodies at the call site.

```bash
# .loomgrammar requires --grammar-ir to name the generated output.
moon run loomgen --target native -- token.mbt token_out syntax_out \
  --term term.mbt --grammar-ir syntax_out/grammar_ir.g.mbt \
  --grammar-file grammar/css.loomgrammar --language css
```

## `--grammar-ir` flag

`--grammar-ir <path>` generates a `<path>.g.mbt` file containing a
`pub let <lang>_grammar_ir : @grammar.GrammarIr[Token, SyntaxKind]` value
(or `pub fn` with a `fragments~` parameter when the grammar uses `@fragment`
references) built from `#loom.rule` annotations on `#loom.term` variants, plus
`#loom.token` (`#loom.punct`/`#loom.eof`) annotations on the Token enum for
FIRST-set token resolution.

The annotation subset covers 14 `@grammar.Expr` variants: `Expect`,
`Emit`, `EmitOr`, `ExpectSkip`, `Ref`, `Native`, `Node`,
`Choice`, `RepeatWhile`, `Seq`, `PrattApp`, `PrattBinary`, `ErrorUntil`,
`ErrorNodeUntil` (and auto-synthesized `Fail` for the required-`Choice` fallback).
Postfix `~` lowers to `Emit` (optional token consume), `!` lowers to
`EmitOr` (expect-or-continue with diagnostic), `~>` lowers to
`ExpectSkip` (consume soft separators before expecting a token),
`@until(Token)` / `@until(T1 | T2)` lowers to `ErrorUntil` (consume until
synchronization point), and `@error_node(Kind, Token)` /
`@error_node(Kind, T1 | T2)` lowers to `ErrorNodeUntil` (consume into error node
until synchronization point).

**Pratt productions (#601).** A production body that begins with `@prefix` is
parsed as an annotation-only Pratt body (not regular EBNF):

| Annotation | Meaning |
|---|---|
| `@prefix Rule` | Prefix rule for `PrattApp` or `PrattBinary` (case-sensitive `#loom.term` variant name) |
| `@prec[Op, ...]` | Operator table for `PrattBinary` (required for binary; empty/duplicate ops rejected) |
| `@skip(Tok)` | Gated soft-separator consume before each operator check (`PrattBinary` only) |
| `@app KindTerm` | Optional CST node kind override (not "application production" — overrides the Pratt node kind) |

`@prefix Atom` lowers to `PrattApp("Atom", <production kind>, FIRST(Atom))`.
`@prefix AppExpr @prec[Plus, Minus] @skip(Newline)` lowers to
`PrattBinary("AppExpr", <kind>, [(Plus,…),(Minus,…)], skip=Some((Newline,…)))`.
Pratt productions emit `PrattApp`/`PrattBinary` **directly** — no outer
`Node(kind, body)` wrapper. Multi-level precedence chains via separate
productions linked by `Ref` (e.g. `Expression = BinaryExpr`, `BinaryExpr =
@prefix AppExpr @prec[…]`, `AppExpr = @prefix Atom`).
The remaining variants (`RepeatTopLevel`, `WrapIfNext`,
`ConsumeGated`, `RequireSep`, `EmitError`,
`DiagnoseIf`, `ManualNewlineAppExpr`, `Empty`) are out-of-subset — a rule
string referencing any of these fails closed with a lowering error.

`@fragment` references serve as the escape hatch for out-of-subset logic. They
emit a mangled `Ref("__loom_frag__<name>")` and the generated function adds a
`fragments~` parameter. Additionally, each referenced fragment gets a generated
`pub let frag_<name> : Expr[T,K]` declaration that the consumer fills in with the
hand-authored `Expr` body. The grammar function pre-registers these fragment vars
into the rules map before the `fragments~` merge loop, so the `fragments~`
parameter is only needed for dynamic override or testing:

```moonbit
/// @fragment 'source_toplevel'
pub let frag_source_toplevel : @grammar.Expr[Token, SyntaxKind] = @grammar.Expr::Fail(
  "TODO: fill in @fragment 'source_toplevel' body",
)

pub fn lambda_grammar_ir(
  fragments~ : Map[String, @grammar.Expr[Token, SyntaxKind]] = Map([]),
) -> @grammar.GrammarIr[Token, SyntaxKind] {
  let rules = { ... }
  rules.set("__loom_frag__source_toplevel", frag_source_toplevel)
  for frag, body in fragments {
    rules.set(frag, body)
  }
  ...
}
```

Each `pub let` uses `@grammar.Expr::Fail("TODO: ...")` as a placeholder — the
consumer replaces this with the actual `@grammar.Expr` body. For backward
compatibility, the `fragments~` parameter still accepts the mangled
`"__loom_frag__<name>"` keys and overrides the pre-registered fragment vars.
Without any matching entry (neither a filled-in `pub let` nor a `fragments~`
entry), `@grammar.compile` raises `MissingFragment`.

**Markdown inline is `@native`-only by decision, not an unfinished feature.**
loomgen targets the CommonMark *block* subset; CommonMark *inline* parsing
(emphasis, links, inline code) stays permanently hand-authored `@native` host
code because it is not expressible as a data-only `GrammarIr` (emphasis is a
delimiter-stack algorithm, link reference definitions are document-global and
two-pass). See [ADR 2026-07-06](../docs/decisions/2026-07-06-markdown-inline-native-only.md)
and [#642](https://github.com/dowdiness/loom/issues/642).

**What is NOT emitted:** `--grammar-ir` emits only the `GrammarIr` value itself.
It does not generate the `Token`/`SyntaxKind` enums, trait impls (`Show`,
`IsTrivia`, `IsEof`, `ToRawKind`), `pkg.generated.mbti`, or `moon.pkg`.
Consumers must hand-author those (or use loomgen's Phase 1/2 emitters for the
same source annotations).

A compile-regression fixture at `fixtures/grammar_ir_regression/` demonstrates
the full consumption pattern with hand-written `token_def.mbt`,
`syntax_kind_def.mbt`, trait impls, and `moon.pkg` alongside the generated
`grammar_ir.g.mbt`. `regenerate.sh` at the fixture root shows the exact CLI
invocation from repo root.

Usage:

```bash
moon run loomgen --target native -- token.mbt token_out syntax_out \
  --term term.mbt --grammar-ir path/to/output.g.mbt --language mylang
```

For `.loomgrammar` file input instead of inline annotations, see the
[Grammar file input](#grammar-file-input-loomgrammar-523) section above
(both feed the same lowering pipeline).

## Fixtures

- `fixtures/parens.loomgrammar` — smallest `.loomgrammar` file; the differential
  parity test asserts it emits the same GrammarIr as the equivalent annotation
- `fixtures/pratt.loomgrammar` + `fixtures/pratt_grammar_fixture.mbt` — lambda-shaped
  Pratt grammar (`@prefix`/`@prec`/`@skip`); differential + golden tests (#601)
- `fixtures/file_only_grammar.mbt` + `fixtures/file_only.loomgrammar` — a
  roles-only `#loom.term` enum (no `#loom.rule`) plus the file that bodies it;
  drives the file-only emission path (multi-production, cross-rule `Ref`,
  root-from-file) and the file-path fail-closed cases. `fixtures/file_only.g.mbt`
  is the golden the file-only test asserts against (full output, not substring)
- `fixtures/grammar_ir_regression/` — compile-regression fixture guarding
  against the `--grammar-ir` generated output becoming uncompilable
- `fixtures/view_fixture.mbt` + `fixtures/views_fixture.g.mbt` — token+term enum
  with `#loom.view` annotations and expected golden. Regenerate:
  ```bash
  moon run loomgen --target native -- loomgen/fixtures/view_fixture.mbt \
    token_out syntax_out
  ```
  Diff `syntax_out/views.g.mbt` against `fixtures/views_fixture.g.mbt`.
- `fixtures/lexmode_fixture.mbt` + `fixtures/lexmode_fixture.g.mbt` — token+term
  enum with `#loom.lexmode` annotations and expected golden. Regenerate:
  ```bash
  moon run loomgen --target native -- loomgen/fixtures/lexmode_fixture.mbt \
    token_out syntax_out
  ```
  Diff `syntax_out/lexmode.g.mbt` against `fixtures/lexmode_fixture.g.mbt`.
- `fixtures/pattern_lexer_fixture.mbt` + `fixtures/pattern_lexer_fixture.g.mbt` —
  token enum with `#loom.pattern` lexer annotations and expected golden.
  Regenerate (independent of syntax-kind output):
  ```bash
  moon run loomgen --target native -- loomgen/fixtures/pattern_lexer_fixture.mbt \
    token_out syntax_out --skip-syntax --lexer token_out/lexer.g.mbt
  ```
  Diff `token_out/lexer.g.mbt` against `fixtures/pattern_lexer_fixture.g.mbt`.
Spec generation is drift-checked against its compiled consumers,
`examples/lambda/spec.g.mbt` and `examples/json/spec.g.mbt` (see the CI
steps "Verify spec generation matches compiled consumer" and "Verify json
spec generation matches compiled consumer"); `fixtures/multi_trivia_spec.g.mbt`
covers the multi-trivia emitter branch.
The following fixtures are not regenerated by loomgen — they are hand-maintained
metadata split across source files:

- `examples/lambda/token/token.mbt` (token source) + `examples/lambda/meta/term_kind.mbt`
  (loaded via `--term`; see issue #563)
- `examples/json/token.mbt` (token source) + `examples/json/meta/term_kind.mbt`
  (loaded via `--term`; a non-package directory, since json is a single package and
  compiling TermKind there would make its constructors ambiguous with SyntaxKind's —
  see issue #565)
