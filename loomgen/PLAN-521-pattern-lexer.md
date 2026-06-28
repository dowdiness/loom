# PLAN-521: `#loom.pattern` Lexer Generation

## Overview

Issue #521 adds lexer generation to `loomgen` for token enums that opt variants into scanning with `#loom.pattern("regex")`, `#loom.punct("literal")`, `#loom.keyword("kw")`, and `#loom.custom_lex("fn_name")`.

The generator emits a `lexer.g.mbt` step lexer that uses MoonBit compile-time regex literals against `@core.LexCursor::view()`: every emitted regex is anchored as `re"^PATTERN"`, matched length comes from `m.length()`, and cursor progress is made with `advance_code_units(len)` followed by `produced(token)`. `loomgen` treats pattern strings as opaque MoonBit `re` dialect regex text and does not translate or execute them at generation time.

The generated scanner uses longest-match semantics. All pattern candidates and punct candidates are considered at the current cursor position; the maximal length wins, and token declaration order is the equal-length tiebreaker. Punctuation should be emitted as exact `cursor.starts_with("...")` candidates rather than escaped regex literals, because this avoids regex escaping ambiguity, preserves exact literal semantics, and is cheaper for fixed strings. Keywords do not get candidate branches; after an Ident-role variant wins, the matched text is post-classified through a generated keyword table.

EOF returns `Done` when `cursor.is_done()` at entry. The `#loom.eof` variant is not a candidate. The `#loom.error` variant is used only as no-match fallback, producing `LexStep::Invalid` that advances one Unicode scalar. Error tokens therefore cannot shadow real tokens. Trivia participates in longest-match like other real candidates, so it only wins when it is the longest match or tied by declaration order.

`#loom.custom_lex("fn_name")` provides an escape hatch for hand-written lexing. The generated step calls custom functions before the regex/punct pass. A custom function has expected signature `(String, Int) -> @core.LexStep[Token]`. If it returns `Produced`, `Invalid`, or `Incomplete`, that result is used; if it returns `Done`, generation falls through to the longest-match pass. Multiple custom lexers run in token declaration order.

## Step 1: Parse Fields And Annotation Validation

### Goal

Extend parsed token metadata with lexer-generation modifiers while preserving existing role classification behavior.

### Files Touched

- `loomgen/parse_annotations.mbt`

### What Each Function Does

- `VariantDecl`: add `pattern : String?` and `custom_lex : String?`.
- `extract_variants`: collect `#loom.pattern("...")` and `#loom.custom_lex("...")` as modifiers, alongside existing `kind_override`, `is_void`, and `is_rawtext`.
- `classify_role`: treat `pattern` and `custom_lex` like `void` and `rawtext`: validate argument shape but do not assign a `SyntaxRole`.
- New small helpers:
  - `find_string_modifier(attr, name)`: extracts a required single string argument for modifier annotations.
  - `validate_token_lexer_annotations(enum_decl)`: validates cross-field token lexer constraints after role classification.
  - `is_nullable_pattern(pattern)`: conservative static guard for zero-width regexes.

### Invariants

- `#loom.pattern` and `#loom.custom_lex` are modifiers, not `SyntaxRole` variants.
- Both annotations require exactly one string argument and produce the same style of error messages as `#loom.punct` and `#loom.literal`.
- Both annotations are only allowed on `#loom.token` enums.
- `#loom.pattern` is rejected on Keyword, Eof, and ErrorToken roles; keywords are post-classified from Ident, EOF is handled at entry, and error is fallback only.
- `#loom.pattern` is rejected together with `#loom.keyword`.
- `#loom.custom_lex` is only allowed on token enums. It may appear on a token variant regardless of role except Eof; it is an escape hatch and its function may return any non-Done lex step.
- If any keyword exists, an Ident-role variant must exist; otherwise `--lexer` generation fails because keywords have no post-classification source.
- Nullable pattern rejection is generation-time defense-in-depth. Runtime still guarantees progress through `LexCursor::produced` and `PrefixLexer::lex_all`.
- The nullable guard is conservative and intentionally not a full regex parser:
  - Reject `""`.
  - Reject patterns whose top-level sequence has no required atom.
  - Treat literal characters, escaped characters, char classes, and groups without a trailing `?` or `*` as required atoms.
  - Treat atoms followed by `?` or `*` as optional.
  - Treat `+` and unquantified atoms as required.
  - For top-level alternation, reject if any branch is nullable.
  - Parenthesized groups are scanned recursively enough to decide whether the group has a required atom.
  - Known false rejections: complex nested alternations or escaped metasyntax that the shallow scanner cannot confidently classify may be rejected. This is acceptable because accepting a truly nullable pattern is not.

### How Verified

- Run `moon check` after the fields and validation helpers are added.
- Add parser-focused tests in Step 5; this step itself should remain green without changing generated outputs.

## Step 2: Lexer Emitter Skeleton And Candidate Model

### Goal

Add `loomgen/emit_lexer.mbt` with a reusable internal candidate model and validation entry point, but do not wire it into the CLI yet.

### Files Touched

- `loomgen/emit_lexer.mbt`

### What Each Function Does

- `LexerCandidate`: internal generated-candidate record containing token constructor text, variant name, declaration index, candidate kind (`pattern` or `punct`), match expression source, and role.
- `collect_lexer_inputs(token_enum)`: returns pattern candidates, punct candidates, keywords, custom lexer calls, Ident variant, EOF variant, and ErrorToken variant; raises a generation error string on invalid lexer-specific state.
- `token_expr_for(variant)`: emits the token constructor expression for zero-arg variants and validates that regex/punct/keyword/ident/trivia/delimiter/literal candidates are zero-arg. Error fallback handles the error variant separately.
- `error_token_expr(error_variant, message_expr)`: emits the fallback error token expression, using a single `String` payload when present and rejecting unsupported error payload shapes.
- `emit_keyword_lookup(keywords, token_qual)`: emits a generated `Map[String, Token]` or `match`-based lookup. Prefer `Map[String, Token]` to align with the design and keep generated lookup compact; use `escape_string` for keys.
- `emit_lexer(token_enum, token_qual, core_qual, step_name?)`: returns `Result[String, String]` containing the generated file.

### Invariants

- Reuse `StringBuilder` accumulation and `escape_string` from `emit_token_impls.mbt`.
- Reuse `derive_kind_name` only where kind naming is needed for diagnostics; token construction is based on the token enum variant name.
- No generated regex attempts to escape or translate `#loom.pattern`; only prefix `^`.
- Punctuation candidates use `cursor.starts_with("literal")` and candidate length `literal.length()`.
- Candidates are collected in token declaration order, preserving tiebreak order.
- If `--lexer` is requested, every non-keyword, non-eof, non-error token variant must be lexable by at least one of: `#loom.pattern`, `#loom.punct`, or `#loom.custom_lex`. Otherwise generation errors, because the token would be unreachable from the generated scanner.

### How Verified

- Run `moon check` with the new file present but unused.
- Ensure the new file compiles as part of the `loomgen` package without changing CLI behavior.

## Step 3: Emit Longest-Match Step Lexer

### Goal

Complete `emit_lexer` so it emits the actual `lexer.g.mbt` step function and helper table.

### Files Touched

- `loomgen/emit_lexer.mbt`

### What Each Function Does

- Generated keyword helper:
  - Stores keyword string to token mapping as a top-level fixed table.
  - Looks up matched Ident text after Ident wins longest-match.
- Generated custom-lex block:
  - Emits a doc comment naming expected signature `(String, Int) -> @core.LexStep[Token]`.
  - Calls custom lexer functions in token declaration order.
  - Uses non-`Done` custom results immediately and falls through on `Done`.
- Generated `fn lex(source, pos) -> @core.LexStep[Token]`:
  - Creates `let cursor = @core.LexCursor::new(source, pos)`.
  - Returns `Done` if `cursor.is_done()`.
  - Initializes best-token state from all candidates.
  - For every pattern candidate, emits `match cursor.view() =~ (re"^PATTERN" as m)` and records `m.length()` if it is longer than the current best. Equal lengths keep the existing best to preserve declaration order.
  - For every punct candidate, uses `cursor.starts_with("literal")` and `literal.length()` in the same best-length comparison.
  - If no candidate matched, returns `@core.LexStep::Invalid(at=pos, width=@core.next_char_offset(source, pos) - pos, message="Unexpected character")`.
  - If a candidate matched, advances by best length, post-classifies Ident text through the keyword table if the winning role is Ident, then returns `cursor.produced(token)`.

### Invariants

- Every emitted pattern literal is `re"^PATTERN"`.
- Declaration order is represented only by candidate evaluation order and strict `>` best-length updates; equal length never overwrites the previous winner.
- Keyword variants never create regex branches.
- Keyword post-classification only happens when the winning candidate is the Ident variant.
- EOF token is not emitted by the step lexer; `TokenBuffer` appends EOF downstream.
- Error fallback advances by one scalar width using `@core.next_char_offset`, matching the recovery pattern in `examples/json/lexer.mbt`.
- Generated code uses `@core.LexCursor`, `@core.LexStep`, `Map`, `match`/`guard`, and callbacks idiomatically; no incidental index-loop logic appears in generated source except where generated best-candidate state genuinely requires it.

### How Verified

- Run `moon check`.
- Use a local scratch generation command only after Step 4 wires the CLI; before that, verify through direct emitter tests added in Step 5.

## Step 4: CLI Wiring For `--lexer`

### Goal

Expose lexer generation through `loomgen` without changing existing output behavior unless `--lexer` is present.

### Files Touched

- `loomgen/main.mbt`

### What Each Function Does

- `parse_args`: add `@argparse.OptionArg("lexer", about="Output path for generated lexer (.g.mbt)")`.
- `main`: read `lexer_path` from matches and pass it into output writing.
- `write_outputs`: add a `lexer_path : String?` parameter and, when present, call `emit_lexer(te, token_qual, core_qual, step_name=None)` and write the returned content to the requested path.

### Invariants

- `--lexer <out_path>` is independent of `--spec` and `--skip-syntax`.
- `--lexer` requires only a valid token enum and uses `--token-qual` and `--core-qual`.
- `--lexer` does not require a term enum, `--language`, or syntax output.
- Existing generated outputs remain unchanged when `--lexer` is absent.
- Error handling mirrors `--spec`: emitter validation errors print `error: <msg>` and exit nonzero; file-write errors name the failed path.

### How Verified

- Run `moon check`.
- Run the existing fixture generation commands without `--lexer` and confirm no unexpected generated-file diffs.

## Step 5: Fixtures And Tests

### Goal

Add regression coverage for generated source shape, runtime behavior, nullable rejection, and custom lexer ordering.

### Files Touched

- `loomgen/fixtures/pattern_lexer_fixture.mbt`
- `loomgen/fixtures/pattern_lexer_fixture.g.mbt`
- `loomgen/emit_lexer_test.mbt` or another package-local `*_test.mbt`
- `loomgen/README.md` if the fixture list is expanded

### What Each Test Covers

- Golden test:
  - Generate from a small CSS-like fixture or an extended `term_kind`-style token enum.
  - Include `#loom.punct("-")`, `#loom.punct("->")`, `#loom.keyword("let")`, Ident pattern, integer/literal pattern, trivia pattern, error, and EOF.
  - Snapshot `lexer.g.mbt` against `loomgen/fixtures/pattern_lexer_fixture.g.mbt`.
  - Expected outcome: emitted source contains anchored regex literals, `starts_with` punct candidates, custom lexer call comments if present, keyword lookup, `Done` at EOF, and scalar-width `Invalid` fallback.
- Behavioral test:
  - Compile and exercise the generated lexer against sample input containing `->`, `-`, `let`, an identifier like `letter`, whitespace, and an integer.
  - Expected outcome: `->` is one Arrow token, not two tokens; `let` is keyword after Ident wins; `letter` remains Ident; trivia is produced by its own pattern; EOF is appended only by `TokenBuffer`.
- Nullable-pattern rejection test:
  - Feed fixtures or inline source containing `#loom.pattern("")`, `#loom.pattern("[a-z]*")`, `#loom.pattern("(foo)?")`, and a top-level nullable alternation.
  - Expected outcome: generation fails before emitting `lexer.g.mbt` with a message naming the nullable variant.
- Custom-lex call-ordering test:
  - Include two `#loom.custom_lex` variants in declaration order and generated helper stubs in the test package.
  - Expected outcome: generated source calls the first custom function before the second; at runtime a non-`Done` result from the first prevents the second and regex pass from running, while `Done` falls through.

### Invariants

- Tests describe outcomes through snapshots and assertions, not pasted generated implementation bodies.
- Fixture patterns use MoonBit `re` dialect directly, including escaped hyphen in char classes when needed.
- Each test can run under the `loomgen` package’s native target.
- If Markdown files are added, moved, or removed, update `docs/README.md` per the documentation protocol. Adding this plan under `loomgen/` does not require a docs index update.

### How Verified

- Run `moon check`.
- Run targeted `moon test loomgen --target native`.
- If snapshot content is generated, run `moon test loomgen --target native --update`, review the fixture diff, then run `moon test loomgen --target native` again.

## Step 6: End-To-End Validation And Documentation Touches

### Goal

Confirm the new generator path works through the public CLI and document the fixture workflow.

### Files Touched

- `loomgen/README.md`
- No ADR file unless the implementation closes a larger accepted design plan; this plan is an implementation plan for an already converged issue design.

### What Each Function Does

- No new runtime functions in this step.
- README update lists the pattern lexer fixture and shows a `moon run loomgen --target native -- --lexer <path> ...` verification command.

### Invariants

- The generated `lexer.g.mbt` compiles in a consumer package that imports the token enum and `loom/core`.
- Existing `token_impls.g.mbt`, `syntax_kind.mbt`, view, and spec generation are unchanged unless their inputs changed.
- `moon fmt` is run before final verification.
- `moon info` is run to review intended public API changes for the `loomgen` package; generated interface changes should be limited to any public helpers intentionally exposed.

### How Verified

- Run `moon check`.
- Run `moon test loomgen --target native`.
- Run `moon run loomgen --target native -- loomgen/fixtures/pattern_lexer_fixture.mbt <tmp-token-out> <tmp-syntax-out> --lexer <tmp-token-out>/lexer.g.mbt` using the actual argparse ordering accepted by the tool.
- Compile the generated fixture consumer or test package that imports the generated `lexer.g.mbt`.
- Run `moon fmt`.
- Run `moon info` and review generated interface diffs.

## Open Questions / Risks

- The exact generated step function name should default to `lex` per the issue text, but existing examples expose `json_step_lexer` plus a batch `lex`. If consumer packages need both names, add a CLI option later rather than overloading this implementation.
- `Map[String, Token]` for keywords is compact but may allocate at initialization depending on MoonBit lowering. If that is undesirable, switch the generated helper to a `match` on the matched string; behavior is identical.
- The nullable-pattern checker is deliberately shallow. It must be sound for obvious nullable forms, but it may reject safe complex regexes. Error messages should say the check is conservative and advise rewriting the pattern with an explicit required atom.
- Compile-time regex literal errors still surface when the generated `lexer.g.mbt` is compiled, because `loomgen` cannot run or fully validate the MoonBit regex dialect.
- Custom lexers are author-defined MoonBit functions in non-generated files. Missing functions will be compiler errors in the consumer package, not `loomgen` parse errors.

## Reuse Check

- Reuse `StringBuilder` for all emitter accumulation.
- Reuse `escape_string` for generated ordinary MoonBit string literals such as keywords, punctuation, and messages. For regex literals, keep the captured pattern body verbatim and only add the leading `^`; any escaping needed inside the regex is the language author's responsibility.
- Reuse `derive_kind_name` only for diagnostics or existing kind alignment; do not create a new kind-naming path.
- Reuse `@core.LexCursor::new`, `view`, `starts_with`, `advance_code_units`, `produced`, and `@core.next_char_offset`.
- Reuse `@core.LexStep` constructors directly for `Done`, `Invalid`, and custom-lex result matching.
- Reuse `Map[String, Token]` or a generated `match` for keyword post-classification.
- Keep new helpers scoped by responsibility: annotation extraction/validation in `parse_annotations.mbt`, candidate collection and source emission in `emit_lexer.mbt`, and CLI/file writing in `main.mbt`.
