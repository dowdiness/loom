# ADR: Reintroduce TokenStage Memo

**Date:** 2026-03-15
**Status:** Accepted
**Reverses:** [2026-02-27: Remove TokenStage Memo](2026-02-27-remove-tokenStage-memo.md)

## Context

The `TokenStage` memo was removed in February 2026 because `TokenInfo`
stored absolute byte offsets (`start`, `end`). Any edit shifted all
subsequent tokens, making the token array always differ — the memo
was vacuous (never backdated).

Since then, `TokenInfo` was changed to store `(token, len)` — position-
independent. Token equality now captures lexeme identity without
positions. This enables meaningful token-sequence comparison.

## Decision

Reintroduce a `TokenStage` memo boundary in the `new_reactive_parser`
three-memo pipeline:

```
Signal[String] → Memo[TokenStage[T]] → Memo[CstStage] → Memo[Ast]
```

`TokenStage` stores the full lex output (`tokens`, `starts`, `source`)
but its `Eq` implementation uses **trivia-insensitive comparison**:
only non-trivia tokens (determined by `IsTrivia` trait) and error state
participate in equality. Trivia tokens (whitespace, newlines), positions
(`starts`), and source text are all excluded.

## Consequences

### When the cutoff fires

The cutoff fires for edits that change only trivia tokens — the most
common case being whitespace and newline changes:

- Adding/removing/resizing spaces between tokens
- Adding/removing blank lines between definitions
- Any formatting-only edit

In these cases the token memo backdates (non-trivia tokens unchanged),
and the CST and AST memos skip recomputation entirely.

### When the cutoff does NOT fire

Edits that change any non-trivia token (kind or content) cause the
token memo to produce a new TokenStage. The full pipeline runs:
token → CST → AST. This is the common case for content edits like
typing new code, renaming variables, or changing literals.

However, CstStage and term_memo can still backdate independently via
their own Eq checks.

### Stale positions in backdated TokenStage

When the token memo backdates, the CST memo receives the old `starts`
and `source` from the previous TokenStage value. These positions may
be stale (shifted from a whitespace edit). This is safe because:

- `CstNode` is position-independent (stores `text_len`, not offsets)
- `SyntaxNode` computes positions ephemerally from `CstNode`
- Diagnostics are formatted during CST memo computation with the
  positions from that computation's TokenStage value
- When the token memo backdates, the CST memo does NOT recompute,
  so stale positions are never used for formatting

### Cost

One additional `Memo` per `ReactiveParser` instance. The lex function
runs on every source change regardless (it must, to determine whether
tokens changed). The overhead is the trivia-filtered equality check,
which is O(non-trivia token count) — typically cheaper than a full
parse.

### Trivia-insensitive equality design

`TokenStage::Eq` requires `T : Eq + IsTrivia`. It walks both token
arrays with two pointers, skipping any token where `is_trivia()` is
true. Only non-trivia tokens are compared for equality. This means
two TokenStages that differ only in whitespace/newline tokens are
considered equal.

This is correct because non-trivia tokens fully determine the CST
structure. Trivia tokens affect only spacing (positions), which are
carried data in the `starts` array but do not affect CstNode identity.
