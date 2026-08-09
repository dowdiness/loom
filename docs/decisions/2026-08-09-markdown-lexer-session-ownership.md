# ADR: Markdown Lexer Session Ownership and Replay API

**Date:** 2026-08-09
**Status:** Accepted
**Issues:** [#908](https://github.com/dowdiness/loom/issues/908)
**Implementation plan:** [Issue #908](https://github.com/dowdiness/loom/issues/908)

## Context

Markdown detached stepping needs source-derived fence ownership and same-line
container facts. Stateless replay rescans the source from the beginning for
each detached position and becomes superlinear on forward middle replays. The
first implementation used bounded module-global caches to recover the required
performance, but those caches were shared across parser sessions and source
streams.

The parser already creates a fresh mode-lexer shell for each
`ModeRelexFactory` session. The detached compatibility function, however,
has no state parameter. The design must preserve the existing stateless API
while making reusable performance state explicit and session-owned.

## Decision

Markdown separates the lexer into a deterministic core and a session shell.

The functional core owns source facts and replay transitions. It does not read
or write global cache state. `MarkdownLexSession` owns only derived acceleration
state: detached replay, same-line facts, line-end hints, source lifecycle, and
fenced-code continuation context.

`new_markdown_mode_lexer()` creates one `MarkdownLexSession` per parser or full
-tokenization shell. `ModeRelexFactory` therefore never shares lexer cache state
between sessions.

The public APIs have distinct contracts:

- `markdown_lex_step(source, position, mode)` remains the stateless compatibility
  step and never mutates replay or line-fact caches.
- `MarkdownLexSession()` constructs an opaque reusable session.
- `session.step(source, position, mode)` performs stateful detached stepping.
- `session.reset()` explicitly ends the session lifecycle.

A source change automatically invalidates source-derived state. Sessions must
not be shared between independent source streams. Cache hits and misses are
semantically equivalent; caches may affect performance but never token, mode,
or diagnostic results.

The replay cache remains bounded and one-source-local. No generic parser-core
session API, public cache representation, or second semantic ownership path is
introduced.

## Rationale

The integrated prototype reproduced the performance shape that motivated the
cache while proving independent interleaved sessions. On a 1024-line middle
replay, the session path measured approximately 410 microseconds on wasm-gc
and 361 microseconds on JavaScript, compared with approximately 57–58
milliseconds for the stateless control. Session ownership preserves this
benefit without making correctness depend on process-global mutable state.

Keeping the old stateless function avoids breaking existing callers and makes
its cost model explicit. The additive opaque session API gives callers that
perform repeated detached stepping a way to opt into reusable state without
exposing cache internals.

## Consequences

- The Markdown package gains the additive `MarkdownLexSession` API and its
  generated `.mbti` entries.
- Global detached-replay and same-line-facts caches are removed.
- Fresh/incremental parser sessions own their lexer state independently.
- Stateless compatibility remains available for baselines and isolated calls.
- Session parity, source replacement, backward stepping, EOF, mode exit,
  oversized-source, and JS/wasm-gc benchmark coverage are required before
  further cache changes.
- Future replay/checkpoint optimizations must preserve the same pure-core and
  session-shell boundary.
