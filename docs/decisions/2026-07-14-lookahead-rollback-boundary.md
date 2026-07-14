# ADR: ParserContext Lookahead Rollback Boundary

**Date:** 2026-07-14
**Status:** Accepted
**Issue:** [#438](https://github.com/dowdiness/loom/issues/438)
**Implementation:** [PR #715](https://github.com/dowdiness/loom/pull/715) introduced the rollback helper; [PR #717](https://github.com/dowdiness/loom/pull/717) renamed it to `ParserContext::lookahead`.
**Related:** [ADR 2026-06-07 ParserContext grammar-author helpers](2026-06-07-parser-context-grammar-author-helpers.md), [ADR 2026-06-13 ParserContext method-only boundary](2026-06-13-parsercontext-method-only-boundary.md)
**Implementation plan:** [#716 terminology cutover](../archive/completed-phases/2026-07-14-parser-context-lookahead-rename.md)

## Context

Markdown had four pure lookahead computations with the same manual pattern:
capture a `ParserContext` checkpoint, consume and emit while inspecting later
tokens, restore, then return the computed result. `ParserContext::lookahead`
centralizes that unconditional rollback pattern while preserving conditional
`checkpoint`/`restore` pairs for parses that commit a successful branch.

The helper is public to grammar authors. Its closure can call `ParserContext`
methods and capture state outside the parser. A broad statement that every
mutation in a pure-lookahead body rolls back would therefore be false.

A checkpoint records parser position, event length, diagnostic count, open-node
count and stack, reuse cursor and count, and lex mode. Restore truncates
diagnostics to the recorded count. It removes diagnostics added after a
checkpoint but cannot undo in-place replacement of an existing diagnostic with
the same count. It also does not restore goal sources, goal-subsumption checks,
or reuse diagnostics.

## Decision

`ParserContext::lookahead` is a limited, unconditional rollback helper for
pure lookahead over the checkpointed `ParserContext` state. It is not a general
transaction mechanism.

Its public documentation must enumerate the checkpointed state and explicitly
exclude in-place diagnostic mutation and parser configuration not captured by a
checkpoint. “Pure” means that the computation confines its parser-owned effects
to that documented rollback set; it does not mean arbitrary closure side effects
are undone.

Any concrete caller that needs a pure-lookahead body to mutate state outside
this set must pause for a correctness and contract decision before implementation. That
decision must choose one of these contracts:

1. extend checkpoint/restore so the relevant **ParserContext-owned** state is
   transactional, with focused restoration tests; or
2. keep the operation grammar-local instead of broadening the public helper.

Broadening the public helper additionally requires repeated use in at least one
independent grammar, following ADR 2026-06-07.

A complete `ParserContext` snapshot would still not roll back state captured
outside the context, I/O, or other external effects. A callback facade alone is
also insufficient as an enforcement boundary if the callback can capture the
full `ParserContext`; a stronger guarantee requires a capability-boundary
redesign of the grammar-author API.

## Rationale

The four Markdown consumers establish a repeated, low-level parser-owned
pattern worth removing from grammar code. They do not establish demand for a
full transaction or a broader public combinator.

Keeping the contract narrow avoids snapshotting state that no current consumer
requires, avoids promising rollback of effects that no context snapshot can
control, and preserves direct conditional checkpoints where a successful parse
must commit. Exact documentation and state-class regression tests make the
boundary reviewable when new parser state or consumers arrive.

This follows ADR 2026-06-07: public `ParserContext` helpers require concrete
repeated use and should not stabilize broad abstractions preemptively.

## Consequences

`lookahead` callers must use it only for lookahead whose parser-owned effects
are inside the documented checkpoint set. Conditional parsing that commits on
success continues to use explicit checkpoint/restore.

Any new pure-lookahead mutation outside the current contract requires a decision
record before implementation. Broadening the public helper additionally
requires repeated use in at least one independent grammar.

The `lookahead` API does not provide rollback for external captured state.
Grammar authors must keep external side effects outside lookahead bodies.
