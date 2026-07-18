# Future Producer Boundary for Generated and Custom Lexers

**Date:** 2026-07-17
**Issue:** #688
**Status:** Proposed
**Lifecycle:** Future direction; not part of the current implementation
**Related:** [Regex Capture Payload Annotations](../../decisions/2026-07-17-payload-capture.md)

## Purpose

Preserve a future direction for separating lexer-level custom hooks from
variant-level generated matching and payload construction. This document does
not change the accepted #688 implementation. It records the boundary that a
future refactor should preserve when payload lowering, line-mode hooks, and
custom lexers are revisited together.

## Current facts

The current implementation has two different custom-hook shapes:

1. Character-level `#loom.custom_lex` hooks are registered on the generated
   lexer in declaration order. A hook may return any `LexStep[Token]`; `Done`
   declines and lets later hooks or generated regex branches run. The hook is
   not constrained to construct the variant on which its annotation appears.
2. Line-level `#loom.line_pattern` plus `#loom.custom_lex` first matches the
   generated line pattern, then invokes the custom function. The function can
   determine the complete `LexStep`, including token, consumed length, next
   offset, and mode transition.

These are not the same producer shape and must not be collapsed into one
variant-local constructor strategy.

## Design principles

- A lexer-level hook is not a constructor annotation.
- Standalone hooks and generated variant matchers are separate plan layers.
- Hook declaration order and `Done` fallthrough are observable behavior.
- A generated matcher has one completion owner: either generated construction
  or a line post-match handler.
- Payload expressions belong only to generated construction.
- A payload annotation and a custom completion handler must not silently choose
  one another.
- Plan resolution happens once before either character- or line-level emission.
- Emitters consume resolved plans; they do not reinterpret raw annotations.

## Proposed internal representation

The future representation has two layers.

```text
LexerPlan {
  hooks: Array[LexerHookPlan]
  variants: Array[VariantPlan]
}
```

The lexer-level hook layer preserves the current standalone hook semantics:

```text
LexerHookPlan =
  StandaloneCustomHook {
    function: String
    declaration_order: Int
  }
```

A variant plan describes only generated matching and line post-match behavior:

```text
VariantPlan =
  GeneratedPattern {
    pattern: ParsedPattern
    on_match: GeneratedCompletion
  }
  | GeneratedLine {
    pattern: ParsedLinePattern
    on_match: GeneratedCompletion
  }
```

```text
GeneratedCompletion =
  Nullary
  | Payload(Array[ParsedPayload])
  | LinePostMatchHandler(String)
```

`LinePostMatchHandler` is deliberately not called `CustomConstructor`.
It can return the complete line-lexer result, including `LexStep`, consumed
length, next offset, and mode transition.

The future plan does not put standalone custom hooks in `VariantPlan`. A hook
may decline with `Done`, may produce a token for a different variant, and may
run before generated branches. Those properties cannot be represented by a
variant-local producer without losing semantics.

## Raw annotation resolution

Resolution must be deterministic and exclusive. The resolver examines the raw
annotation combination before `effective_pattern` can hide any annotation.

### Standalone custom hook

```text
custom_lex + no pattern + no line_pattern + no payload
  -> LexerHookPlan::StandaloneCustomHook
```

The hook remains a lexer-level entry in declaration order.

### Generated character matcher

```text
pattern + no custom_lex + no payload
  -> VariantPlan::GeneratedPattern { on_match: Nullary }

pattern + no custom_lex + complete payload
  -> VariantPlan::GeneratedPattern { on_match: Payload }
```

### Generated line matcher

```text
line_pattern + no custom_lex + no payload
  -> VariantPlan::GeneratedLine { on_match: Nullary }

line_pattern + no custom_lex + complete payload
  -> VariantPlan::GeneratedLine { on_match: Payload }
```

### Generated line matcher with post-match handler

```text
line_pattern + custom_lex + no payload
  -> VariantPlan::GeneratedLine {
       on_match: LinePostMatchHandler(custom_lex)
     }
```

This preserves the current line prefilter without pretending that the handler
is only a constructor.

## Invalid combinations

The resolver must reject these combinations before emission:

```text
pattern + custom_lex
  -> conflict

custom_lex + payload
  -> conflict

line_pattern + custom_lex + payload
  -> conflict

partial payload
  -> partial-payload error

pattern + line_pattern
  -> matcher conflict
```

`pattern + custom_lex` is invalid because the current character-level API has
no generated-match/post-match-hook contract. `effective_pattern` currently
removes the pattern from the regex pass; accepting both would leave dead
metadata.

`line_pattern + custom_lex` is valid only without payload because the custom
handler owns completion after the generated line match. Adding payload would
create two completion owners.

Partial payloads remain invalid. A partial payload cannot construct all fields,
and the custom hook does not receive the unused payload metadata. Accepting it
would create an annotation with no observable effect.

## Payload representation

`ParsedPayload` remains a private typed representation rather than an
`Array[String]` carried into the emitters.

```text
ParsedPayload {
  source: String
  parts: Array[PayloadPart]
}

PayloadPart =
  Text { kind: PayloadTextKind, span: PayloadSpan }
  | Capture {
      span: PayloadSpan
      index: Int
      operation: CaptureOperation
    }
```

Capture validation, diagnostics, and lowering must consume this same structure.
The future implementation should not maintain a separate
`max_payload_capture_index` scanner beside the rewrite scanner.

The lexical representation must distinguish at least ordinary code, string
text, character literals, comments, raw multiline text, and interpolation
delimiters. `$|` interpolation and `#|` raw multiline text must not be
collapsed into one opaque multiline category if both forms are supported.

## Emitter boundary

After resolution, emitters consume plans rather than `VariantDecl` annotation
fields.

```text
emit_lexer(LexerPlan)
  -> emit standalone hooks in declaration order
  -> emit generated character plans

emit_line_lexer(LexerPlan)
  -> emit generated line matchers
  -> invoke LinePostMatchHandler only after its pattern matches
```

The two emitters may differ in cursor and line-boundary mechanics, but they
must share:

- payload lowering
- conflict policy
- constructor-field arity validation
- generated completion semantics
- diagnostic propagation

## Migration sequence

This direction should be implemented only as a separate refactor. The steps
below deliberately separate tests that preserve current behavior from tests
that require a future policy decision.

1. Add green characterization tests for standalone hook ordering, `Done`
   fallthrough, arbitrary token production, line prefilter behavior, and line
   post-match mode transitions. These tests must pass before the refactor and
   must remain green after it.
2. Independently review and adopt the conflict policy through an ADR or an
   explicit update/supersession of the existing #688 ADR. Do not treat the
   proposed conflict policy as current behavior.
3. After that policy is adopted, add red acceptance tests for payload/custom
   conflicts, `pattern + custom_lex`, and partial payload rejection. These
   tests define the new contract and are expected to fail until the resolver
   is implemented.
4. Introduce private `ParsedPayload` and remove duplicated capture-index
   scanning.
5. Add a private resolver that produces `LexerPlan` and `VariantPlan` before
   emission.
6. Move character-level standalone hooks into `LexerHookPlan[]` without
   changing declaration order or fallthrough.
7. Represent line `line_pattern + custom_lex` as
   `GeneratedLine(LinePostMatchHandler)`.
8. Make both emitters consume resolved plans and remove raw strategy checks.
9. Only after parity is demonstrated, consider renaming the overloaded
   `#loom.custom_lex` concepts or adding a distinct annotation for line
   post-match handlers.

## Non-goals

- No public parser, regex, or runtime capture API.
- No immediate change to the accepted #688 implementation.
- No immediate change to custom-hook signatures.
- No attempt to make standalone hooks variant-local.
- No new annotation syntax until existing semantics have characterization
  tests and a concrete consumer requirement.

## Decision status

This is a proposed future direction, not an accepted implementation decision.
The existing #688 ADR remains authoritative for the current feature. No new ADR
is needed yet because this document records an unadopted design direction
rather than closing or changing a public contract. An ADR should be created when
this producer-boundary refactor is accepted for implementation or when it
changes the current hook policy.
