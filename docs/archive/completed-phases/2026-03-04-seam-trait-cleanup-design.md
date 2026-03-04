# Seam trait cleanup + token_at_offset design

**Date:** 2026-03-04
**Status:** Approved

## Problem

`LanguageSpec[T, K]` carries seven closures that duplicate knowledge already implicit in the
language's token and syntax-kind types:

```moonbit
kind_to_raw     : (K) -> RawKind
raw_is_trivia   : (RawKind) -> Bool
raw_is_error    : (RawKind) -> Bool
token_is_trivia : (T) -> Bool
token_is_eof    : (T) -> Bool
tokens_equal    : (T, T) -> Bool
print_token     : (T) -> String
```

These closures cause duplication (e.g. `reuse_cursor.mbt` has private `first_token_text` /
`first_token_kind` helpers that mirror `spec.raw_is_trivia`), complicate the constructor
call-site, and grow harder to maintain as more languages are added.

Additionally, `CstNode` has no `first_token` method, and `SyntaxNode` has no
`token_at_offset` query — gaps that force callers to re-implement traversal logic.

## Solution overview

Two-phase delivery:

- **Phase 1** — define K-traits in seam, clean K-side of `LanguageSpec`, add `CstNode::first_token` and `SyntaxNode::token_at_offset`.
- **Phase 2** — define T-traits in seam, clean T-side of `LanguageSpec` (all remaining closures).

After both phases, `LanguageSpec` retains only two irreducible items: `cst_token_matches`
(cross-layer old-CST↔new-token comparison) and `parse_root` (grammar entry point).

---

## Phase 1 — K-traits + new SyntaxNode APIs

### 1.1 New traits in `seam/kind_traits.mbt`

```moonbit
pub(open) trait ToRawKind   { to_raw(Self) -> RawKind }
pub(open) trait FromRawKind { from_raw(RawKind) -> Self }
pub(open) trait IsTrivia    { is_trivia(Self) -> Bool }
pub(open) trait IsError     { is_error(Self) -> Bool }
```

`FromRawKind` is a static constructor-style trait method (return type is `Self`).
All four traits live in seam so that both loom and language packages can reference them.

### 1.2 `SyntaxKind` implementations (lambda)

Convert existing plain functions to trait impls:

```moonbit
pub impl @seam.ToRawKind   for SyntaxKind with to_raw(self)  { ... } // existing body
pub impl @seam.FromRawKind for SyntaxKind with from_raw(raw) { ... } // existing body
pub impl @seam.IsTrivia    for SyntaxKind with is_trivia(self) { self == WhitespaceToken }
pub impl @seam.IsError     for SyntaxKind with is_error(self)  { self == ErrorToken }
```

The plain `SyntaxKind::to_raw` / `SyntaxKind::from_raw` functions are removed; all call
sites use the trait dispatch.

### 1.3 `LanguageSpec[T, K: ToRawKind]` — drop 3 K-side fields

| Removed field | How it was used | Replacement |
|---|---|---|
| `kind_to_raw : (K) -> RawKind` | convert K value to raw for tree ops | `k.to_raw()` |
| `raw_is_trivia : (RawKind) -> Bool` | skip whitespace in reuse cursor | `raw == spec.whitespace_kind.to_raw()` |
| `raw_is_error : (RawKind) -> Bool` | detect error tokens in reuse cursor | `raw == spec.error_kind.to_raw()` |

`whitespace_kind : K` and `error_kind : K` fields remain — they provide the reference value
for the inline comparisons.

`LanguageSpec::new` drops the three corresponding constructor parameters
(`kind_to_raw`, `raw_is_trivia?`, `raw_is_error?`).

The `lambda_spec` construction site drops three arguments.

### 1.4 `reuse_cursor.mbt` cleanup

Private helpers `first_token_text` and `first_token_kind` are deleted.
Their callers are rewritten using `CstNode::first_token` (see §1.5).

### 1.5 New seam APIs

**`CstNode::first_token`** — DFS first leaf, with predicate for trivia skipping:

```moonbit
pub fn CstNode::first_token(
  self : CstNode,
  is_trivia : (RawKind) -> Bool,
) -> CstToken?
```

Call site in reuse cursor:

```moonbit
node.first_token(fn(r) { r == spec.whitespace_kind.to_raw() })
```

**`TokenAtOffset`** enum + **`SyntaxNode::token_at_offset`**:

```moonbit
pub enum TokenAtOffset {
  None
  Single(SyntaxToken)
  Between(SyntaxToken, SyntaxToken)   // cursor sits exactly on a token boundary
} derive(Show, Debug, Eq)

pub fn SyntaxNode::token_at_offset(self : SyntaxNode, offset : Int) -> TokenAtOffset
```

Algorithm: DFS into the deepest node whose span contains `offset`; collect the token
immediately to the left (`end == offset`) and immediately to the right (`start == offset`).

---

## Phase 2 — T-traits + LanguageSpec T-side cleanup

### 2.1 New traits in `seam/kind_traits.mbt`

```moonbit
pub(open) trait IsEof { is_eof(Self) -> Bool }
```

(`IsTrivia` already defined in Phase 1 — reused for T.)

### 2.2 `Token` implementations (lambda)

```moonbit
// token/token.mbt — add to existing file
pub impl @seam.IsTrivia for Token with is_trivia(self) { self == Whitespace }
pub impl @seam.IsEof    for Token with is_eof(self)    { self == EOF }
```

`Token` already derives `Eq` and `Show`. `derive(Debug)` is added alongside them.
`Show` is re-implemented manually to produce the concise diagnostic format:

```moonbit
pub impl Show for Token with output(self, logger) {
  logger.write_string(match self {
    Lambda => "λ"
    Dot => "."
    // ... concise forms for all variants
    Identifier(name) => name
    Integer(n) => n.to_string()
    Whitespace => "whitespace"
    EOF => "EOF"
  })
}
```

### 2.3 `LanguageSpec[T: Eq + Show + Debug + IsTrivia + IsEof, K: ToRawKind]` — drop 4 T-side fields

| Removed field | Replacement |
|---|---|
| `tokens_equal : (T, T) -> Bool` | `T: Eq`, `a == b` |
| `token_is_trivia : (T) -> Bool` | `T: IsTrivia`, `t.is_trivia()` |
| `token_is_eof : (T) -> Bool` | `T: IsEof`, `t.is_eof()` |
| `print_token : (T) -> String` | `T: Show`, `t.to_string()` |

### 2.4 Final `LanguageSpec` shape

Fields remaining after both phases:

```moonbit
pub struct LanguageSpec[T: Eq + Show + Debug + IsTrivia + IsEof, K: ToRawKind] {
  whitespace_kind  : K
  error_kind       : K
  root_kind        : K
  eof_token        : T
  cst_token_matches : (@seam.RawKind, String, T) -> Bool   // irreducible
  parse_root        : (ParserContext[T, K]) -> Unit         // grammar entry point
}
```

Seven closures removed (3 K-side + 4 T-side). Constructor call-site shrinks correspondingly.

---

## Files affected

| File | Change |
|---|---|
| `seam/kind_traits.mbt` | **new** — 5 trait definitions |
| `seam/cst_node.mbt` | add `CstNode::first_token` |
| `seam/syntax_node.mbt` | add `TokenAtOffset` + `SyntaxNode::token_at_offset` |
| `seam/pkg.generated.mbti` | regenerated |
| `loom/src/core/parser.mbt` | `LanguageSpec` struct + constructor updated (both phases) |
| `loom/src/core/reuse_cursor.mbt` | drop helpers, rewrite call sites |
| `examples/lambda/src/syntax/syntax_kind.mbt` | add 4 trait impls, remove plain functions |
| `examples/lambda/src/token/token.mbt` | add `IsTrivia`, `IsEof` impls + manual `Show` + `derive(Debug)` |
| `examples/lambda/src/lambda_spec.mbt` | drop 7 constructor arguments |

## Non-goals

- Removing `whitespace_kind`, `error_kind`, `root_kind`, `eof_token` value fields (possible
  future work using associated constants in traits).
- Making `cst_token_matches` a trait — it bridges old-CST RawKind+text against new-stream T,
  which is inherently cross-layer.
- Changing any public API of `SyntaxNode` beyond the two additions in §1.5.
