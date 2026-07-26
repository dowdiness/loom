# ADR: ParserContext lex-mode API lifecycle

**Date:** 2026-07-26
**Status:** Accepted
**Implementation plan:** [Remove the public ParserContext lex-mode API](../archive/completed-phases/2026-07-26-remove-parser-context-lex-mode-api.md)
**Follow-up plan:** [Remove private ParserContext lex-mode state](../plans/2026-07-26-remove-private-parser-context-lex-mode-state.md)

## Context

`ParserContext::lex_mode()` and `ParserContext::set_lex_mode(Int)` were added as
public parser-author methods during the ParserContext field-boundary work. The
corrected contract is narrower than their names suggest: they read and write a
parser-local opaque `Int`, defaulting to `0`, and checkpoints save and restore
it. The value is not consumed by `TokenBuffer`, `ModeLexer`, already-produced
tokens, mode re-lexing, or goal tokenization.

Loom now has three independent lexical-state mechanisms:

1. `ModeLexer` selects native lexical modes while lexing and
   `ModeRelexFactory`/`ModeRelexState` retain per-`TokenBuffer` snapshots for
   incremental re-lexing.
2. `GoalTokenSource` receives an explicit goal for a particular token query;
   its cache and spans are managed separately from parser-local state.
3. `ParserContext::lex_mode` is checkpointed parser-local scratch state. It
   does not configure either lexical mechanism.

The checked ModeLexer recipe from Plan 002 is the appropriate path for a mode
choice that is lexically decidable: carry the mode through `ModeLexer`, erase it
with `erase_mode_lexer`, and pass the resulting factory through
`Grammar::new(mode_relex=...)`.

## Consumer evidence

The audit was run on 2026-07-26. The local search was:

```text
rg -n 'lex_mode|set_lex_mode' --glob '*.mbt' --glob '*.mbti' --glob '*.md' .
```

Every local hit falls into these classes:

| Class | Evidence | Meaning |
| --- | --- | --- |
| Public definition/interface | `loom/core/parser_context_access.mbt:299-316`; `loom/core/pkg.generated.mbti:315,334` | The getter/setter and their generated signatures. |
| Private storage/checkpoint plumbing | `loom/core/parser_context_access.mbt:28,62`; `loom/core/parser.mbt:143,166`; `loom/core/parser_events.mbt:187,208` | Initialization, private fields, and checkpoint save/restore only. |
| Test-only caller | `loom/core/parser_context_wbtest.mbt:153-188`; `examples/markdown/continuation_wbtest.mbt:47,56` | Core behavior/checkpoint tests; Markdown reads the scalar before and after a continuation decision as a purity observation and never sets or interprets it. |
| Current documentation | `docs/architecture/goal-token-source.md:58,176,207,220,241`; `docs/architecture/lexer-guidelines.md:66`; `examples/html/README.mbt.md:181` | Documentation distinguishes the scalar from goal tokenization and ModeLexer, and warns that it does not control eager lexing. |
| Documentation/history | `docs/superpowers/specs/2026-07-20-markdown-continuation-decision-refactor-design.md`; `docs/superpowers/plans/2026-06-28-grammar-ir-emitter.md`; `docs/archive/completed-phases/2026-07-14-parser-context-lookahead-rename.md`; `docs/archive/completed-phases/2026-07-22-markdown-continuation-decision-refactor.md`; `docs/archive/completed-phases/2026-07-14-markdown-code-span-authoring-contract.md` | Design, plan, and archived text; none is a production consumer. |

The semantic queries were:

```text
NEW_MOON_MOD=0 moon ide find-references ParserContext::lex_mode
NEW_MOON_MOD=0 moon ide find-references ParserContext::set_lex_mode
```

They returned only the public definitions, the core white-box tests, and the
passive Markdown white-box getter use listed above. No production grammar or
parser caller was found.

First-party downstream audit, using the following revisions, was read-only:

| Repository | Revision | Result | Classification |
| --- | --- | --- | --- |
| Loom | `a684fdd4ffcb92ddcfb07a29a5db01133c141d8c` | The local definition, checkpoint plumbing, tests, and docs above; no production caller. | Definition/private state/test/docs; no consumer. |
| Canopy | `8e400bbb4cf482a564a8e4f7e620968f74341759` | No Canopy production `.mbt`/`.mbti` caller. Hits were advisory plan documentation and the embedded Loom checkout's own definitions/tests. Its `moon.mod` declares `dowdiness/loom@0.1.0`, but no code assumes the scalar controls tokenization. | Dependency declaration/docs and mirrored Loom test surface; no production consumer. |
| js_engine | `5540ffa7f0ada321dfdc05eaab564265030f8d3e` | No `set_lex_mode` or `lex_mode(` hit in `.mbt`, `.mbti`, or `.md`. | No consumer found. |

The public GitHub code searches used the exact limit of 100:

```text
gh search code 'set_lex_mode extension:mbt' --limit 100
gh search code 'lex_mode() extension:mbt' --limit 100
gh search code 'dowdiness/loom extension:mod' --limit 100
```

The first query returned 3 matching lines in 2 Loom files: the public setter
definition and a core test. The second returned 4 matching lines in 2 Loom
test files: core tests and the passive Markdown purity test. The third returned
33 matching lines in 19 files: Loom's own module/dependency declarations and
Canopy's `moon.mod`. These are indexed-source results, not proof of all public
usage; no external production caller appeared. The candidate source files were
cross-checked through GitHub's repository contents API.

The registry audit found no published `dowdiness/loom` module in the Mooncakes
modules listing or in the `dowdiness` profile. Mooncakes exposes module metadata
but no verified reverse-dependency listing; **registry provides no verified
reverse-dependency listing**. Therefore this ADR does not claim exhaustive zero
usage from registry evidence. `gh api repos/dowdiness/loom/releases` returned
`[]`, and `gh api repos/dowdiness/loom/tags` returned `[]`. The repository module
still declares version `0.1.0`; no release or tag boundary, nor a mandatory
public deprecation window, was identified by this audit.

## Options

### Retain

Keep the public getter/setter under the corrected opaque parser-local contract.
This avoids source churn, but preserves names that can be mistaken for lexer
control and keeps an accidental public surface alive.

### Deprecate, then remove

Mark the methods deprecated, document the migration, and remove them after a
compatibility window. This gives any unindexed consumer time to migrate, but
adds a temporary compatibility surface and requires a defined window and
replacement policy. The audit found no policy that mandates such a window.

### Clean removal at a breaking boundary

Remove the public methods at the next maintainer-approved breaking boundary,
while deciding separately whether private checkpoint state remains useful. This
is the smallest honest public surface, but it is still a breaking change and
must not be implemented without a source-backed implementation plan and
maintainer approval.

## Decision

**Accepted: clean removal of the public `ParserContext::lex_mode()` and
`ParserContext::set_lex_mode(Int)` methods at the next maintainer-approved
breaking boundary.**

The Loom maintainer approved this decision on 2026-07-26. Implementation remains
bounded by the repeat live consumer audit in the linked plan: any production or
external caller, tokenization-control assumption, or required compatibility
window stops the implementation and returns it to review.

## Rationale

The current contract is truthful but the names invite the wrong architecture.
The actual supported mechanisms already have explicit ownership and trigger
semantics: `ModeLexer` for persistent native lexical modes and GoalTokenSource
for explicit per-query lexical goals. Keeping a parser-local scalar public
solely for tests and an unproven future parser-local use does not justify the
lexical-control implication of the API names.

The evidence boundary matters. Local and first-party searches establish no
production consumer in the inspected revisions. GitHub code search is limited
to indexed public code, and Mooncakes provides no verified reverse-dependency
listing; neither is treated as exhaustive proof of zero external use. If a
consumer is discovered before implementation, this proposal must return to the
matrix rather than being applied unilaterally.

## Migration guidance

For persistent lexical modes and other lexically decidable mode changes, use the
[canonical checked ModeLexer recipe](../architecture/lexer-guidelines.md#mode-aware-opaque-string-contexts).
That guide owns the exact `ModeLexer` / `erase_mode_lexer` /
`Grammar::new(mode_relex=...)` wiring and the checked fixture links. For explicit
parser-directed goals, use the opt-in interfaces described by the
[GoalTokenSource architecture note](../architecture/goal-token-source.md), not
`lex_mode` as an implicit bridge. The parser-local scalar has no replacement
as a tokenization control mechanism. Its current test-only use is observation
of parser-state purity; a later implementation plan must migrate or remove
that instrumentation deliberately and owns any `.mbti`, changelog, and release
updates.

## Consequences

The linked implementation plan owns public API removal, core and downstream
test changes, generated-interface verification, changelog communication, and
any compatibility decision required by a new consumer discovery. The plan must
be completed before this decision is considered landed in code.

The private `lex_mode` fields and checkpoint save/restore wiring are not removed
by this decision. They may remain useful as parser-internal state or may be
reconsidered independently once concrete evidence exists. The ModeLexer,
goal-token, Grammar IR, and TokenBuffer APIs are unchanged.

## Follow-up decision: remove private state

On 2026-07-26, the Loom maintainer approved the follow-up after the
post-public-removal local audit. The audit found no production reader or writer
of the retained private scalar: only initialization, `Checkpoint` save/restore
plumbing, and two white-box tests that manufacture reads and writes for that
same plumbing remain. The accepted deletion boundary is therefore the private
`ParserContext.lex_mode` and `Checkpoint.lex_mode` fields, both initializers,
the checkpoint copies, the two self-referential tests, and the stale
lex-mode-restoration comments.

This follow-up does not alter `ModeLexer`, `ModeRelexFactory`,
`GoalTokenSource`, `TokenBuffer`, the public `checkpoint`, `restore`, or
`lookahead` methods, or any public interface. The original public-removal
decision, evidence, migration guidance, and historical statement that private
state was retained remain valid for their respective decisions and revisions.

## Revisit/approval gate

Before any source edit, repeat the consumer audit against live code, re-check
the public contract and checkpoint behavior, and stop if any production or
external caller is found, if a caller assumes tokenization control, or if
compatibility policy requires a path not covered by this matrix. Acceptance of
this decision does not waive that implementation gate.
