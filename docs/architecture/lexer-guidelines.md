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

## Recovery And Progress

Core step-lexer recovery paths use Unicode-safe progress for malformed lexer
reports:

- no-progress `Produced` steps advance with `next_char_offset`
- zero-width or stale `Invalid` steps recover with a shared internal offset
  helper
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
