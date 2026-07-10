# ADR 2026-07-30: @error_node(Kind, Token) EBNF Syntax

**Status:** Accepted

## Context

The grammar IR (`loom/grammar/ir.mbt`) has `Expr::ErrorNodeUntil(K, Pred[T], String)` — a compiled construct that wraps consumed tokens in an error node until a sync token. There was no EBNF syntax to produce it, forcing grammars to hand-write catch-all `@native` functions that duplicate the recovery logic.

## Decision

Add `@error_node(Kind, Token)` and `@error_node(Kind, A | B)` EBNF syntax to `loomgen`.

- Single token → `Pred::IsToken`; multiple (`|`-separated) → `Pred::OneOf`.
- The `Kind` must match the `#loom.errornode` variant in the `#loom.term` enum (validated at lower-time via `LowerCtx::error_node_variant`).
- Sync tokens must be `#loom.token` variants (validated via `token_kinds.contains`).

In a `Choice`, `@error_node` in the final branch position is treated as a catch-all — it receives `Pred::Any` and replaces the implicit `Any → Fail` fallback. Without this, its empty FIRST set would cause `lower_choice` to reject the alternation.

## Alternatives considered

- **Hand-write `@native` for every recovery rule.** Rejected: duplicated boilerplate across grammars, no compile-time validation that the kind is an errornode or the tokens are valid.
- **`@skip`-like syntax (returns a Term with fixed kind).** Rejected: `@skip` is for skipping trivia as a side effect; `@error_node` needs to wrap an arbitrary consumed range in an ErrorNode node.

## Consequences

- Grammars can express error recovery declaratively with a single line.
- `LowerCtx` gained `error_node_variant : String?` to enforce the single-errornode-per-term-enum constraint.
- `RuleAst::is_catch_all` now covers `ErrorNodeUntil` alongside `Native`.
