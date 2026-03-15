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
but its `Eq` implementation compares only `tokens` + error state.
Positions (`starts`) and source text are excluded from comparison.

## Consequences

**Early cutoff:** When an edit changes token positions but not token
kinds or lengths, the token memo backdates. The CST memo does not
recompute, and the AST memo does not recompute.

**When this helps:** Edits that insert/delete equal-length text at the
same position (e.g., replacing `x` with `y` in a way that preserves
the token `Identifier` kind and length). In the current lambda calculus
grammar, this is uncommon — most edits change at least one token's
content. The primary benefit is architectural: the pipeline has a clean
lex/parse boundary that supports future trivia-insensitive equality
(Phase 4 of the position-independent tokens plan).

**When this doesn't help:** Edits that change any token kind or length
(the common case). The token memo recomputes and produces a new
TokenStage, CstStage recomputes, and the full pipeline runs. However,
CstStage and term_memo can still backdate independently.

**Stale positions in backdated TokenStage:** When the token memo
backdates, the CST memo receives the old `starts` and `source` from
the previous TokenStage value. These positions may be stale (shifted).
This is safe because:
- `CstNode` is position-independent (stores `text_len`, not offsets)
- `SyntaxNode` computes positions ephemerally from `CstNode`
- Diagnostics are formatted during CST memo computation with the
  positions from that computation's TokenStage value

**Cost:** One additional `Memo` per `ReactiveParser` instance. The lex
function runs on every source change regardless (it must, to determine
whether tokens changed). The overhead is the memo equality check
(`Array[TokenInfo]` comparison), which is O(n) in token count.
