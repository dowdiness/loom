# Loomgen HTML Element Properties and Classification

**Date:** 2026-07-19
**Status:** Proposed
**Issue:** [#607](https://github.com/dowdiness/loom/issues/607)
**Related:** [#508](https://github.com/dowdiness/loom/issues/508), [#559](https://github.com/dowdiness/loom/issues/559), [#602](https://github.com/dowdiness/loom/issues/602)

## Problem

`examples/html` currently keeps void-element and raw-text membership in handwritten functions. The parser and lexer therefore maintain tag-name policy outside loomgen, while loomgen's existing `#loom.void` and `#loom.rawtext` emitters operate on `SyntaxKind` variants. The current HTML token is structural: `OpenTag(String)` carries the lexer's extracted tag name, while the lexer separately scans attributes from the source.

The design must connect these boundaries without introducing a second element-kind taxonomy, changing the `OpenTag(String)` token shape, or adding a second handwritten tag table. **Attribute preservation is resolved: retain the current name-only `OpenTag(String)` payload and use the existing token source span for source fidelity.** `cursor.produced(...)` records the full consumed source range, so attributes remain available through token text/source spans without duplicating them in the token payload.

## Goals

- Make tag classification and element-property membership derive from one annotated term source.
- Reuse the existing `SyntaxKind`, `is_void_element`, and `is_raw_text_element` APIs.
- Preserve the current name-only `OpenTag(String)` contract; preserve the complete opening-tag spelling and attributes through the token's source span/text path.
- Provide generic fallback for unknown/custom tags.
- Keep HTML tag matching and classification ASCII case-insensitive.
- Exercise #607's `@native` tag-stack and `Pred::HostGuard` requirements with parser-local state.
- Delete the duplicated handwritten void/raw-text membership checks after migration.

## Non-goals

- Full HTML5 tree construction, optional end tags, namespaces, entity resolution, or unquoted attributes.
- One lexer token variant per known tag.
- A parallel `ElementKind` enum.
- General HostGuard annotation design for every grammar; HTML uses the smallest explicit registration path needed by this issue.

## Source model

A `#loom.term` enum declares tag-specific `SyntaxKind` variants. A new `#loom.tag("name")` modifier associates a canonical HTML tag name with a term variant; `#loom.void` and `#loom.rawtext` remain orthogonal property modifiers.

```moonbit
#loom.term
pub(all) enum HtmlElementKind {
  #loom.tag("br")
  #loom.void
  #loom.node
  Br

  #loom.tag("script")
  #loom.rawtext
  #loom.node
  Script

  #loom.tag("div")
  #loom.node
  Div
}
```

The existing term-to-`SyntaxKind` generation path must produce these variants in the syntax package. `#loom.tag` is metadata and does not replace the role annotation.

## Validation and canonicalization

`#loom.tag` is valid only on variants in a `#loom.term` enum that opts into tag classification. The existing `#loom.void` / `#loom.rawtext` property-only fixtures remain valid without `#loom.tag`; this new constraint applies only to the classifier-enabled term enum. The parser validates:

- non-empty tag names;
- ASCII HTML tag-name characters only;
- canonicalization by ASCII lowercase, without Unicode case folding;
- no duplicate canonical tag names within one classifier-enabled term enum;
- no variant carrying both `#loom.void` and `#loom.rawtext`;
- tag-specific property modifiers in a classifier-enabled enum must have `#loom.tag`.

Diagnostics identify both the duplicate canonical name and the conflicting variants. Source spelling in the annotation may be normalized in generated output, but source spelling in input tokens and diagnostics remains unchanged.

Loomgen generates the classifier alongside the existing element-property output:

```moonbit
pub fn classify_element(name : String) -> SyntaxKind?
pub fn is_void_element(kind : SyntaxKind) -> Bool
pub fn is_raw_text_element(kind : SyntaxKind) -> Bool
```

`classify_element` lowercases ASCII letters and returns the annotated `SyntaxKind` for a known tag. Unknown and custom names return `None`. The caller retains the current name-only `OpenTag(String)` payload. Complete opening-tag spelling and attributes are recovered from the token's source span/text; no payload migration is part of #607.

The existing property emitter remains the source for `is_void_element` and `is_raw_text_element`. It continues to support untagged property-only term fixtures and is extended with classifier output only for classifier-enabled enums. No second `ElementKind` or tag-membership table is introduced.

## Lexer and parser flow

The structural token shape is fixed:

```text
source → OpenTag(String name) + source span → classify_element(name)
```

The lexer uses the generated classifier for raw-text mode selection. It stores the canonical classified name in mode state while preserving the current token/source contract. The parser uses the same classifier for void/raw-text behavior; it must not call a separate handwritten membership function. Source-fidelity tests must inspect the token source span/text for attributes and original spelling, not the `OpenTag(String)` payload.

For a known tag:

```text
Some(kind)
  → is_void_element(kind)
  → is_raw_text_element(kind)
```

For an unknown/custom tag:

```text
None
  → generic element behavior
  → original tag name remains available for CST and diagnostics
```

Open/close matching compares canonical ASCII names while diagnostics preserve the original spellings.

## Native tag-stack and HostGuard

The HTML integration chooses one concrete path: keep `@loom.Grammar::new` as the public entry point and add an HTML-side compiled-interpreter adapter.

The adapter is constructed once:

```text
make_html_parse_root()
  → compile(html_ir, native_names, guard_names) once
  → return parse_root(ctx)
```

Each invocation of the returned `parse_root(ctx)` allocates a fresh mutable tag stack, builds `natives` and `guards` closures that capture that stack, obtains `interpret_compiled(compiled_ir, natives~, guards~)`, and dispatches it on the current context. `LanguageSpec` and the compiled grammar are reused; the stack and captured maps are never shared between parse invocations.

The adapter must use the actual APIs:

```text
compiled_ir = @grammar.compile(html_ir, native_names~, guard_names~)
parse_root(ctx) =
  stack = fresh_stack()
  natives = html_native_registry(stack)
  guards = html_guard_registry(stack)
  @grammar.interpret_compiled(compiled_ir, natives~, guards~)(ctx)
```

`@loom.Grammar::new` receives this `parse_root` through the generated `LanguageSpec` factory. No parse calls `@grammar.interpret`, so compilation is not repeated. The adapter's construction function and registry functions are part of the #607 implementation contract.

The native operations are:

1. opening a non-void element pushes its canonical tag name;
2. closing an element pops and compares canonical names;
3. mismatch reports a diagnostic while preserving source tokens;
4. end-of-input with non-empty stack reports unclosed elements;
5. void elements do not push and do not require a closing tag;
6. raw-text elements use the classifier-selected lexer mode before child parsing.

The HTML grammar registers the required guard in `html_guard_registry(stack)` and uses `Pred::HostGuard` only for the context-dependent tag-stack check. Generated membership functions handle static void/raw-text classification; HostGuard handles stack state. Two failure checks are required: compiling the IR without the guard name must raise `MissingHostGuard`, while the HTML adapter must always pass the registered per-parse guard map to `interpret_compiled`. A missing runtime map entry follows the current interpreter contract and returns `false`; it is not claimed as a separate diagnostic.

## Responsibility map and removals

| Responsibility | Owner after migration |
|---|---|
| tag annotation parsing and duplicate validation | `loomgen/parse_annotations.mbt` |
| `SyntaxKind` variant generation | existing term/syntax emitter |
| tag classifier generation | new element-property/classifier emitter |
| static void/raw-text membership | generated `is_void_element` / `is_raw_text_element` |
| structural tag payload | `examples/html` `OpenTag(String)` / `CloseTag(String)` |
| raw-text scanning | HTML mode lexer, selected by generated classifier |
| tag-stack state | parse-local HTML native rule |
| stack-dependent guard | explicit HTML `HostGuard` registration |
| generic/custom tag fallback | HTML parser, retaining original name |

The migration removes `is_void_tag`, `is_raw_text_tag`, and duplicated case-fold/membership logic from `examples/html`. Raw-text scanning and tag-stack mechanics remain handwritten because they are stateful behavior, not static membership tables.

## Acceptance trace for #607

| Issue acceptance / exercise | Direct evidence required |
|---|---|
| `examples/html` exists | package check and native test |
| `<div>text</div>` parses | parser test with zero diagnostics and `Div` classification |
| `<br>` is void and has no children | generated predicate test plus CST test |
| `<script>` is raw text | generated raw-text predicate, lexer mode test, CST test |
| `#loom.void` / `#loom.rawtext` tables are generated | generated-source fixture and compile test |
| `@native` tag-stack push/pop | matching, mismatch, unclosed, and void-stack tests |
| `Pred::HostGuard` dispatch | compile-time missing-name test raises `MissingHostGuard`; registered per-parse adapter runtime test exercises the guard and stack behavior |
| unknown/custom tags remain generic | `my-widget` test preserving `OpenTag(String)` payload |
| ASCII case-insensitive behavior | mixed-case open/close and raw-text tests |
| no drift table remains | source-level regression or generated output check proving handwritten membership helpers are removed |
| existing behavior remains stable | all current `examples/html` tests pass unchanged |

## Rollout order

1. Add and validate `#loom.tag` metadata on term variants.
2. Generate and test the classifier while preserving existing property output.
3. Add direct generated-output and malformed-annotation tests.
4. Connect HTML lexer raw-text mode and parser membership to the classifier.
5. Add parse-local native tag-stack and explicit HostGuard registration.
6. Remove handwritten membership helpers.
7. Run focused loomgen and HTML tests, then review generated artifacts and acceptance trace.

## Decision record

This design requires a proposed ADR because it adds a public annotation/classifier contract and establishes a reusable generated metadata policy. See [ADR: Loomgen HTML Element Properties and Classification](../../decisions/2026-07-19-loomgen-html-element-properties.md).
