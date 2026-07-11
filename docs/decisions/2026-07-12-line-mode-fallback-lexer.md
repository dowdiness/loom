# ADR: Line-mode lexer fallback annotation

**Date:** 2026-07-12  
**Status:** Accepted  
**Implementation plan:** [docs/plans/2026-07-fallback-lex.md](../plans/2026-07-fallback-lex.md)  
**Design specification:** [docs/superpowers/specs/2026-07-12-fallback-lex-design.md](../superpowers/specs/2026-07-12-fallback-lex-design.md)

## Context

`#loom.line_pattern` generates block-level line lexer functions. A line with no matching block pattern is ordinary input for many languages, such as Markdown paragraph text, and must be delegated to the language's inline lexer. The existing generated no-match behavior is `LexStep::Invalid`; changing it globally would break callers that already handle this step.

## Decision

Add the public annotation `#loom.fallback_lex("function_name")` for `#loom.line_mode` term variants. The named function is emitted in the line-mode no-match path and must have the existing mode-lexer fallback signature:

```moonbit
(String, Int) -> (LexStep[Token], LexMode)
```

The annotation requires both `#loom.lexmode("ModeName")` and `#loom.line_mode`. Token variants cannot use it. Multiple declarations for one mode must agree on the fallback function name.

When no fallback is declared, generated code retains the existing `Invalid` behavior. This preserves compatibility for generators whose callers intentionally handle unmatched block-level input.

## Rationale

The fallback must return both a token step and the next mode, so delegating to a complete mode lexer preserves the existing mode transition contract instead of inventing a second callback shape. Keeping `Invalid` as the no-annotation path makes the feature additive and avoids forcing every existing line-mode generator to provide a fallback.

## Consequences

- Generated line-mode lexers can compose with hand-written inline lexers without changing `ModeLexer`.
- Annotation errors are reported at generation time rather than producing ambiguous output.
- Existing line-mode fixtures and callers without `#loom.fallback_lex` remain behaviorally unchanged.
- The generated source directly references the named fallback function; the generator does not verify that the function body implements the signature beyond the emitted program's normal type checking.
