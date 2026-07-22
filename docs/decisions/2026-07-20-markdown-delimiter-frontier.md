# ADR: Defer Markdown Delimiter Frontier Integration

**Date:** 2026-07-20
**Status:** Accepted
**Issue:** #719
**Related:** [Markdown delimiter frontier design](../superpowers/specs/2026-07-20-markdown-delimiter-frontier-design.md); [investigation plan](../archive/completed-phases/2026-07-20-markdown-delimiter-frontier.md)
**Implementation plan:** [Investigation plan](../archive/completed-phases/2026-07-20-markdown-delimiter-frontier.md)

## Context

The #719 Markdown benchmark regression prompted an investigation into a cmark-style,
container-local monotonic frontier for code-span delimiter matching. The intended design
preserved the approved CommonMark code-span ownership and bounded delimiter work by the
number of tokens in the inline container.

A standalone probe demonstrated the algorithm over real Markdown lexer facts, including
cumulative source ranges, non-backtick tokens, explicit container ends, unmatched runs,
and left-to-right ownership. It did not establish that production Markdown parsing could
obtain those facts without crossing the `ParserContext` event and state boundary.

## Decision

Do not integrate the frontier probe into production Markdown parsing in this
investigation. Keep the probe disconnected from production parsing and do not add
speculative emission or an opener-specific suffix-result cache.

When no `goal_source` is configured, the existing `ParserContext::token_at(offset, goal=0)`
is a viable candidate transport for Markdown delimiter facts: it returns token kind and end
offset without moving parser position, and the caller can carry the returned end as the next
offset. The probe demonstrates this no-goal-source path. Because `token_at` delegates to
`goal_source` whenever one is configured, regardless of `goal`, the candidate is conditional
on that state. No new generic cursor or `LanguageSpec` callback change is justified yet.

Defer production integration until a separate design proves the pure continuation-boundary
split, container/revision invalidation, and a paired production benchmark improvement.

## Rationale

The current `LanguageSpec.parse_root` callback receives only `ParserContext`, and the
indexed entrypoint constructs that context before invoking it. A parser-session cursor
would change the callback contract and require coordinated migration across grammar
factories and generated specs. The existing no-goal-source `token_at` path avoids that API
change and passes the minimal delimiter-facts test, but it does not establish the pure
continuation ownership, invalidation, or performance contracts needed for production.
Those gates—not the absence of arbitrary token access—are the reason integration is
deferred.

The probe and focused tests pass. The latest clean-branch benchmark verification measured
CST 172.91 us, CST+AST 263.10 us, and delimiter index R=512 at 24.91 us, versus frozen
baselines of 175.52 us, 273.60 us, and 25.23 us. These single-run measurements are below
the frozen baseline but do not prove a stable optimization. The baseline therefore
remains unchanged.

## Consequences

- No production parser behavior or public parser API changes result from this work.
- The probe remains as evidence for real-lexer representativeness and the linear-visit
  invariant.
- Future work starts with a token-facts transport and pure continuation-boundary design;
  it must not treat the probe as an integration-ready API.
- The existing benchmark baseline remains the classification reference.
