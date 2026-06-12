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
| Shared runtime | downstream derived cells (projection, typecheck, eval) join `parser.runtime()` directly — no second runtime and no second parse |
| Diagnostics | `parser.diagnostics().read_or_abort()` — `DiagnosticSet`; format only at presentation boundaries |
| Recovery | malformed input still publishes a recovered `SyntaxNode` plus structured diagnostics |

`Parser[Ast]` updates one parse snapshot input under `Runtime::batch` so
consumers never observe a half-updated graph.

## Runtime ownership and attachments

Runtime ownership:

- `new_parser(source, grammar)` creates a fresh `@incr.Runtime` and stores it
  inside the parser. Treat that runtime as parser-owned.
- `new_parser(source, grammar, runtime=rt)` makes the parser join a
  caller-owned runtime graph. The caller keeps responsibility for that runtime's
  wider lifecycle.
- In both cases, downstream cells that read parser views should use
  `parser.runtime()`. Do not create a second runtime for those cells.
- Prefer a parser-specific high-level constructor, such as
  `CallersPipeline::from_parser(parser)`, when one exists.

Attachment lifecycle:

1. create `Scope::new(parser.runtime())`;
2. create `Derived` cells in that scope;
3. read parser views with `.get_or_abort()` inside derived closures;
4. keep a persistent `Watch` on each public terminal read surface;
5. prime the terminal watch before returning if GC can run before the first
   public read; and
6. implement `dispose()` by disposing the attachment scope, not the parser.

A handle to a `Derived` cell is not a GC root. `Runtime::gc()` is safe only when
that runtime is idle: not inside `Runtime::batch`, and not inside a derived
recompute. GC marks from persistent `Watch` / `Observer` roots and implicit
effects, then sweeps unrooted interior cells.

Priming rule:

- A `Watch` roots its terminal cell immediately.
- Upstream dependencies are recorded only after that cell computes.
- The priming read materializes edges such as
  `terminal -> parser.syntax_tree()` before an eager GC can sweep unobserved
  parser view cells.
- If an attachment intentionally skips constructor priming, document that the
  first public read is the priming read and must happen before an eager GC.

```mbt nocheck
pub(all) struct NameIndexAttachment {
  scope : @incr.Scope
  watch : @incr.Watch[NameIndex]
}

pub fn attach_name_index(
  parser : @loom.Parser[MyAst],
) -> NameIndexAttachment {
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let index : @incr.Derived[NameIndex] = scope.derived(
    fn() {
      let syntax = parser.syntax_tree().get_or_abort()
      build_name_index(syntax)
    },
    label="name_index",
  )
  let watch = scope.add_watch(index.watch())
  let _ = watch.read_or_abort() // prime before any eager Runtime::gc()
  { scope, watch }
}

pub fn NameIndexAttachment::get(self : NameIndexAttachment) -> NameIndex {
  self.watch.read_or_abort()
}

pub fn NameIndexAttachment::dispose(self : NameIndexAttachment) -> Unit {
  // Releases attachment cells; the parser remains owned by its caller.
  self.scope.dispose()
}
```

The same ownership rule applies to `SyntaxParser`: use `parser.runtime()` for
syntax-only downstream cells, and give the attachment its own scope/watch
lifecycle.

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
let p = new_parser(initial_source, grammar, runtime=rt)
let s = new_syntax_parser(initial_source, syntax_grammar, runtime=rt)
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
