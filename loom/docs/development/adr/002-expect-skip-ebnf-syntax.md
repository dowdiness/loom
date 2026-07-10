# ADR 002: Token~> (ExpectSkip) EBNF Syntax

| Metadata | Value |
|---|---|
| Date | 2026-07-10 |
| Status | accepted |
| Decision Driver | @antisatori |
| Implementation PR | TBD |

## Context

The grammar IR has `Expr::ExpectSkip(Pred[T], K, T, K)` — a compiled construct that
consumes optional skip tokens (e.g. soft newlines) before expecting a required token.
Unlike `@skip(Tok)` on `PrattBinary` (which skips between binary operator checks),
ExpectSkip is a general-purpose node that can appear anywhere in a production body.

There was no EBNF syntax to produce it, forcing grammars to hand-write `@native`
functions calling `expect_after_skip` directly.

## Decision

Add `SkipTok~>ExpectedTok` EBNF syntax to `loomgen`.

The construct lowers to `Expr::ExpectSkip`. The left operand is the skip token
(consumed with `Pred::IsToken`), the right operand is the expected token. Both
must be `#loom.token` variants.

The operator parses as a binary postfix in `parse_postfix`, consuming two atoms:

```
Newline~>Ident
  → Expr::ExpectSkip(Pred::IsToken(Newline), SyntaxKind::NewlineToken,
                     Token::Ident, SyntaxKind::IdentToken)


**Constraint:** The right operand of `~>` cannot carry additional postfix
operators (`*`, `+`, `?`, `~`, `!`). The postfix grammar (`parse_postfix`)
allows at most one postfix operator per atom; `~>` IS that postfix operator,
so `A~>B*` parses as `Seq([ExpectSkip("A","B"), Star(...)])` — the `*`
attaches to the **next** atom, not to `B`. This is a natural consequence of
the one-postfix-per-atom rule, enforced by `parse_postfix`'s single-peek
dispatch.

## Alternatives

- **`@skip`-like annotation syntax.** Rejected — `@skip` only applies to
  `PrattBinary` productions and is not a general-purpose body expression.
- **`@native` with hand-written `expect_after_skip` call.** Rejected — duplicated
  boilerplate, no compile-time validation of token names.
- **Implicit skip on every `Expect`.** Rejected — would change existing parser
  behavior for all grammars; `~>` makes the skip explicit and opt-in.

## Consequences

- Grammars can express "consume optional separators before required token" declaratively.
- `RuleAst` gained `ExpectSkip(String, String)` — parse-time validation extracts
  string names from `Sym` atoms.
- All analysis functions (`nullable`, `first_set`, `leading_refs`,
  `has_fragment_refs`) handle the new variant.
- Both annotation-based (`#loom.rule`) and file-based (`.loomgrammar`) inputs
  support the syntax.
