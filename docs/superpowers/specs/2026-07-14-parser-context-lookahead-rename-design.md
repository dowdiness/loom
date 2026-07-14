# ParserContext Lookahead Rename Design

**Date:** 2026-07-14
**Issue:** [#716](https://github.com/dowdiness/loom/issues/716)
**Status:** Approved for implementation

## Goal

Replace the misleading public `ParserContext::speculative` name with
`ParserContext::lookahead`. The API remains a pure lookahead helper: it always
restores its checkpointed parser execution state after its callback returns,
then returns the callback value.

## Scope

The cutover updates the core method, all pure-lookahead callers, core tests,
the generated public interface, API comments, architecture documentation, and
the existing rollback-boundary ADR.

The cutover does not add aliases, deprecated shims, conditional-backtracking
helpers, grammar IR variants, grammar annotations, or checkpoint fields.

## Contract

`lookahead` checkpoints before running its callback and restores after it,
regardless of the callback result. The rollback boundary remains parser-owned
execution state captured by `checkpoint`: token position, emitted events,
parser-added diagnostics, open-node state, reuse cursor and count, and lex
mode.

It does not roll back arbitrary state captured by the callback, I/O,
in-place mutation of an existing diagnostic, or parser configuration excluded
from `checkpoint`.

Conditional parses that commit a successful branch remain explicit
`checkpoint`/`restore` control flow. They are distinct from `lookahead`.

## Alternatives Considered

1. **Clean rename — selected.** One public name matches unconditional rollback
   semantics and removes the ambiguity that caused conditional-backtracking
   proposals to target this helper.
2. **Retain `speculative` as an alias.** Rejected: it preserves the misleading
   surface and permits new callers to choose the ambiguous name.
3. **Add a conditional-backtracking helper in this change.** Rejected: #560 has
   no accepted policy-independent consumer or consumer-derived contract.

## Validation

Focused tests must prove that `lookahead` returns the callback value while
restoring each checkpointed parser-state category. Markdown pure-lookahead
callers must continue to pass. A repository-wide reference check must prove
that no `ParserContext::speculative` API declaration, caller, or API document
remains.
