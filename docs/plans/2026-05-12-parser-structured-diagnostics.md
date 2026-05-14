# Parser-Level Structured Diagnostics

**Status:** Active
**Date:** 2026-05-12

## Execution Notes

- 2026-05-13: PR #117 merged as
  `514d2d2 [codex] Add structured parser and lexer diagnostics (#117)`.
  It delivered token-erased `Diagnostic` / `DiagnosticSet`,
  `TextOffset` / `TextRange`, `LexResult`, lexer diagnostics in
  `TokenBuffer`, parser diagnostics as `DiagnosticSet`, block-reparse and
  incremental diagnostic shifting, JSON/Lambda strict parser token
  preservation, and review fixes for parser diagnostic dedupe, block-reparse
  lexer diagnostics, and insertion-boundary range shifting.
- 2026-05-14: Mode-aware lexing now has recoverable structured diagnostics.
  `erase_mode_lexer` requires an error token, `ModeRelexState::tokenize`
  returns `LexResult[T]`, incremental mode relex returns `ModeRelexResult[T]`
  with replacement diagnostics, and Markdown uses that total mode lexer
  boundary directly.
- 2026-05-14: The high-level parser boundary now publishes
  `ParseSnapshot[Ast]`. `ImperativeParser::{parse,edit,reset}` return
  snapshots, `Parser` stores one snapshot signal with derived views, diagnostics
  are `DiagnosticSet`, `syntax_tree()` is total, `ParseOutcome` is removed, and
  the unused grammar `on_lex_error` callback is gone.
- 2026-05-14: `ParserContext` now exposes structured reporting helpers:
  `report`, `report_error`, `report_at_current`, and `report_expected`.
  Current-token and EOF diagnostics carry token-erased evidence through
  `ToRawKind`, and focused tests cover structured reuse replay plus block
  reparse diagnostic offset/merge behavior.

## Context

PR #112 kept loom's canonical source coordinate system as UTF-16 code-unit
offsets and added `LineIndex` for presentation-time line/column derivation.
At plan start, the remaining high-level gap was the parser boundary:
`Parser::diagnostics()` and `ImperativeParser::diagnostics()` still exposed
formatted `Array[String]` values while lower-level parser code carried
`DiagnosticSet`.

That parser-boundary gap is now closed. Prefix-lexer recovery carries lexer
diagnostics through `TokenBuffer`, mode-aware lexing carries lexer diagnostics
through `LexResult`, and the high-level parser publishes `ParseSnapshot[Ast]`
with `DiagnosticSet` diagnostics. Remaining follow-up in this active plan is
narrower: decide whether the remaining string-first grammar call sites should
migrate to the new structured helpers immediately or stay on the compatibility
`error` wrapper.

This design assumes no backward compatibility requirement. Prefer the clean
architecture over compatibility shims.

Baseline facts captured when this plan was written and updated as slices
landed:

- `rtk moon check` passes on `main`.
- `@loom.Diagnostic` is a token-erased structured diagnostic re-exported from
  `@core`.
- `Array[Diagnostic]` and generic `ParseSnapshot[Ast]` can derive `Eq` when
  `Ast : Eq`, so structured diagnostics can live behind `@incr.Memo`.
- `SyntaxNode` implements `Eq`.
- Prefix and mode-aware grammar lexing can recover inline.
- The total high-level parsing work is complete: the engine-level
  `ParseOutcome::LexError` side channel was replaced with `ParseSnapshot[Ast]`.

## Goals

- Make diagnostics structured data, not formatted strings.
- Make the high-level parser publish one coherent parse snapshot.
- Keep UTF-16 code-unit offsets canonical; derive line/column coordinates only
  at presentation boundaries.
- Keep language-specific token types internal to lexing/parsing mechanics.
- Route lexer and parser diagnostics through the same data model.
- Make parser APIs suitable for editor and LSP consumers without requiring a
  second tokenization pass.

## Non-Goals

- Preserve `Array[String]` parser diagnostics.
- Add incremental `LineIndex`; build `LineIndex::new(source)` on demand until
  profiling proves it is a bottleneck.
- Design an LSP adapter.
- Reintroduce token-specific diagnostics in public parser-facing APIs.
- Remove every strict lexer helper. Strict tokenization can remain as a
  low-level test/debug API, but it must not be the high-level parser contract.

## Principles

1. **Diagnostics are data.** Formatting is a rendering step.
2. **Snapshots are atomic.** Source, syntax, AST, diagnostics, and reuse stats
   should travel as one parse result.
3. **High-level parsing is total.** Malformed user input should produce a tree
   with error/incomplete nodes plus diagnostics, not a missing syntax tree.
4. **Offsets are canonical.** Store UTF-16 code-unit ranges; derive line/column
   with `LineIndex`.
5. **Token evidence is erased.** Diagnostics may expose `RawKind` and ranges,
   but not the language-specific token type `T`.
6. **Invariant wrappers beat raw `Int`.** Use opaque `TextOffset` and
   `TextRange` so offsets cannot be mixed casually with counts or indexes.

## Proposed Data Model

Place these types in `loom/src/core/diagnostics.mbt`, replacing the former
public role of token-specific diagnostics.

```moonbit
pub struct TextOffset {
  priv value : Int
} derive(Eq, Debug, Hash, Compare)

pub(all) suberror DiagnosticBuildError {
  NegativeTextOffset(Int)
  InvalidTextRange(Int, Int)
} derive(Debug)

pub fn TextOffset::TextOffset(
  value : Int,
) -> TextOffset raise DiagnosticBuildError {
  guard value >= 0 else { raise NegativeTextOffset(value) }
  { value, }
}

pub fn TextOffset::value(self : TextOffset) -> Int {
  self.value
}

pub struct TextRange {
  priv start : TextOffset
  priv end : TextOffset
} derive(Eq, Debug, Hash, Compare)

pub fn TextRange::TextRange(
  start : TextOffset,
  end : TextOffset,
) -> TextRange raise DiagnosticBuildError {
  guard end.value() >= start.value() else {
    raise InvalidTextRange(start.value(), end.value())
  }
  { start, end }
}

pub fn TextRange::from_offsets(
  start : Int,
  end : Int,
) -> TextRange raise DiagnosticBuildError {
  TextRange(TextOffset(start), TextOffset(end))
}
```

Diagnostic records:

```moonbit
pub enum DiagnosticSeverity {
  Error
  Warning
  Info
  Hint
} derive(Eq, Debug)

pub struct DiagnosticSource {
  priv name : String
} derive(Eq, Debug, Hash)

pub struct DiagnosticCode {
  priv value : String
} derive(Eq, Debug, Hash)

pub struct TokenEvidence {
  kind : @seam.RawKind
  range : TextRange
} derive(Eq, Debug)

pub struct DiagnosticLabel {
  range : TextRange
  message : String?
} derive(Eq, Debug)

pub struct Diagnostic {
  source : DiagnosticSource
  severity : DiagnosticSeverity
  code : DiagnosticCode?
  message : String
  primary : TextRange?
  labels : Array[DiagnosticLabel]
  notes : Array[String]
  token : TokenEvidence?
} derive(Eq, Debug)

pub struct DiagnosticSet {
  priv items : Array[Diagnostic]
} derive(Eq, Debug)
```

`DiagnosticSet` owns collection behavior:

- `DiagnosticSet::empty()`
- `DiagnosticSet::single(Diagnostic)`
- `DiagnosticSet::items() -> Array[Diagnostic]` returning a defensive copy
- `DiagnosticSet::push(Diagnostic) -> Unit`
- `DiagnosticSet::extend(DiagnosticSet) -> Unit`
- `DiagnosticSet::is_empty() -> Bool`
- `DiagnosticSet::length() -> Int`
- `DiagnosticSet::format() -> Array[String]`
- `DiagnosticSet::format_with_line_col(LineIndex) -> Array[String]`
- `DiagnosticSet::offset_by(delta : Int, after : TextOffset) -> DiagnosticSet raise DiagnosticBuildError`

Deduplication should happen here, keyed by source, severity, code, message, and
primary range. Token evidence can refresh on duplicate reports, matching the
current `push_diagnostic_unique` behavior.

The offset/range constructors are checked custom constructors, not `::new`
factories. They must not clamp, normalize, drop, or `abort` on invalid input.
Invalid offsets and ranges preserve their original values in
`DiagnosticBuildError`. Parser and lexer recovery paths should catch those
errors at the boundary and convert them into structured diagnostics rather than
discarding information.

## Lexing Boundary

Introduce a total lexer output for high-level parser use:

```moonbit
pub struct LexResult[T] {
  tokens : Array[TokenInfo[T]]
  starts : Array[Int]
  diagnostics : DiagnosticSet
} derive(Eq, Debug)
```

The target high-level grammar path should eventually use:

```moonbit
lex : (String) -> LexResult[T]
```

instead of:

```moonbit
tokenize : (String) -> Array[TokenInfo[T]] raise LexError
```

Strict tokenizers can remain low-level helpers for tests and batch consumers
that want fail-fast lexing. The parser factory should not route strict lex
errors into a separate `ParseOutcome::LexError` channel.

### Prefix Lexer

`PrefixLexer` already reports `Invalid(at, width, message)` and
`Incomplete(at, expected)` and `TokenBuffer::new_from_steps` already recovers
by emitting error tokens. That path now:

- appends a lexer diagnostic for each `Invalid` / `Incomplete`
- records a diagnostic when a no-progress `Produced` step is defensively
  advanced
- keeps the current Unicode-safe recovery offset behavior
- keeps token starts explicit so late invalid offsets remain representable

This makes `error_token_from_message` unnecessary for user-facing messages.
Diagnostics carry messages; error tokens only need to preserve syntax shape.

### Mode Lexer

`ModeLexer` keeps strict `tokenize_with_modes` for low-level callers, while
`erase_mode_lexer` now builds a recoverable `ModeRelexState` for grammar use:

- full mode lexing returns `LexResult[T]` plus mode state
- mode relex returns replacement tokens, starts, convergence index, and
  diagnostics
- `Invalid` advances with the same recovery law as `PrefixLexer`
- the returned `next_mode` from `ModeLexer.lex_step` is used after a recovered
  invalid step; `Incomplete` records a diagnostic and stops at EOF

## Parser Boundary

Replace parser-level side channels with a parse snapshot:

```moonbit
pub struct ParseSnapshot[Ast] {
  source : String
  syntax : @seam.SyntaxNode
  ast : Ast
  diagnostics : DiagnosticSet
  reuse_count : Int
} derive(Eq, Debug)
```

`ImperativeParser` should store and return snapshots:

```moonbit
ImperativeParser::parse() -> ParseSnapshot[Ast]
ImperativeParser::edit(Edit, String) -> ParseSnapshot[Ast]
ImperativeParser::reset(String) -> ParseSnapshot[Ast]
ImperativeParser::current() -> ParseSnapshot[Ast]?
```

The reactive `Parser` should publish a single snapshot signal/view:

```moonbit
Parser::snapshot() -> @incr.Memo[ParseSnapshot[Ast]]
```

Convenience views are derived from the snapshot:

```moonbit
Parser::source() -> @incr.Memo[String]
Parser::syntax_tree() -> @incr.Memo[@seam.SyntaxNode]
Parser::ast() -> @incr.Memo[Ast]
Parser::diagnostics() -> @incr.Memo[DiagnosticSet]
```

`Parser::syntax_tree()` should no longer return `SyntaxNode?` in the high-level
API. Invalid input is represented by error/incomplete nodes and diagnostics.

## ParserContext Changes

ParserContext has been changed from:

```moonbit
errors : Array[{ message : String, start : Int, end : Int, got_token : T }]
```

to:

```moonbit
diagnostics : DiagnosticSet
```

`ParserContext` now has structured reporting helpers:

```moonbit
ParserContext::report(Diagnostic) -> Unit
ParserContext::report_error(message~ : String, code? : DiagnosticCode?, range? : TextRange?) -> Unit
ParserContext::report_at_current(message~ : String, code? : DiagnosticCode?) -> Unit
ParserContext::report_expected(expected~ : String, code? : DiagnosticCode?) -> Unit
```

`report_at_current` records token evidence when `T : ToRawKind`:

- current token range from `get_start` / `get_end`
- current token kind from `get_token(i).to_raw()`
- EOF token evidence from `spec.eof_token.to_raw()` and zero-width EOF range

The compatibility `error(String)` wrapper remains for existing grammar call
sites and delegates to `report_at_current`.

## Incremental Reuse And Block Reparse

The reuse path replays `DiagnosticSet` entries whose primary range falls inside
the reused node. Synthesis of reused diagnostics constructs real `Diagnostic`
values with:

- `source = DiagnosticSource::parser()`
- `severity = Error`
- `message = "reused syntax error"` initially, with a follow-up to produce a
  better code/message if needed
- token-erased evidence from the closest token

Block reparse should accept lex results rather than a raising tokenizer:

```moonbit
lex : (String) -> LexResult[T]
old_diagnostics : DiagnosticSet
```

Block diagnostics are offset by `block_start` and merged by `DiagnosticSet`.

## Line And Column Formatting

Do not store line/column in `Diagnostic`.

Add derived helpers:

```moonbit
Diagnostic::line_range(LineIndex) -> LineRange?
Diagnostic::format() -> String
Diagnostic::format_with_line_col(LineIndex) -> String
```

Line/column coordinates stay presentation-only and follow ADR
`2026-05-11-derived-source-locations`.

## Implementation Plan

1. Done: add the new diagnostic data model and `DiagnosticSet` helpers.
2. Done: convert `ParserContext` parse diagnostics to `DiagnosticSet`.
3. Done: convert low-level parse entry points to return `DiagnosticSet`.
4. Done: add `LexResult[T]` and migrate the prefix-lexer recovery path.
5. Done: add recovering mode-lexer variants and migrate Markdown.
6. Done: change `Grammar` and factories to consume `LexResult[T]`.
   `TokenBuffer::new_from_lex` now accepts a total structured lexer, parser
   factories merge lexer diagnostics with parser diagnostics, recovery policy
   lives inside the grammar's `lex` implementation, and range relex offsets
   diagnostics from re-lexed slices instead of discarding them.
7. Done: replace `ParseOutcome` / `ImperativeLanguage` side-channel diagnostics with
   `ParseSnapshot[Ast]`.
8. Done: collapse reactive `Parser` state to a snapshot signal plus derived
   views.
9. Done: update examples and public docs to use `DiagnosticSet`.
   Active and public-facing docs now describe `ParseSnapshot[Ast]` /
   `DiagnosticSet` as the high-level parser boundary. Stale `Array[String]`
   parser-diagnostic references are retained only as historical context.
10. Done: remove parser-level formatted string diagnostics.

Run after each meaningful step:

```bash
rtk moon check
```

Final verification:

```bash
rtk moon fmt
rtk moon check
rtk moon test
rtk moon info
rtk git diff --check
```

For touched examples:

```bash
cd examples/json && rtk moon test
cd examples/lambda && rtk moon test
cd examples/markdown && rtk moon test
```

## Tests To Add Or Update

- `DiagnosticSet` construction, defensive-copy, formatting, and dedupe tests.
- `TextOffset` / `TextRange` invariant tests.
- Done: `ParserContext::report_at_current` token-evidence tests.
- Done: prefix lexer invalid/incomplete diagnostics.
- Done: legacy resilient lexer diagnostics for recovered scalar ranges.
- Done: prefix lexer non-BMP diagnostic range assertions.
- Done: mode lexer invalid/incomplete diagnostics with mode-state recovery.
- Done: incremental reuse replays structured diagnostics without duplication.
- Done: block reparse offsets and merges structured diagnostics.
- Done: `Parser::snapshot()` updates source, syntax, AST, diagnostics, and reuse count
  atomically.
- Line/column formatting derives from `LineIndex` without mutating stored
  diagnostics.

## Risks And Follow-Ups

- Mode-aware recovery is the highest-risk part because convergence depends on
  mode and position alignment. Keep the first implementation conservative:
  fall back to full recovering mode lex when partial convergence is unclear.
- `ParseSnapshot[Ast]` equality compares `source`; this is acceptable for the
  first implementation because parser updates already know when source changes.
  Revisit only if profiling shows snapshot equality is hot.
- `DiagnosticSet::offset_by` must preserve optional ranges and labels
  consistently. Primary range and token-evidence offsetting are covered by block
  reparse tests; add label-specific tests before relying on label-heavy
  diagnostics.
- Done: example fail-fast `parse(...)` helpers use message-only `ParseError`
  payloads instead of reconstructing language-specific token payloads.

## Decision Record

No ADR is created for this item-9 documentation cleanup because the active plan
is not being completed or archived in this change. An ADR is required when this
plan is completed because the implementation changes public parser contracts
and establishes the diagnostic boundary policy.
