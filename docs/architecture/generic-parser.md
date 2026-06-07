# Generic Parser Core (loom/src/core/)

The `dowdiness/loom/core` package exposes a language-agnostic parsing infrastructure. Any MoonBit project can define a new parser by providing token and syntax-kind types — no need to reimplement the CST, error recovery, or incremental subtree-reuse logic.

## Three Core Types

### TokenInfo And LexResult

A generic position-independent token:

```moonbit
pub struct TokenInfo[T] {
  token : T
  len   : Int
}
```

`T` is the language-specific token type. Token starts are tracked outside the
token array so token values remain stable across reuse checks. `len` is a
MoonBit string length: a UTF-16 code-unit count, not a byte count.

Recovering lexer paths use `LexResult[T]`:

```moonbit
pub struct LexResult[T] {
  tokens      : Array[TokenInfo[T]]
  starts      : Array[Int]
  diagnostics : DiagnosticSet
}
```

Use `LexResult::with_starts` when a lexer already produces Loom's parallel
`TokenInfo` and start arrays. For production lexers that return positioned
source spans, prefer the located-token adapter instead of hand-building those
parallel arrays:

```moonbit
pub struct LocatedToken[T] { ... }

pub fn LocatedToken::LocatedToken(
  token : T,
  start~ : Int,
  end~ : Int,
) -> LocatedToken[T]

pub fn LexResult::from_located_tokens(
  source : String,
  located_tokens : Array[LocatedToken[T]],
  gap_token? : (StringView, Int, Int) -> T,
  gap_error_token? : (StringView, Int, Int) -> T,
  diagnostics? : DiagnosticSet,
  gap_error_code? : String,
  diagnose_nonblank_gaps? : Bool,
) -> LexResult[T]
```

The adapter contract is:

- `start` and `end` are half-open UTF-16 code-unit offsets into `source`.
- `located_tokens` must already be sorted in source order; the adapter preserves
  caller order and does not sort for you.
- Positive-width token spans must not overlap. Zero-width tokens are valid when
  `start == end`, so adjacent starts may repeat at token-stream boundaries
  (for example, inserted ASI semicolon tokens).
- Invalid external spans — negative offsets, reversed ranges, or offsets beyond
  `source.length()` — are recorded as lexer diagnostics before the adapter
  safely normalizes them for `LexResult` construction.
- Gaps between located spans are explicit policy points. Blank gaps are skipped
  unless `gap_token` is supplied; then the callback produces a token for the
  blank source slice. Non-blank gaps emit an `unlexed source gap` diagnostic by
  default and can also be represented by `gap_error_token`. Set
  `diagnose_nonblank_gaps=false` only when the external lexer has already
  reported the same source gap.
- The optional `diagnostics` argument is copied into the result and then merged
  with adapter diagnostics such as invalid spans, non-blank gaps, and final
  `LexResult` invariant checks. `TokenBuffer` stores those lexer diagnostics;
  parser entry points append parser diagnostics before returning to callers.

See `examples/moonbit/src/lexer_adapter.mbt` for a concrete consumer that adapts
`moonbitlang/parser/lexer` UTF-16 locations through `LocatedToken` and
`LexResult::from_located_tokens`.

### LanguageSpec

Describes one language. Create once at module initialisation, reuse across all parses:

```moonbit
pub struct LanguageSpec[T, K] {
  whitespace_kind    : K
  error_kind         : K
  root_kind          : K
  eof_token          : T
  parse_root         : (ParserContext[T, K]) -> Unit
}
```

- `T` — language-specific token type; must implement `Eq + IsTrivia + IsEof + ToRawKind`
- `K` — language-specific syntax kind type; must implement `ToRawKind`
- `whitespace_kind`, `error_kind`, `root_kind` — fixed kinds used for trivia nodes, error recovery, and the implicit root wrapper
- `eof_token` — sentinel token returned when the parser advances past the end of input
- `parse_root` — entry-point grammar function, used by `parse_tokens_indexed`

Token matching for incremental reuse is handled by the framework internally:
`old_cst_token.kind == new_token.to_raw() && old_cst_token.text() == token_text_at(pos)`.
Languages do not need to implement token matching — `T : ToRawKind` is sufficient.

### Required Traits

`T` (token type) must implement:

| Trait | Method | Purpose |
|-------|--------|---------|
| `@seam.IsTrivia` | `is_trivia(self) -> Bool` | Identifies whitespace/comments to skip |
| `@seam.IsEof` | `is_eof(self) -> Bool` | Identifies the end-of-input sentinel |
| `Eq` | `==` | Token comparison in `ctx.at(token)` |

`K` (syntax kind type) must implement:

| Trait | Method | Purpose |
|-------|--------|---------|
| `@seam.ToRawKind` | `to_raw(self) -> RawKind` | Maps to the integer used by seam |

These replace the closures that older versions carried in `LanguageSpec` (`kind_to_raw`, `token_is_trivia`, `token_is_eof`, `tokens_equal`, `print_token`).

### ParserContext

Core parser state. Grammar functions receive a `ParserContext` and call methods on it to build the CST event stream:

```moonbit
pub struct ParserContext[T, K] { ... }
```

The internal fields are not part of the public API. All interaction is through the methods listed below.

## Grammar API

Methods that grammar functions call on `ParserContext`:

```moonbit
ctx.peek()                    // next non-trivia token (does not consume)
ctx.at(token)                 // test whether current token equals the given token
ctx.at_eof()                  // test whether all input has been consumed
ctx.node(kind, body)          // reuse-aware node: try reuse, else start_node→body→finish_node
ctx.emit_token(kind)          // consume current token, emit it as a leaf with the given kind
ctx.start_node(kind)          // open a new node frame with the given kind
ctx.finish_node()             // close the most recently opened node frame
ctx.mark()                    // reserve a retroactive-wrap position (returns a Mark)
ctx.start_at(mark, kind)      // retroactively wrap children emitted since mark
ctx.wrap_at(mark, kind, body) // start_at + body + finish_node
ctx.error(msg)                // record a diagnostic without consuming a token
ctx.bump_error()              // consume current token as an error token
ctx.emit_error_placeholder()  // emit a zero-width error token (for missing tokens)

// Recovery combinators (recovery.mbt):
ctx.expect(token, kind)                    // consume if match, else diagnostic + placeholder
ctx.skip_until(is_sync)                    // skip to sync point, wrap skipped in error node
ctx.skip_until_balanced(is_open, is_close) // bracket-aware skip with nesting depth
ctx.node_with_recovery(kind, body, sync)   // reuse-aware node with automatic recovery
ctx.expect_and_recover(token, kind, sync)  // expect + skip + retry pattern
```

`ctx.node(kind, body)` is the primary building block: it attempts incremental reuse from a prior parse, falling back to `start_node → body() → finish_node` on a miss. Prefer it over bare `start_node`/`finish_node` whenever incremental parsing is needed.

Zero-width leaves have provenance. Lexer-produced zero-width tokens are
source-backed and can be real token-stream boundary context. Parser-produced
placeholders from `emit_zero_width()` / `emit_error_placeholder()` are synthetic
and intentionally are not lexer context. During reuse, boundary ownership is
computed from structural child offsets — the reused node start plus accumulated
child `text_len` — not from `CstToken::start_offset()` / `end_offset()`, which
are backing-source spans. PR #221 added regression coverage for this in
`loom/src/core/parser_wbtest.mbt`: `ParserContext reuse: zero-width lexer leaf
at reused boundary advances position` and `ParserContext reuse: interned
zero-width lexer boundary advances position`.

`mark()` / `start_at()` implement the tombstone pattern described in [seam-model.md](seam-model.md). They are essential for left-associative constructs where the outer node kind is not known until after the first child is parsed.

## Entry Points

```moonbit
// Simple: tokenize + parse in one call
pub fn parse_with[T : IsTrivia + ToRawKind, K : ToRawKind](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, DiagnosticSet)

// Advanced: pre-tokenized, optional reuse cursor, returns reuse_count
pub fn parse_tokens_indexed[T : IsTrivia + ToRawKind, K : ToRawKind](
  source        : String,
  token_count   : Int,
  get_token     : (Int) -> T,
  get_start     : (Int) -> Int,
  get_end       : (Int) -> Int,
  spec          : LanguageSpec[T, K],
  cursor?       : ReuseCursor[T, K]?,
  prev_diagnostics? : DiagnosticSet?,
) -> (@seam.CstNode, DiagnosticSet, Int)
```

`parse_with` drives a complete fresh parse. `parse_tokens_indexed` is used by
the incremental path; pass a `ReuseCursor` built from the previous tree and the
`Edit` that produced the new token stream to enable subtree reuse.

Application code should normally stay above this layer and call
`Parser::apply_edit` / `ImperativeParser::edit`. Grammar-specific cursor helpers
should prefer `ReuseCursor::new_with_edit` (or their own `*_with_edit` wrapper).
`ReuseCursor::new` accepts raw old-source damage coordinates and is reserved for
low-level infrastructure, focused tests, and callers that have already computed
both old and new damage endpoints.

Error recovery uses two layers. Low-level primitives (`bump_error()`, `emit_error_placeholder()`) let grammars handle recovery manually. Higher-level combinators (`expect`, `skip_until`, `skip_until_balanced`, `node_with_recovery`, `expect_and_recover`) provide reusable patterns — the grammar decides which layer to use.

## Reference Implementation

The Lambda Calculus parser in `examples/lambda/src/` is the reference implementation:

- `lambda_spec.mbt` — defines the `LanguageSpec` for lambda calculus; implements `IsTrivia`/`IsEof` on `Token` and `ToRawKind` on `SyntaxKind`
- `cst_parser.mbt` — implements the grammar functions that call into `ParserContext`
