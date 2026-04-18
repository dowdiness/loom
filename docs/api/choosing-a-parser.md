# Choosing a Parser

loom exposes one parser for new work: **`Parser`**. It handles both
edit-driven updates (typing, CRDT ops) and whole-source resets through
a single reactive handle. `ReactiveParser` is deprecated; see
[Legacy](#legacy-reactiveparser) below.

## Quick decision

Use `Parser`. If you have an `Edit { start, old_len, new_len }`, call
`apply_edit(edit, new_source)`; otherwise call `set_source(new_source)`.
Both update the same signal/memo graph atomically.

## What `Parser` gives you

| Capability | How |
|---|---|
| Edit-driven update | `parser.apply_edit(edit, new_source)` |
| Whole-source reset | `parser.set_source(new_source)` |
| Node-level CST reuse | via the underlying `ImperativeParser` engine |
| Reactive composition | `parser.runtime()`, `parser.source()`, `parser.syntax_tree()`, `parser.ast()`, `parser.diagnostics()` — all `@incr.Memo` views |
| Shared runtime | downstream memos (projection, typecheck, eval) join `parser.runtime()` directly — no second parse |
| Diagnostics | `parser.diagnostics().get()` — `Array[String]`, defensively copied |
| Lex-error routing | language's `on_lex_error` runs on every lex failure; AST cell stays populated with a sentinel |

`Parser` batches all four signal updates under `Runtime::batch` so
consumers never observe a half-updated graph.

## Factory

```moonbit
// From @loom:
let p = new_parser(initial_source, grammar)          // → Parser[Ast]
// Or attach to an existing runtime:
let p = new_parser(initial_source, grammar, runtime?)
```

The factory requires `T : IsTrivia + Eq` and `Ast : Eq` — same bounds
`new_reactive_parser` needed, because the underlying memo graph still
does structural-equality backdating at the CST and AST boundaries.

## Legacy: `ReactiveParser`

`ReactiveParser` is deprecated and scheduled for removal one release
cycle after the Stage 5 cut (see
[`docs/plans/2026-04-17-unified-parser.md`](../plans/2026-04-17-unified-parser.md)).

- **Why it existed:** originally the reactive pipeline lived in its own
  type, separate from the edit-driven `ImperativeParser`. Editors needed
  both and had to own two parser handles plus a second `Runtime`.
- **Why it's gone:** `Parser` wraps `ImperativeParser` with the same
  signal/memo outputs `ReactiveParser` exposed, so there's no reason to
  keep two handles.
- **If you still need it:** existing call sites keep working; `#deprecated`
  emits compiler warnings pointing at `Parser`. New code should not use
  it.

See [`api/reference.md`](reference.md) for the full `Parser` API and
[`decisions/2026-04-17-unified-parser-proposal.md`](../decisions/2026-04-17-unified-parser-proposal.md)
for the consolidation rationale.
