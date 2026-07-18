# `#loom.payload` Capture Extraction Design

**Date:** 2026-07-17  
**Issue:** #688  
**Status:** Approved for implementation  
**Lifecycle:** Cheap option; promote to permanent only after generated Markdown adoption and runtime-equivalence evidence.

## Goal

Allow `#loom.pattern` and `#loom.line_pattern` token annotations to construct payload fields from regex captures, while preserving private parser/IR boundaries and the existing `#loom.custom_lex` escape hatch.

## Concrete consumer and success signal

`examples/markdown` already consumes payload-bearing `HeadingMarker(Int)` and `CodeFenceOpen(Int, String)` tokens. Existing lexer tests assert their values, including empty and Unicode info strings. The implementation succeeds when a generated fixture and a migrated Markdown lexer produce the same payload values and token lengths as the current hand-written lexer.

## Design

### Annotation metadata

Extend private `VariantDecl` metadata with ordered payload expressions. `#loom.payload("expr")` annotations are positional: annotation 0 maps to constructor field 0. Parsing validates annotation arity and rejects payload annotations on nullary variants. Capture-index validation is performed against the supported private pattern representation, with diagnostics tied to the annotation/pattern source position using existing annotation diagnostics.

### Placeholder rewriting

Payload expressions remain arbitrary MoonBit expressions as specified by #688. The implementation performs lexical placeholder rewriting, not identifier whitelisting:

- Recognize `$0`, `$N`, `$N_start()`, `$N_end()`, and `$0_match_length()` only in MoonBit code, outside string literals and comments.
- Replace recognized placeholders with generated match-object/source-offset expressions.
- Preserve ordinary MoonBit syntax, string contents, comments, and standard-library calls verbatim.
- Validate the rewritten expression through the project’s MoonBit parse/check path before emission. Invalid expressions fail generation rather than producing generated source.

A capture that did not participate evaluates to the specified empty string behavior. `$N_start()` and `$N_end()` are absolute byte offsets in the source, obtained from the returned capture view; existing lexer position/length semantics remain unchanged.

### Emission

Introduce one private lowering helper shared by character-level and line-level emitters. Inline token construction is generated only when every constructor field has a payload expression. If any field is missing an expression, existing `#loom.custom_lex` behavior remains authoritative. Payload annotations without a usable custom lexer therefore fail with the existing missing-payload diagnostic rather than silently constructing a partial token.

Generated code continues to use existing `Produced`/`TokenInfo` and line-mode transition paths. No public parser, regex, capture, or IR API is added.

## Invariants

- #529 fail-closed pattern allowlist remains unchanged.
- Existing diagnostic precedence and positions remain unchanged.
- Cursor recovery and nullability semantics remain unchanged.
- Patterns without payload annotations generate byte-equivalent behavior.
- `#loom.pattern` and `#loom.line_pattern` remain mutually exclusive.
- Existing `#loom.custom_lex` remains available for complex logic.

## Test plan

1. Add failing annotation/parser tests for valid references, arity mismatch, nullary payloads, out-of-range captures, and partial fallback.
2. Add lexical-rewriter tests proving placeholders in strings/comments are untouched and ordinary standard-library expressions survive.
3. Add generated golden fixtures for both `#loom.pattern` and `#loom.line_pattern`, including multi-field payload construction.
4. Migrate the Markdown heading and code-fence payload paths to annotations and retain runtime tests for values, lengths, empty info strings, and Unicode info strings.
5. Run `moon ide`, focused tests, `moon check`, full `loomgen` tests, Markdown tests, and documentation checks through `rtk`.

## Non-goals

- No new regex syntax beyond capture references.
- No public parser/IR or runtime capture API.
- No removal of `#loom.custom_lex`.
- No changes to unrelated lexer, parser, diagnostic, or nullability behavior.
