# Generic Parser Core (loom/src/core/)

The `dowdiness/loom/core` package exposes a language-agnostic parsing infrastructure. Any MoonBit project can define a new parser by providing token and syntax-kind types — no need to reimplement the CST, error recovery, or incremental subtree-reuse logic.

## Three Core Types

### TokenInfo

A generic token with source position:

```moonbit
pub struct TokenInfo[T] {
  token : T
  start : Int
  end   : Int
}
```

`T` is the language-specific token type. The lexer produces `Array[TokenInfo[T]]`; the parser consumes it through `ParserContext`.

### LanguageSpec

Describes one language. Create once at module initialisation, reuse across all parses:

```moonbit
pub struct LanguageSpec[T, K] {
  whitespace_kind    : K
  error_kind         : K
  root_kind          : K
  eof_token          : T
  cst_token_matches  : (RawKind, String, T) -> Bool
  parse_root         : (ParserContext[T, K]) -> Unit
}
```

- `T` — language-specific token type; must implement `Eq + IsTrivia + IsEof`
- `K` — language-specific syntax kind type; must implement `ToRawKind`
- `whitespace_kind`, `error_kind`, `root_kind` — fixed kinds used for trivia nodes, error recovery, and the implicit root wrapper
- `eof_token` — sentinel token returned when the parser advances past the end of input
- `cst_token_matches` — compares a CST token (kind + text) against a new token for incremental reuse; return `false` to disable cst-level matching
- `parse_root` — entry-point grammar function, used by `parse_tokens_indexed`

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

`mark()` / `start_at()` implement the tombstone pattern described in [seam-model.md](seam-model.md). They are essential for left-associative constructs where the outer node kind is not known until after the first child is parsed.

## Entry Points

```moonbit
// Simple: tokenize + parse in one call
pub fn parse_with[T : IsTrivia, K : ToRawKind](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, Array[Diagnostic[T]])

// Advanced: pre-tokenized, optional reuse cursor, returns reuse_count
pub fn parse_tokens_indexed[T : IsTrivia, K : ToRawKind](
  source        : String,
  token_count   : Int,
  get_token     : (Int) -> T,
  get_start     : (Int) -> Int,
  get_end       : (Int) -> Int,
  spec          : LanguageSpec[T, K],
  cursor?       : ReuseCursor[T, K]?,
  prev_diagnostics? : Array[Diagnostic[T]]?,
) -> (@seam.CstNode, Array[Diagnostic[T]], Int)
```

`parse_with` drives a complete fresh parse. `parse_tokens_indexed` is used by the incremental path — pass a `ReuseCursor` built from the previous tree and damage range to enable subtree reuse.

Error recovery uses two layers. Low-level primitives (`bump_error()`, `emit_error_placeholder()`) let grammars handle recovery manually. Higher-level combinators (`expect`, `skip_until`, `skip_until_balanced`, `node_with_recovery`, `expect_and_recover`) provide reusable patterns — the grammar decides which layer to use.

## Reference Implementation

The Lambda Calculus parser in `examples/lambda/src/` is the reference implementation:

- `lambda_spec.mbt` — defines the `LanguageSpec` for lambda calculus; implements `IsTrivia`/`IsEof` on `Token` and `ToRawKind` on `SyntaxKind`
- `cst_parser.mbt` — implements the grammar functions that call into `ParserContext`
