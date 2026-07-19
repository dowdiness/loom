# ADR: Loomgen Emitter Pre-Merge Checklist

**Date:** 2026-07-17
**Status:** Accepted
**Implementation plan:** Issue [#575](https://github.com/dowdiness/loom/issues/575)

## Context

Loomgen emitter changes can produce source that is syntactically valid enough to
escape local inspection while still losing declaration details, constructor
shape, expression precedence, pattern anchors, or lexer behavior. PR #573
exposed several of these defects before they were caught in review.

## Decision

Keep a concise, emitter-specific pre-merge checklist in `loomgen/README.md`.
The checklist requires the loomgen check, test, and formatting commands and
prompts verification of generated-source compilation, output shape, lexer
semantics, Unicode offsets, fixture diffs, and independent review.

## Rationale

These checks are specific to generated MoonBit and lexer output, so they belong
beside the emitter documentation rather than only in repository-wide contributor
guidance. Explicit commands make the minimum verification reproducible; targeted
questions cover failure modes that ordinary compilation does not reliably expose.

## Consequences

Emitter contributors have a repeatable author-side gate before review. The list
must evolve when a new emitter failure mode becomes recurring; it is guidance,
not an automated replacement for CI.
