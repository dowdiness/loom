# ADR 2026-06-13: Lambda Example Uses MoonBit-Style Function Syntax

**Status:** Accepted

## Context

The lambda example historically accepted classical lambda notation (`\x.x` / `λx.x`) and function-binding sugar (`let f(x) = ...`). Issue #305 changes the example language to better match MoonBit authoring conventions while preserving the example's role as a compact parser, CST, and projection testbed.

The new syntax needs to keep value declarations familiar (`let name = expr`), use explicit function declarations (`fn name(params) { body }`), and support anonymous functions without Unicode or backslash tokens (`(params) => expr` / `(params) => { body }`).

## Decision

The lambda example grammar accepts:

- `let name = expr` for value declarations
- `fn name(params) { body }` for named function declarations
- `(params) => expr` and `(params) => { body }` for anonymous functions

The old lambda abstraction syntax (`\x.x` / `λx.x`) and old function-binding sugar (`let f(x) = ...`) are rejected. Legacy lambda tokens remain lexed so diagnostics and negative tests can report rejected old syntax instead of failing tokenization.

The existing `LetDef` CST/AST conversion shape is retained for both `let` and `fn` definitions to avoid unnecessary downstream churn. Multi-parameter arrows and functions continue to lower to nested `Lam` terms.

## Consequences

- Pretty/source output now emits parseable MoonBit-style syntax.
- Public token/syntax enums gain `Fn`/`FatArrow` and `FnKeyword`/`FatArrowToken` variants.
- `LambdaExprView` exposes `params()` so callers can inspect multi-parameter arrows without rewalking raw CST tokens.
- Tests, benchmarks, and example fixtures now use the new syntax except for intentional rejection cases.
