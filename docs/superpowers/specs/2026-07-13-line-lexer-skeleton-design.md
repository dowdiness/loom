# Line-mode lexer skeleton integration design

**Date:** 2026-07-13  
**Issue:** [#699](https://github.com/dowdiness/loom/issues/699)  
**Status:** Approved

## Context

`emit_lexer_skeleton` creates a persistent `lexer_skeleton.g.mbt` containing the public `lex` dispatcher and one `lex_<mode>` aborting stub per lex mode. `emit_line_lexer` separately creates `line_lexer.g.mbt` with functions using the same names for `#loom.line_mode` modes. The artifacts cannot compile together without the user deleting generated skeleton stubs.

The integration must make generated line modes reachable from the existing dispatcher, retain an intentional handwritten `lex_<mode>` override point, and migrate an existing untouched skeleton without replacing handwritten implementations.

## Decision

Use layered delegation.

`line_lexer.g.mbt` emits one helper per line mode named `generated_lex_<mode>`. Each helper has the existing `(String, Int) -> (@core.LexStep[Token], LexMode)` contract and owns all generated line-pattern matching logic.

`lexer_skeleton.g.mbt` remains the owner of the public `lex` dispatcher and of `lex_<mode>` functions. For each generated line mode, the skeleton function delegates directly to the corresponding helper. Non-line modes retain their aborting stubs.

A new skeleton emitted during `--line-lexer` generation contains these delegates from its first write. A normal invocation without `--line-lexer` retains existing skeleton-once semantics.

## Existing skeleton migration

When `--line-lexer` finds an existing skeleton, generation compares each requested line-mode function with Loom's exact historical generated aborting-stub text. It replaces only that exact text with the generated-helper delegate.

Any non-identical `lex_<mode>` body is treated as a handwritten override and is left unchanged. The generated helper is still emitted, but the override deliberately controls dispatch for that mode. `--force-lexer` remains the explicit operation that can overwrite the entire skeleton.

This migration is deterministic and idempotent: the second generation sees the already-generated delegate and leaves it unchanged.

## Data flow

1. Annotation parsing identifies the `#loom.line_mode` lex modes already used by `emit_line_lexer`.
2. `emit_line_lexer` emits `generated_lex_<mode>` functions for those modes.
3. Skeleton emission receives the same line-mode set and emits delegates instead of aborting stubs for new skeletons.
4. Existing skeleton integration replaces only recognized generated aborting stubs for that mode set.
5. The main generation flow writes the generated helper output and the compatible skeleton artifacts from one preflighted line-lexer request.

## Failure behavior

`--line-lexer` keeps its existing validation: it rejects requests without both line-pattern tokens and line-mode terms before writing output. A user override is not an error and is never rewritten implicitly. Existing no-match behavior and `#loom.fallback_lex` behavior remain inside the generated helper unchanged.

## Testing

- Preserve the current all-stub skeleton golden test.
- Add unit coverage for a new skeleton containing line-mode delegates and non-line stubs.
- Add migration coverage proving exact legacy stubs become delegates, handwritten functions remain byte-identical, and a second migration is unchanged.
- Update the line-lexer golden output to use generated-helper names.
- Update the compile-and-run Markdown fixture to use the generated skeleton dispatcher and a handwritten `lex_inline` override inside that skeleton; regeneration must preserve the override.
- Run `--regenerate-fixtures` twice and assert the generated artifacts are deterministic.
- Document the generated-helper and override contracts in `loomgen/README.md`.

## Decision record

An ADR is required at completion because this changes Loom's public generated-file contract and establishes the override policy for future lexer generation.
