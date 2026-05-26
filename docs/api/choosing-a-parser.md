# Choosing a Parser

loom exposes one parser for application code: **`Parser`**. It handles
both edit-driven updates (typing, CRDT ops) and whole-source resets
through a single reactive handle.

## Quick decision

Use `Parser`. If you have an `Edit { start, old_len, new_len }`, call
`apply_edit(edit, new_source)`; otherwise call `set_source(new_source)`.
Both update the same input/derived graph atomically.

## What `Parser` gives you

| Capability | How |
|---|---|
| Edit-driven update | `parser.apply_edit(edit, new_source)` |
| Whole-source reset | `parser.set_source(new_source)` |
| Validated CST subtree reuse | via the underlying `ImperativeParser` engine |
| Reactive composition | `parser.runtime()`, `parser.snapshot()`, `parser.source()`, `parser.syntax_tree()`, `parser.ast()`, `parser.diagnostics()` — all `@incr.Derived` views |
| Shared runtime | downstream derived cells (projection, typecheck, eval) join `parser.runtime()` directly — no second parse |
| Diagnostics | `parser.diagnostics().read_or_abort()` — `DiagnosticSet`; format only at presentation boundaries |
| Recovery | malformed input still publishes a recovered `SyntaxNode` plus structured diagnostics |

`Parser` updates one parse snapshot input under `Runtime::batch` so consumers
never observe a half-updated graph.

The reuse contract is structural: incremental output must match a full reparse,
and unchanged CST subtrees may be reused when validation succeeds. It does not
promise stable parser-owned token or subtree identity across arbitrary edits.

## Factory

```moonbit
// From @loom:
let p = new_parser(initial_source, grammar)          // → Parser[Ast]
// Or attach to an existing runtime:
let p = new_parser(initial_source, grammar, runtime?)
```

The factory requires `T : IsTrivia + Eq` and `Ast : Eq` because the underlying
memo graph does structural-equality backdating at the snapshot and derived-view
boundaries.

## When to use `ImperativeParser` directly

`Parser` wraps `ImperativeParser` and is the right choice for almost
everything. Reach for `ImperativeParser` directly only if you need the
non-reactive engine without the input/derived layer — for example, a
one-shot parse in a batch tool, or a subsystem that owns its own
runtime lifecycle and can't accept a caller-supplied one.

See [`api/reference.md`](reference.md) for the full `Parser` API and
[`decisions/2026-04-17-unified-parser-proposal.md`](../decisions/2026-04-17-unified-parser-proposal.md)
for the consolidation rationale.
