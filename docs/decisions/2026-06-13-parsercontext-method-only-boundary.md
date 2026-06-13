# ADR: ParserContext Grammar-Author Method-Only Boundary

**Date:** 2026-06-13
**Status:** Accepted
**Issue:** [#251](https://github.com/dowdiness/loom/issues/251)
**Implementation plan:** [docs/archive/completed-phases/2026-06-12-parsercontext-field-boundary-design.md](../archive/completed-phases/2026-06-12-parsercontext-field-boundary-design.md)
**Related:** [ADR 2026-06-07 parser context grammar-author helpers](2026-06-07-parser-context-grammar-author-helpers.md)

## Context

`ParserContext[T, K]` is the object grammar authors receive while implementing a
Loom grammar. The intended contract is that grammars build parse events,
inspect tokens, recover from errors, and query parser state through named
methods.

Before issue #251, `ParserContext` was already read-only outside `loom/src/core/`,
but its parser-state fields were still visible in generated interfaces. That made
internal cursor, diagnostic, reuse, and event-buffer state look like stable API.
The helper methods accepted in ADR 2026-06-07 reduced common direct-field needs,
but did not enforce the boundary.

## Decision

Make the grammar-author surface of `ParserContext` exactly its public methods.
All parser-state fields are private implementation detail and must not appear in
the generated public interface.

Keep `ParserContext` as a public struct so existing type references and facade
re-exports remain valid. Do not add broad escape-hatch accessors. If a future
grammar has a concrete need to observe parser state, add a named method with
explicit semantics instead of exposing raw fields.

## Rationale

Named methods let Loom document invariants around token cursor movement,
trivia-skipping, event emission, diagnostics, reuse validation, and recovery.
Raw field reads bypass those invariants and make future parser implementation
changes harder.

The compatibility cost is low: in-repo production code did not read the fields
cross-package, and the lone cross-package test read asserted a core invariant. It
belongs in the core white-box tests where private field access is still allowed.

## Consequences

`ParserContext` remains a stable public type, but the stable grammar-author API
is method-only. The generated interface collapses the old field block to private
fields, and downstream grammars must use existing parser-context methods.

Future parser-context API additions should follow the helper bar from ADR
2026-06-07: require concrete grammar-author use, expose a small named method,
and document the method's semantics at the parser boundary.
