# ADR: Editor-neutral atomic parser transitions

**Date:** 2026-08-30
**Status:** Accepted; amended by [#943](https://github.com/dowdiness/loom/issues/943)
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

A validated transition computes candidate state without mutating the accepted
session. Languages may use a bounded reparse forest when every replacement is
admitted by their existing block-reparse policy. Loom initially limits this path
to at most 32 equal-length replacements. Any rejection, unsupported shape, or
larger batch uses the transactional full parse.

After successful candidate computation, the parser commits its source, snapshot,
diagnostics, and cache decisions. It then publishes the final snapshot once. An
unchanged authoritative source is accepted without parsing or publication.

Malformed language input remains a successful recovered syntax tree plus
structured diagnostics. `Failure` remains the channel for internal parser or
lexer defects.

The public operation fixes the transition semantics while leaving the parsing
strategy private. The bounded forest was adopted after fresh-result parity and
release JavaScript and wasm-gc benchmarks passed the #943 gate. A replayable
token source remains a later option only if measured workloads justify it.

## Consequences

- Callers can submit one editor-neutral atomic transition without exposing
  intermediate parser states.
- Loom reuses `ChangeSet`; it does not expose arrays of `Edit` or `TextDelta` as
  another public batch format.
- Mismatched evidence and internal failures preserve the previous accepted
  source, snapshot, and incremental cache.
- Successful forest updates invalidate edit-indexed token state and publish one
  coherent reactive snapshot. The next single edit rebuilds that state on demand.
- Full parse is the correctness baseline. Any faster private strategy must match
  fresh CST, AST, and diagnostics, preserve rollback, and outperform this
  baseline on JavaScript and wasm-gc.

## Validation evidence

Release measurements on the 2,500-block Markdown fixture were 1.22 ms for 10
edits and 3.51 ms for 32 edits on JavaScript, and 0.96 ms and 2.54 ms on
wasm-gc. A 100-edit batch selected full parsing: 20.06 ms on JavaScript and
15.54 ms on wasm-gc.

Tests cover fast-path `Failure` rollback, one reactive publication, structural
and size-based fallback, a subsequent single edit after token-state
invalidation, and fresh CST, AST, and diagnostics parity. The JavaScript
retention test runs 5,000 alternating batches under explicit GC and rejects
linear retained-heap growth.
