# Remove the public ParserContext lex-mode API

**Status:** Complete
**Planned at:** commit `fd286e2`, 2026-07-26
**Decision record:** [ADR: ParserContext lex-mode API lifecycle](../../decisions/2026-07-26-parser-context-lex-mode-lifecycle.md)

## Context and boundary

Remove the misleading public `ParserContext::lex_mode()` and
`ParserContext::set_lex_mode(Int)` methods at the approved breaking boundary.
They expose only checkpointed parser-local `Int` scratch state; they do not
configure `TokenBuffer`, `ModeLexer`, already-produced tokens, incremental
mode re-lexing, or goal tokenization.

This plan is public-only. Retain the private `ParserContext.lex_mode` field,
the private `Checkpoint.lex_mode` field, both `lex_mode: 0` constructor
initializers, and checkpoint save/restore wiring. Do not add a replacement
getter, setter, or scratch-state abstraction. Real lexical modes use
`ModeLexer`/`ModeRelexFactory`; explicit parser-directed goals use
`GoalTokenSource` and its goal-query APIs.

## Consumer-audit gate

Before source edits, repeat the live local, first-party, and indexed-public
audit. Continue only when the semantic references are definitions, tests, and
private checkpoint plumbing; Loom, Canopy, and js_engine are inspectable; no
production or external caller is found; no caller assumes tokenization control;
and no compatibility policy requires a deprecation window. Record evidence
limits honestly: indexed GitHub search is not exhaustive and registry metadata
does not provide a verified reverse-dependency listing.

## Scope

Only these product paths may change:

- `loom/core/parser_context_access.mbt`: remove the two public methods only.
- `loom/core/parser_context_wbtest.mbt`: remove public-contract-only tests and
  retain checkpoint/lookahead coverage through direct package-private field
  access.
- `loom/core/pkg.generated.mbti`: regenerate; exactly two signatures disappear.
- `examples/markdown/continuation_wbtest.mbt`: remove passive observation of the
  public scalar while preserving range, node, and mark assertions.
- `docs/architecture/goal-token-source.md`: document ModeLexer and explicit
  goal queries as separate supported mechanisms; remove live public-scalar
  claims.
- `docs/architecture/lexer-guidelines.md`: identify ModeLexer as the persistent
  mode path and state that no parser-local setter exists.
- `examples/html/README.mbt.md`: direct persistent modes to ModeLexer.
- `docs/decisions/2026-07-26-parser-context-lex-mode-lifecycle.md`: accept the
  decision, link this active plan, and preserve the evidence and alternatives.
- `docs/archive/completed-phases/2026-07-26-remove-parser-context-lex-mode-api.md`:
  final archived implementation plan after validation.
- `docs/README.md`: keep ADR and plan navigation current.
- `CHANGELOG.md`: record the breaking removal and migration paths.

Do not change `loom/core/parser.mbt`, `loom/core/parser_events.mbt`, private
initializers or checkpoint wiring, other interfaces, manifests, release
metadata, historical docs, submodules, or the Canopy parent gitlink.

## Implementation and validation

1. Run the drift check, API discovery (`moon ide`), consumer audit, and
   targeted baselines. The Markdown module is `dowdiness/markdown` in this
   workspace.
2. Commit the accepted ADR, this active plan, and `docs/README.md` before any
   MoonBit source edit as:
   `docs(core): accept ParserContext lex-mode removal`.
3. Remove only the two public methods and migrate the two white-box test files
   without introducing a replacement API.
4. Update only the listed current documentation and `CHANGELOG.md`; leave
   historical records untouched.
5. Run `NEW_MOON_MOD=0 moon fmt` and `NEW_MOON_MOD=0 moon info -p dowdiness/loom/core`;
   review the generated interface and require exactly the two named signatures
   to disappear.
6. Run targeted core and Markdown checks/tests, then full `moon check` and
   `moon test`, `bash check-docs.sh`, and `git diff --check`. Record exact test
   totals. A single dependency-download failure may be retried once; a second
   network failure is an infrastructure stop.
7. Mark this plan Complete, add the two local commit hashes and validation
   totals, move it to `docs/archive/completed-phases/`, update the ADR link and
   `docs/README.md`, then run docs/link validation again.
8. Verify the final allowlist exactly, private-state and submodule diffs are
   empty, and commit the implementation as:
   `refactor(core)!: remove ParserContext lex-mode API`.

## Stop conditions

Stop without source edits or improvisation if a production or external caller
is found; a caller assumes the scalar controls tokenization; Loom, Canopy, or
js_engine cannot be inspected; public search is unavailable for an honest
evidence report; compatibility policy requires deprecation; live definitions,
checkpoint contract, or caller set differs; removal requires private-state or
other public-API changes; interface generation changes anything beyond the two
signatures; the Markdown test needs replacement state observation; unrelated
historical docs must be rewritten; any required validation fails twice for a
code reason; or the allowlist, submodule, parent gitlink, publication, or
release boundary would be exceeded.

## Completion

The accepted ADR and this plan were committed before source edits in
`43f5d87`. Implementation validation completed with 333 core tests, 339 Markdown
package tests, and 3476 full-workspace tests passing; `moon check`, formatting,
interface generation, `check-docs.sh`, and `git diff --check` also passed. The
implementation was committed in `9a0abfd`.
