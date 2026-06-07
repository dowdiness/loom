# Choosing a Parser

loom exposes two reactive parser handles for application code:
**`Parser[Ast]`** when you want an AST view, and **`SyntaxParser`** when you only
need source, CST, diagnostics, and reuse metadata. Both handle edit-driven
updates (typing, CRDT ops) and whole-source resets through a single reactive
handle.

## Quick decision

Use `Parser[Ast]` when your grammar has an AST fold and `Ast : Eq`. If your
AST is not naturally `Eq`, or a consumer only needs reactive CST/diagnostics,
use `SyntaxParser` via `new_syntax_parser`.

If you have an `Edit { start, old_len, new_len }`, call
`apply_edit(edit, new_source)`; otherwise call `set_source(new_source)`. Both
reactive handles update their input/derived graph atomically.

## What `Parser[Ast]` gives you

| Capability | How |
|---|---|
| Edit-driven update | `parser.apply_edit(edit, new_source)` |
| Whole-source reset | `parser.set_source(new_source)` |
| Validated CST subtree reuse | via the underlying `ImperativeParser` engine |
| Reactive composition | `parser.runtime()`, `parser.snapshot()`, `parser.source()`, `parser.syntax_tree()`, `parser.ast()`, `parser.diagnostics()` — all `@incr.Derived` views |
| Shared runtime | downstream derived cells (projection, typecheck, eval) join `parser.runtime()` directly — no second parse |
| Diagnostics | `parser.diagnostics().read_or_abort()` — `DiagnosticSet`; format only at presentation boundaries |
| Recovery | malformed input still publishes a recovered `SyntaxNode` plus structured diagnostics |

`Parser[Ast]` updates one parse snapshot input under `Runtime::batch` so
consumers never observe a half-updated graph.

## What `SyntaxParser` gives you

| Capability | How |
|---|---|
| Edit-driven update | `parser.apply_edit(edit, new_source)` |
| Whole-source reset | `parser.set_source(new_source)` |
| Validated CST subtree reuse | via the underlying `ImperativeParser[Unit]` engine |
| Reactive composition | `parser.runtime()`, `parser.snapshot()`, `parser.source()`, `parser.syntax_tree()`, `parser.diagnostics()` — all `@incr.Derived` views |
| Diagnostics | `parser.diagnostics().read_or_abort()` — `DiagnosticSet`; format only at presentation boundaries |
| No AST requirement | `SyntaxGrammar` has no `fold_node`; `SyntaxParser` has no `ast()` view and no `Ast : Eq` bound |

`SyntaxParser` updates one syntax snapshot input under `Runtime::batch`, with
source, syntax tree, diagnostics, and reuse count kept coherent.

The reuse contract is structural: incremental output must match a full reparse,
and unchanged CST subtrees may be reused when validation succeeds. It does not
promise stable parser-owned token or subtree identity across arbitrary edits.

## Factories

```moonbit
// From @loom:
let p = new_parser(initial_source, grammar)          // → Parser[Ast]
let s = new_syntax_parser(initial_source, syntax_grammar) // → SyntaxParser

// Or attach to an existing runtime:
let p = new_parser(initial_source, grammar, runtime?)
let s = new_syntax_parser(initial_source, syntax_grammar, runtime?)
```

`new_parser` requires `T : IsTrivia + Eq` and `Ast : Eq` because the underlying
derived graph does structural-equality backdating at the snapshot and
AST-view boundaries.

`new_syntax_parser` requires `T : IsTrivia + Eq` but has no `Ast` parameter. Use
`SyntaxGrammar::new(...)` when you do not have an AST fold, or
`grammar.to_syntax_grammar()` when you already have a `Grammar[T, K, Ast]` and
want the CST/diagnostic surface without requiring `Ast : Eq`.

If official lexer tokens carry non-`Eq` payloads, adapt them at the Loom
boundary with a lightweight `Eq` wrapper that preserves the stable kind/class
needed by the grammar. CST spans carry source text, so downstream projection
code can rebuild richer payloads when needed; the MoonBit skeleton's `MoonToken`
follows this pattern.

## When to use `ImperativeParser` directly

`Parser[Ast]` and `SyntaxParser` both wrap `ImperativeParser` and are the right
choice for almost everything reactive. Reach for `ImperativeParser` directly
only if you need the non-reactive engine without the input/derived layer — for
example, a one-shot parse in a batch tool, or a subsystem that owns its own
runtime lifecycle and can't accept a caller-supplied one.

See [`api/reference.md`](reference.md) for the full `Parser` API and
[`decisions/2026-04-17-unified-parser-proposal.md`](../decisions/2026-04-17-unified-parser-proposal.md)
for the consolidation rationale.
