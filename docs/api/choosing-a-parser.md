# Choosing a Parser

loom provides two parsers. Use this guide to pick the right one.

## Quick decision

**Can you provide an `Edit { start, old_len, new_len }` describing what changed?**

- **Yes** → `ImperativeParser` — you get node-level CST reuse
- **No** → `ReactiveParser` — set source string, memos handle the rest

## Comparison

| | `ImperativeParser` | `ReactiveParser` |
|---|---|---|
| Update method | `edit(Edit, String)` | `set_source(String)` |
| Node-level reuse | ✓ | ✗ |
| CST equality skip | ✓ | ✓ |
| Persistent interning | ✓ (global) | ✓ (global) |
| Reactive `@incr` composition | ✗ | ✓ |
| `diagnostics()` | ✓ | ✓ |
| `reset()` / `set_source()` | ✓ | ✓ |
| `get_source()` | ✓ | ✓ |

## By use case

| Use case | Parser | Reason |
|---|---|---|
| Text editor (keystroke-level edits) | `ImperativeParser` | CRDT/edit ops → `Edit` → node reuse |
| Language server | `ReactiveParser` | Source string arrives, reactive graph updates |
| Build tool | `ReactiveParser` | Batch source changes, equality-based skip |
| Projectional editor import | `ReactiveParser` | One-shot text → AST bootstrap |
| Hybrid editor text input path | `ImperativeParser` + `reset()` | Edits → structural ops; reset on mode switch |

## Factory functions

```moonbit
// From @loom:
let p  = new_imperative_parser(initial_source, grammar)  // → ImperativeParser[Ast]
let db = new_reactive_parser(initial_source, grammar)    // → ReactiveParser[Ast]
```

See [api/reference.md](reference.md) for full API.
See [decisions/2026-03-02-two-parser-design.md](../decisions/2026-03-02-two-parser-design.md) for design rationale.
