# Line-mode lexer fallback design

**Date:** 2026-07-12  
**Issue:** [#700](https://github.com/dowdiness/loom/issues/700)  
**Status:** Approved

## Context

`#loom.line_pattern` generates mode functions that inspect the current line and produce a block token when a pattern matches. Before this change, a no-match path emitted `LexStep::Invalid`. `@core.tokenize_with_modes` treats `Invalid` as a lexer error, so ordinary line content such as Markdown paragraph text cannot fall through to an inline lexer.

The existing mode-aware lexer contract is:

```moonbit
(String, Int, LexMode) -> (LexStep[Token], LexMode)
```

A mode-specific lexer function therefore already has the exact callable shape required for a fallback function after its mode argument is fixed:

```moonbit
(String, Int) -> (LexStep[Token], LexMode)
```

## Decision

Add `#loom.fallback_lex("function_name")` as a term-variant modifier.

The annotation is valid only together with:

- `#loom.lexmode("ModeName")`
- `#loom.line_mode`

The named function is emitted verbatim in the generated line-mode lexer fallthrough:

```moonbit
return lex_inline(source, pos)
```

When no fallback is declared, generation preserves the current `Invalid` behavior for backward compatibility, as specified by issue #700. The generator does not silently produce an uncompilable function.

If multiple term variants declare the same line mode, their non-`None` fallback names must agree. Conflicting names are rejected during annotation parsing.

## Data flow

1. `parse_annotations` stores the string in `VariantDecl.fallback_lex`.
2. Token variants carrying the modifier are rejected.
3. Term variants carrying it without both `#loom.lexmode` and `#loom.line_mode` are rejected.
4. `emit_line_lexer` collects one fallback function name per line mode while collecting line modes.
5. Each generated mode function delegates on no-match when its fallback is `Some`, otherwise emits the existing `Invalid` step.

## Validation

The annotation argument must be exactly one string literal and a valid lexer function reference (`ident` or `@pkg.ident`), matching `#loom.custom_lex` validation.

## Testing

- Positive generation test asserts `return lex_inline(source, pos)` is emitted.
- Negative token-variant test rejects `#loom.fallback_lex` outside term metadata.
- Negative term-variant test rejects fallback without `#loom.line_mode`.
- Conflicting fallback names for one mode are rejected.
- Existing no-fallback output remains `Invalid`.
- The line-pattern fixture and golden output exercise the fallback path.
