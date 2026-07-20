# ADR: Loomgen HTML Element Properties and Classification

**Date:** 2026-07-19
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-07-19-loomgen-html-element-properties.md](../archive/completed-phases/2026-07-19-loomgen-html-element-properties.md)
**Design specification:** [docs/superpowers/specs/2026-07-19-loomgen-html-element-properties-design.md](../superpowers/specs/2026-07-19-loomgen-html-element-properties-design.md)

## Context

The HTML example currently emits an `OpenTag(String)` token carrying the lexer's extracted tag name; attribute text is scanned from the source and is not embedded in that payload. `cursor.produced(...)` preserves the complete consumed source range for token text/source-span access. Loomgen's existing `#loom.void` / `#loom.rawtext` emitters operate on `SyntaxKind` variants. Handwritten tag membership in the lexer and parser can drift from generated syntax metadata.

Issue #607 requires generated element properties, native tag-stack behavior, and `Pred::HostGuard` dispatch. Unknown/custom tags must remain generic, source spelling must remain available for CST and diagnostics, and HTML tag matching must be ASCII case-insensitive.

## Decision

Add tag-name metadata to concrete `#loom.term` syntax variants (`Leaf`, `Node`, `ErrorNode`, or `Root`) through `#loom.tag("name")`. `#loom.view` projection variants cannot carry `#loom.tag`; loomgen rejects that combination. Generate `classify_element(String) -> SyntaxKind?` from the same classifier-enabled term metadata that drives the existing `is_void_element(SyntaxKind)` and `is_raw_text_element(SyntaxKind)` functions. Existing untagged property-only term fixtures remain supported.

Keep `OpenTag(String)` and `CloseTag(String)` as structural tokens. The name-only `OpenTag(String)` payload remains unchanged; complete opening-tag spelling and attributes are recovered from the token source span/text, so #607 does not migrate the payload. Known names classify to existing `SyntaxKind` variants; unknown/custom names return `None` and retain their original spelling. Static membership is generated; parse-local tag-stack checks remain native.

For #607, keep `@loom.Grammar::new` as the public entry point and add an HTML-side compiled-interpreter adapter. `make_html_parse_root()` compiles the HTML `GrammarIr` once. Each invocation of its returned `parse_root(ctx)` allocates a fresh tag stack, builds stack-capturing `natives` and `guards` registries, and calls `@grammar.interpret_compiled(compiled_ir, natives~, guards~)`. Thus the compiled grammar and `LanguageSpec` are reused while mutable stack state is parse-local. A future general guard-registration API is out of scope.

## Rationale

This preserves one syntax-kind taxonomy and one source of truth. It avoids both a parallel `ElementKind` type and a second handwritten tag-name table. Static metadata and parser-state-dependent validation remain separate responsibilities.

## Consequences

- `#loom.tag` requires annotation parsing, validation, duplicate canonical-name diagnostics, and classifier emission.
- ASCII lowercase canonical names are used for classification and tag-stack matching; original source spelling remains in tokens and diagnostics.
- HTML lexer/parser membership helpers can be removed after migration.
- The HTML native tag stack must be parse-local because language specifications are reused across parses.
- HostGuard registration is explicit in the HTML-side adapter; a general guard-annotation API remains out of scope.
- Existing untagged `#loom.void` / `#loom.rawtext` property-only generation remains compatible.
- Acceptance is tied directly to #607: generated predicates, classifier fallback, raw-text mode, native push/pop, HostGuard dispatch, and parity tests.

## Implementation Evidence

- `#loom.tag` is term-only, canonicalized, duplicate-checked, and emitted as an ASCII-case-insensitive classifier; generated void/raw-text predicates remain compatible.
- Native grammar dispatch uses compile-time dependency validation and an atomic `try_parse_rule(name) -> Bool` gate restricted to top-level `Choice` rules. Context-aware negated `HostGuard` predicates are covered by regression tests.
- HTML uses a compile-once grammar adapter with parse-local tag-stack and pure HostGuard state. Lexer/parser behavior is classifier-driven, and MAX_DEPTH/MAX_ERRORS recovery guarantees progress.
- Focused verification passed: grammar package tests 64/64, loomgen tests 264/264, and HTML tests 44/44; package checks and `git diff --check` passed. The generated classifier, element properties, parse-local stack, raw-text behavior, and case-insensitive close matching are covered by the committed tests.
