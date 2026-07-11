# ADR 001: @error_node(Kind, Token) EBNF Syntax

| Metadata | Value |
|---|---|
| Date | 2026-07-30 |
| Status | accepted |
| Decision Driver | @antisatori |
| Implementation PR | #663 (squash) |

## Context

The grammar IR has `Expr::ErrorNodeUntil(K, Pred[T], String)` — a compiled construct
that wraps consumed tokens in an error node until a sync token. There was no EBNF
syntax to produce it, forcing grammars to hand-write catch-all `@native` functions.

## Decision

Add `@error_node(Kind, Token)` and `@error_node(Kind, A | B)` EBNF syntax to `loomgen`.

The construct lowers to `Expr::ErrorNodeUntil`. The `Kind` must be a `#loom.errornode`
variant. Sync tokens must be `#loom.token` variants.

`@error_node` in the final position of a `Choice` is treated as a catch-all
(`Pred::Any`), matching the required semantics: it fires only when no earlier
branch's FIRST set matches, consuming tokens until the sync point.

## Alternatives

- **Hand-write `@native` for every recovery rule.** Rejected — duplicated
  boilerplate, no validation of kind/token types.
- **`@skip`-like syntax.** Rejected — `@skip` returns a Term with a fixed kind;
  `@error_node` needs flexible error-node targeting.

## Consequences

- Grammars can express error recovery declaratively.
- Catch-all treatment in `Choice` extends `RuleAst::is_catch_all` to include
  `ErrorNodeUntil`.
- Single `#loom.errornode` variant per term enum is enforced.
