# Markdown Delimiter Frontier Design Decision

**Date:** 2026-07-20
**Status:** Candidate transport demonstrated; production integration deferred
**Related:** [Completed investigation plan](../../archive/completed-phases/2026-07-20-markdown-delimiter-frontier.md)

## Decision

Do not integrate the standalone delimiter frontier into Markdown production parsing in this
change.

The probe is retained as a standalone validation artifact, not wired into production
parsing. Its new `ParserContext` test demonstrates that Markdown's
`ParserContext::token_at(offset, goal=0)` can scan token kind and end facts from
caller-owned offsets without moving parser position when no `goal_source` is configured.
The conditional facts transport gate therefore passes for this context; production
integration remains deferred because the continuation-boundary, invalidation, and
performance gates have not passed.

The remaining blockers are the pure continuation-boundary split and the absence of a
production benchmark showing that the candidate transport reduces the #719 regression.
Do not add speculative emission, an opener-specific cache, or a partial compatibility
path.

## Evidence

The probe in `examples/markdown/delimiter_frontier_probe_wbtest.mbt`:

- obtains facts from the real `tokenize` adapter;
- stores cumulative `start`/`end` offsets and token kinds, including non-backtick and
  boundary tokens;
- rejects a `container_end` that is not zero or an exact token end;
- scans the full in-container stream with a monotonic `frontier_token`;
- retains left-to-right ownership for `R1 R2 R3` and unmatched runs; and
- passes its eight native tests, including the no-goal-source `token_at` scan, non-boundary,
  out-of-range, same-length post-boundary, and extended post-boundary-tail rejection.

The focused Markdown tests also pass: inline 19/19, incremental 26/26, source fidelity
6/6, and probe 8/8. The latest regression benchmark verification, without production
parser edits, measured:

- realistic CST: 209.65 us mean, versus frozen 175.52 us;
- realistic CST+AST: 309.98 us mean, versus frozen 273.60 us; and
- delimiter index R=512: 28.02 us mean, versus frozen 25.23 us.

These measurements are single runs and do not establish a stable optimization. They are
slower than the frozen baseline, so the existing baseline remains unchanged.

## Transport gate

Two transports were considered against the concrete implementation:

1. **Parser-session transport.** `LanguageSpec.parse_root` currently accepts only
   `(ParserContext[T, K]) -> Unit` (`loom/core/parser.mbt:68-80`). The indexed entrypoint
   constructs the context from token accessors and invokes that callback
   (`loom/core/parser_entrypoints.mbt:91-115`). Passing a second read-only cursor would
   change the public callback contract and require coordinated migration of
   grammar/factory callers and generated specifications. This transport was not selected.
2. **Existing `ParserContext` transport with no `goal_source`.** When no goal source is
   configured, `token_at(offset, goal=0)` returns the baseline token and end offset without
   moving parser position (`loom/core/parser_context_access.mbt:365-392`). The new probe
   test demonstrates walking Markdown token facts by carrying the returned end as the next
   offset (`examples/markdown/delimiter_frontier_probe_wbtest.mbt:327-348`). For delimiter
   analysis, the caller-owned offset supplies the start and token kind/end are sufficient;
   `token_text_at` and `peek_index` are not required by the scan.

   `token_at` delegates to `goal_source` whenever one is configured, regardless of the
   `goal` value. The candidate is therefore conditional on the no-goal-source state
   demonstrated by the probe, or requires a separate isolation contract for goal-directed
   parsing.

The conditional transport passes the minimal facts gate, but it does not by itself
establish the production container-boundary, invalidation, continuation-ownership, or
performance contract. The probe remains outside production parsing until those gates pass.

## Continuation boundary

The current Markdown helper combines observation and consumption: it decides whether the
next token can continue a paragraph and immediately emits continuation tokens
(`examples/markdown/cst_parser.mbt:277-303`). A valid integration would need a pure
`can_continue_line(...) -> Bool` receiving the same explicit container boundary as the
consuming operation, while leaving `consume_continuation(ctx)` responsible for CST events.
That split is the current integration blocker.

## Invariants for any future proposal

A future design must prove all of the following before production edits:

- frontier state is container-local and revision-local;
- the frontier never decreases;
- each token is visited at most once per container/revision;
- delimiter visits are bounded by in-container token count times a constant;
- source revision or container-range changes discard cached state;
- unmatched runs retain literal fallback and following emphasis/link parsing;
- continuation observation does not consume or emit; and
- one-shot, incremental, and block-reparse callers receive the same token facts and
  explicit boundary semantics.

## Consequences

No production Markdown or generic Loom parser API changes are made by this investigation.
The probe remains useful as evidence that the existing baseline `token_at` transport can
support a future Markdown-local scan. Any implementation must be a separate
design-reviewed change gated by pure continuation ownership, incremental invalidation,
and paired production benchmarks.
