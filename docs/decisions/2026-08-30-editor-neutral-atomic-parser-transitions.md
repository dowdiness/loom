# ADR: Editor-neutral atomic parser transitions

**Date:** 2026-08-30
**Status:** Accepted
**Issue:** [#928](https://github.com/dowdiness/loom/issues/928)
**Implementation plan:** N/A — the issue records the behavioral matrix and the implementation is covered by package-local TDD.

## Context

`Parser` and `SyntaxParser` accepted either one incremental `Edit` or an
unvalidated whole-source replacement.

Editors, CRDT adapters, and language servers often produce one logical
transaction with several disjoint replacements. Replaying those replacements
through the single-edit parser would publish intermediate snapshots and expose
partially applied transitions.

Loom already depends on `dowdiness/text-change`, whose opaque `ChangeSet`
represents ordered, non-overlapping replacements in original-source UTF-16
coordinates. A separate Loom batch-edit model would duplicate that contract.

Full parsing also updated hidden token-buffer and parser state before completion.
`Runtime::batch` can coalesce reactive publication, but it cannot roll back such
imperative mutation after an internal `Failure`.

## Decision

Add `apply_changes(changes, new_source)` to `Parser` and `SyntaxParser`.
`new_source` is authoritative semantic input.

The parser applies `changes` to its currently accepted source before mutation
and requires the result to equal `new_source`. A mismatch raises
`ParserUpdateError::ChangeSetMismatch` and leaves the accepted state unchanged.

A validated transition uses a transactional full parse. Lexing and parsing
operate on candidate state.

After a successful parse, the parser commits its source, snapshot, token buffer,
diagnostics, and cache. It then publishes the final snapshot once. An unchanged
authoritative source is accepted without parsing or publication.

Malformed language input remains a successful recovered syntax tree plus
structured diagnostics. `Failure` remains the channel for internal parser or
lexer defects.

The public operation fixes the transition semantics while leaving the parsing
strategy private. Native multi-range reuse, reparse forests, or replayable token
sources may replace the full parse only after correctness parity and
deployment-target benchmarks justify them.

## Consequences

- Callers can submit one editor-neutral atomic transition without exposing
  intermediate parser states.
- Loom reuses `ChangeSet`; it does not expose arrays of `Edit` or `TextDelta` as
  another public batch format.
- Mismatched evidence and internal failures preserve the previous accepted
  source, snapshot, and incremental cache.
- Successful updates invalidate full-parse reuse metadata and publish one
  coherent reactive snapshot.
- Full parse is the correctness baseline. Any faster private strategy must match
  fresh CST, AST, and diagnostics, preserve rollback, and outperform this
  baseline on JavaScript and wasm-gc.
