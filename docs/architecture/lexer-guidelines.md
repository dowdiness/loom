# Lexer Guidelines

Current lexer work should prefer shared cursor and offset helpers over ad hoc
UTF-16 code-unit scans. MoonBit string offsets are UTF-16 code-unit offsets, so
token lengths, `TokenBuffer` starts, and `Edit` ranges must stay in that unit.
That does not mean lexers should advance with `pos + 1` for arbitrary text:
doing so can split non-BMP characters such as emoji.

## Preferred Patterns

- Use `@core.LexCursor` for step lexers. It centralizes clamping, current
  `StringView`, token length normalization, and Unicode-scalar advancement.
- Use `LexCursor::view()` and `StringView` pattern matching for keyword,
  operator, and delimiter dispatch. This keeps lexer branches readable and
  avoids repeated `code_unit_at(pos + n)` checks.
- Use `LexCursor::set_view(rest)` after matching a `StringView` pattern that
  returns the unmatched suffix.
- Use `LexCursor::advance_char()` when consuming one Unicode scalar value from
  a cursor.
- Use `@core.next_char_offset(source, pos)` when a lexer scans with local
  integer offsets instead of a `LexCursor`.
- For external lexers that already return positioned tokens, adapt through
  `@core.LocatedToken` and `@core.LexResult::from_located_tokens` instead of
  hand-building parallel token/start arrays. Configure gap tokens only when the
  external lexer intentionally omits trivia; keep non-blank gaps diagnostic by
  default unless the external lexer has already reported the same error.

## Mode-aware opaque string contexts

When one delimiter has two lexical meanings, a quote-only prefix step cannot
choose the right tokenization. For example, `s("bd sd")` may need notation
words while `section("verse: 1")` must preserve the spaces and colon as one
opaque token. Splitting punctuation after tokenization or slicing source text
in the parser is a workaround: it loses the lexical span contract and makes
incremental convergence harder to prove.

Keep the choice in a small lexical state machine. The normal state recognizes
the head (`s` or `section`) and carries that fact through the ASCII `(` step;
the next state assigns the shared `"` delimiter to notation or opaque content.
Notation emits its word and punctuation pieces, opaque scans through spaces and
punctuation until the closing quote, and the closing quote returns to normal.
Every `Produced` step must advance; EOF returns `Done` without inventing a
quote or changing parser state.

Wire the state machine through the existing mode-lexer boundary:

```mbt nocheck
let mode_lexer : @core.ModeLexer[Token, LexMode] = {
  initial_mode: Normal,
  lex_step: lex_step,
}
let mode_relex = @core.erase_mode_lexer(
  mode_lexer,
  Eof,
  error_token=Error,
)
let grammar = @loom.Grammar::new(
  spec~, lex~, fold_node~, mode_relex=Some(mode_relex),
)
```

`erase_mode_lexer` provides detached tokenization and a factory. Each
`TokenBuffer` owns its `ModeRelexState` session; edits re-lex from the damage
frontier until both source position and lexical mode converge, then reuse the
unchanged suffix. Do not use the parser-local
`@core.ParserContext::set_lex_mode` for this wiring: it preserves a parser
callback's scalar state but does not configure `TokenBuffer`, `ModeLexer`, or
already-produced tokens.

The checked mixed-context recipe is in the [mode lexer fixture](../../loom/core/mode_lexer_wbtest.mbt)
and its [incremental re-lex test](../../loom/core/mode_relex_wbtest.mbt).
Related in-repository recipes cover [Markdown code fences](../../examples/markdown/lexer.mbt),
[HTML raw text](../../examples/html/lexer.mbt), and [JSX opaque braces](../../examples/jsx/lexer.mbt).

## Recovery And Progress

Core step-lexer recovery paths use Unicode-safe progress for malformed lexer
reports:

- no-progress `Produced` steps advance with `next_char_offset`
- zero-width or stale `Invalid` steps recover with a shared internal offset
  helper
- positive-width `Invalid` steps whose reported end would split a surrogate
  pair are snapped forward to the scalar boundary
- `TokenBuffer::new_from_steps`, strict step tokenization, and
  `PrefixLexer::lex_all` preserve non-BMP scalars during defensive progress
- the deprecated `TokenBuffer::new_resilient` fallback also emits a whole
  Unicode scalar for unlexable non-BMP input

Recoverable lexer paths must preserve the error information as diagnostics:

- `TokenBuffer::new_from_steps` records `LexStep::Invalid` and
  `LexStep::Incomplete` messages in `DiagnosticSet`
- defensive no-progress recovery records a lexer diagnostic instead of
  silently correcting the cursor
- `TokenBuffer::get_diagnostics()` exposes the lexer diagnostics that parser
  factories merge with parser diagnostics

When adding a new recovery path, avoid `pos + 1` unless the code is explicitly
walking ASCII syntax or intentionally indexing a single UTF-16 code unit.

## Example Status

- JSON and Lambda lexers use `LexCursor`.
- JSON, Lambda, and Markdown lexer branches use `StringView` matching where it
  improves keyword/operator/newline handling.
- Markdown text/code runs use `next_char_offset` so non-BMP characters remain
  whole in token spans.
