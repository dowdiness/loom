# ADR: Physical-Line Production Boundaries in `.loomgrammar`

**Date:** 2026-07-17  
**Status:** Accepted  
**Implementation plan:** [Issue #556](https://github.com/dowdiness/loom/issues/556)

## Context

The `.loomgrammar` parser previously used one whole-file parenthesis stack to
identify production boundaries. A malformed opening parenthesis in one
production could therefore match a stray closing parenthesis after the next
production's header and attribute the next production's `=` to the preceding
production.

The parser must remain fail-closed, preserve same-line nested notation such as
`A = (B C = D)`, and report diagnostics against the production that owns the
malformed body.

## Decision

A production header is an `IDENT =` pair whose identifier is the first token on
a physical source line. Indentation is permitted; the boundary is determined by
the token line transition, not by column zero.

Same-line `IDENT =` pairs remain body tokens. Consequently, `A = (B C = D)`
continues to treat `C =` as malformed body syntax rather than as a new
production.

## Rationale

Line-start anchoring removes the ambiguity between a production boundary and a
parenthesis that accidentally closes across productions. It improves diagnostic
attribution for malformed files without changing valid nested groups. The
parser can also remove the obsolete whole-file parenthesis matching and depth
tracking because production boundaries no longer depend on matching a closing
parenthesis in a later production.

## Consequences

- Malformed productions are isolated at physical-line boundaries for error
  reporting.
- A same-line `IDENT =` cannot introduce a second production; it is rejected as
  an unexpected separator in the preceding body.
- Indented production headers remain valid.
- The grammar-file format now reserves physical-line `IDENT =` pairs as
  production boundaries, including when the preceding body has an open group.
