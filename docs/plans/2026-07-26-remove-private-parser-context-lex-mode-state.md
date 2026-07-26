# Remove private ParserContext lex-mode state

**Status:** In Progress

## Context

Plan 006 removed the public `ParserContext::lex_mode()` and
`ParserContext::set_lex_mode(Int)` API at the accepted breaking boundary. Its
reviewed follow-up retained the private scalar pending a separate,
evidence-based decision. The post-public-removal audit at `d46e37f` finds no
production reader or writer: the field is only initialized, copied into and out
of `Checkpoint`, and accessed by two white-box tests that manufacture state to
test that plumbing. This plan removes that dead state without adding
replacement scratch state.

The accepted lifecycle ADR is
[ParserContext lex-mode API lifecycle](../decisions/2026-07-26-parser-context-lex-mode-lifecycle.md).
The completed public-removal plan is preserved in
[Plan 006](../archive/completed-phases/2026-07-26-remove-parser-context-lex-mode-api.md).

## Decision boundary

Remove `ParserContext.lex_mode`, `Checkpoint.lex_mode`, both constructor
initializers, checkpoint save/restore copies, the two private-only white-box
tests, and comments that claim lex-mode checkpoint/lookahead restoration.
Preserve the existing `ParserContext::checkpoint`, `restore`, and `lookahead`
methods and all other checkpoint state. Persistent lexical state remains owned
by `ModeLexer`/`ModeRelexFactory`; explicit parser-directed goals remain owned
by `GoalTokenSource`. Do not add a replacement field, helper, method, type,
loop, test-only scratch state, or lexical mechanism.

## Scope and validation

Source scope is limited to `loom/core/parser.mbt`,
`loom/core/parser_context_access.mbt`, `loom/core/parser_events.mbt`, and
`loom/core/parser_context_wbtest.mbt`. Documentation scope is this plan, the
lifecycle ADR, `docs/README.md`, and the existing `CHANGELOG.md` bullet. The
public interface `loom/core/pkg.generated.mbti` must remain byte-for-byte
unchanged. Do not change `parser_robustness_wbtest.mbt`, lexer/token-source
implementations, grammar/factories, package metadata, submodules, or Plan 006.

Before source edits, verify the planned base `d46e37f`, an empty drift diff,
the classified `lex_mode` audit, the package outline, and baselines of 333
core and 3476 workspace tests. Commit this active plan, ADR follow-up, and
index update before MoonBit source edits. Then run formatting, interface
no-drift, targeted/full checks, core/workspace tests (331 and 3474), docs
health, and whitespace checks in the reviewed order. Any production consumer,
semantic drift, public-interface change, changed non-lex-mode test, unexpected
test delta, failed validation twice, second dependency-download failure,
submodule/parent change, or required out-of-scope edit is a STOP condition.

## Completion and archival

On successful validation, record exact planning and implementation commit
hashes, mark this plan Complete, and move it to
`../archive/completed-phases/2026-07-26-remove-private-parser-context-lex-mode-state.md`.
Update the lifecycle ADR link and completion evidence, and update the index in
the same archival commit. Preserve the ADR's original evidence and decision;
it remains Accepted and is additively qualified by the follow-up.

Decision record:
[ParserContext lex-mode API lifecycle](../decisions/2026-07-26-parser-context-lex-mode-lifecycle.md)

Plan 006 history and the supported `ModeLexer`/`ModeRelexFactory` and
`GoalTokenSource` mechanisms are explicitly preserved.
