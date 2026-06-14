# ADR: Defer BlockReparseContext Pending Markdown Evidence

**Date:** 2026-06-14
**Status:** Accepted
**Issue:** [#315](https://github.com/dowdiness/loom/issues/315)
**Related:** [#313](https://github.com/dowdiness/loom/pull/313), [#316](https://github.com/dowdiness/loom/pull/316)
**Implementation plan:** N/A — investigation-only design note; no API migration yet.

## Context

Block reparsing is an optional fast path: a grammar marks isolated container
nodes as reparseable, Loom reparses one candidate block, then falls back to the
normal incremental path whenever the candidate cannot preserve full-parse
semantics.

PR #313 changed the reparser lookup from kind-only to syntax-node-aware so JSON
can preserve its absolute nesting-depth limit. That is enough for the current
JSON regression because the grammar can walk the node's parents and count the
ancestor kinds it cares about. Issue #315 asks whether Loom should expose a
richer context object before more grammars grow ad hoc context reconstruction.

The existing spec is a public struct used through record literals, so adding a
required callback field or changing callback arguments is source-visible API
churn. A context API should therefore need evidence beyond the one JSON use case
that the current node callback already covers.

The in-repo Markdown example is the expected proving ground for that evidence.
It already uses mode-aware lexing (`LineStart`, `Inline`, `CodeBlock(n)`) but
has no block-reparse spec. Markdown may expose real failures where isolated
reparse needs local token diagnostics, edit shape, or lexer-mode information to
preserve full-parse CST and diagnostic parity.

## Decision

Do not replace the current syntax-node callback yet. Treat the following shape
as the conservative successor if Markdown or another concrete grammar
demonstrates the need:

```moonbit
struct BlockReparseContext[T] {
  node : SyntaxNode
  edit : Edit
  old_block_range : Range
  new_block_range : Range
  block_text : String
  lex_result : LexResult[T]
}

enum BlockReparseDecision[T, K] {
  Reparse((ParserContext[T, K]) -> Unit)
  Decline(reason~ : String)
}

get_reparser : (BlockReparseContext[T]) -> BlockReparseDecision[T, K]
```

The context should contain facts Loom already computes while orchestrating the
fast path. It should not invent grammar semantics. In particular, do not expose
a generic container-depth field: JSON counts only object/array ancestors, while
another language might count scopes, indentation regions, or no ancestors at
all.

Generally useful context fields:

- `node`: the absolute syntax node, including kind, span, text, and parent
  traversal. This remains the primary escape hatch for language-specific
  context.
- `edit`: the triggering single edit, useful for grammars that can accept only
  some edit shapes or for debug explanations.
- `old_block_range` and `new_block_range`: absolute splice boundaries for range
  checks and observability.
- `block_text`: the new isolated text already extracted for lexing.
- `lex_result`: local tokens, starts, and token diagnostics from the isolated
  lex pass, without duplicating `LexResult` fields.
- `Decline(reason)`: a debug-only fallback explanation. Declines must not become
  parser diagnostics; they explain optimization-path selection.

Fields that should stay framework-internal until a specific grammar needs them:

- physical splice path through the CST, because it is an implementation detail
  of path-copy replacement rather than a stable grammar concept;
- old diagnostic partitions, because diagnostic merge policy belongs to Loom;
- full old/new source strings, because needing arbitrary surrounding text is a
  strong signal that isolated reparsing may not preserve full-parse semantics;
- lexer-mode snapshots, because `ModeRelexState` already owns mode-aware token
  convergence. Expose mode context only after the Markdown spike shows that
  `SyntaxNode` plus local lex results cannot preserve full-parse parity.

JSON-specific context stays in the JSON grammar:

- counting object/array ancestors to derive absolute container depth;
- choosing object vs array entry points;
- bracket/brace balance rules.

With the future context shape, JSON would still compute its depth from
`context.node`; no generic Loom field is needed.

## Rationale

The current callback already gives grammar authors the most important fact: the
absolute candidate node. That lets JSON preserve full-parse diagnostics without
stabilizing a larger public contract.

The proposed context fields are deliberately mechanical. They avoid a second
round of ad hoc slicing or token-diagnostic plumbing if another grammar needs
that data, but they do not encode language-specific notions such as block depth,
layout state, or scope kind. The proposed decision enum makes the fallback story
observable while preserving the core invariant: declining block reparse simply
falls through to the normal parser path.

Keeping the API unchanged now avoids forcing all record-literal spec users
through a migration for an unproven abstraction. If a later grammar needs the
context, migration from the current callback is straightforward because
`context.node` preserves the existing capability.

## Consequences

The #315 investigation records a design result rather than an API change. It is
not a claim that Markdown will never need richer context; it is a claim that no
enabled block-reparse grammar has demonstrated that need yet.

The next Markdown block-reparse work should start with CST+diagnostics parity
tests. If a fenced-code or paragraph-boundary case cannot be made safe with the
current `SyntaxNode` callback, prototype this context shape or justify a
narrower one.

Any prototype must validate syntax-tree and diagnostic parity against a fresh
full parse. Reuse-count assertions remain opt-in and should prove only that the
optimization path was selected, not correctness.
