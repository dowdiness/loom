# ADR: Keep `new_reactive_parser`'s `T : Eq` Bound

**Date:** 2026-03-09
**Status:** Accepted

## Context

The position-independent token work reintroduced a token-stage memo in the
reactive parser factory:

```
Signal[String] → Memo[TokenStage[T]] → Memo[CstStage] → Memo[Ast]
```

`Memo` backdating depends on structural equality of the memo value. That makes
token equality part of the reactive parser's semantics rather than an internal
optimization detail.

At the same time, the helper constructor
`ReactiveParser::from_parts(source_text, source_memo, cst_memo, term_memo)` had
become public. That constructor must preserve a graph invariant: all cells must
belong to one coherent runtime graph and the dependency chain must be
`source_text → source_memo → cst_memo → term_memo`.

Only the memo values that are eagerly forced at construction need `Eq` here.
That means `source_memo` requires `Eq`, while `term_memo`'s `Ast` type does not.

## Decision

- Keep `new_reactive_parser` as:

```moonbit
pub fn[T : @seam.IsTrivia + Eq, K : @seam.ToRawKind, Ast : Eq] new_reactive_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @pipeline.ReactiveParser[Ast]
```

- Keep `ReactiveParser::from_parts` public, but change it to accept the memo
  immediately downstream of `source_text` and validate runtime/dependency wiring
  without forcing AST construction at parser creation time.

## Rationale

### 1. Equality at a memo boundary is a semantic requirement

If the reactive pipeline exposes token-stage memoization, then token equality is
part of the type-level contract. Hiding that requirement would make the API claim
less than the implementation actually needs.

### 2. Invalid states should be unrepresentable

A public `from_parts` constructor is acceptable only if it enforces the graph
shape it requires. That means the constructor must be told which memo is the
first stage downstream of `source_text`; otherwise a disconnected `cst_memo`
cannot be distinguished from a legitimate staged pipeline. Mismatched runtimes
or disconnected memos should fail at construction, not later during
`set_source()` or `get()`.

AST construction remains lazy. `from_parts` eagerly validates only the
source-driven portion of the graph. The `term_memo → cst_memo` edge is checked
on the first `term()` call so grammars can still construct parsers for invalid
text and inspect `cst()` or `diagnostics()` without invoking `to_ast` or
`on_lex_error`.

### 3. Source compatibility is secondary to semantic honesty here

This project is still evolving rapidly. A source-compatible API that obscures core
invariants is worse than a documented break that states them plainly.

## Consequences

- Existing callers of `new_reactive_parser` must ensure their token type derives or
  implements `Eq`.
- `ReactiveParser::from_parts` remains available as an expert constructor, but it
  now eagerly rejects incoherent source-stage graphs while preserving lazy AST
  construction.
- API docs must describe the `Eq` requirement as intentional, not incidental.
