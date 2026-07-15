# ADR: Widen Block Reparse Only After Explicit Decline

**Date:** 2026-07-15
**Status:** Accepted
**Implementation plan:** [2026-07-15-block-reparse-ancestor-widening.md](../archive/completed-phases/2026-07-15-block-reparse-ancestor-widening.md)

## Context

Block reparsing is an optional incremental fast path. Before this change, Loom
selected only the innermost strict reparseable ancestor. Markdown list-indentation
edits can change which list owns a following sibling, so that local candidate
may no longer be semantically valid even though its tokens are balanced. Falling
through directly to the normal incremental path preserves correctness but leaves
an eligible enclosing block unreused.

A language needs more than the old syntax node to make that decision: it must
inspect the candidate's new source and its already-produced local token stream.
Mode-aware grammars also require mutable lexer-mode snapshots to stay owned by a
single `TokenBuffer` session; a grammar-level factory must not retain that state.

## Decision

`BlockReparseSpec.get_reparser` receives the old candidate node, candidate-local
new source, and candidate-local tokens. Core enumerates strict reparseable
ancestors from innermost to outermost. A selector result of `None` explicitly
declines that candidate and permits the next parent. Once a selector returns a
parser, every subsequent parse, splice, or diagnostic failure returns `None`; it
does not widen further.

`ModeRelexFactory` is the immutable grammar-level contract. It creates a fresh
`ModeRelexState` for each `TokenBuffer` session. Candidate block reparsing uses
the detached factory tokenizer, while the grammar lexer remains the source of
final-buffer tokens and diagnostics.

## Rationale

The selector owns language semantics, so only it can distinguish an unsafe local
candidate from a reparsable parent. Treating parse failure as a decline could
silently reinterpret malformed input at a different boundary. Passing facts Loom
already computes avoids a language-specific Markdown parser or duplicated list
grammar.

Separating the reusable factory from session state prevents candidate lexing,
full parsing, and separate parser instances from mutating one another's mode
snapshots. Retaining the grammar lexer for final buffer construction preserves
any grammar-added diagnostics.

## Consequences

All `BlockReparseSpec` initializers migrate to the three-argument selector.
JSON and Lambda ignore the added candidate facts; Markdown declines only its
ownership-changing list candidate and otherwise retains its existing parser.

Grammar authors supplying mode-aware relexing provide a factory, not a mutable
session. A full tokenization may intentionally initialize both the grammar lexer
and the buffer's owned mode session when the grammar decorates diagnostics.
