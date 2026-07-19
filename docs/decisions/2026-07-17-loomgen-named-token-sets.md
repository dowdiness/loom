# ADR: Loomgen Centralized Named Token Sets

**Date:** 2026-07-17
**Status:** Accepted
**Implementation:** `loomgen` parser, shared membership emitter, JSON consumer migration, generated interface, and full test suites verified on 2026-07-17.

## Context

Loom-based parsers repeatedly hand-write `Token -> Bool` matches for finite
sets such as value starts, binary operators, and block boundaries. A token may
belong to several such sets, so these sets are overlapping parser policies, not
exclusive token categories.

A per-variant membership annotation would keep metadata near each token but
would repeat set names, hide each set's complete membership, and allow a typo to
look like a valid singleton set. A declaration-plus-local-reference design
would detect unknown names but would still split one relationship across two
locations. The generated output also needs to share match-pattern and ordering
logic with the existing recovery synchronization function.

## Decision

Named token sets are declared once at token-enum level:

```moonbit
#loom.token_set(value_start, LBrace, LBracket, StringLit)
```

The minimal fixture in `loomgen/attribute_ast_wbtest.mbt` and the
end-to-end parser, emitter, generated-consumer, and full-suite tests pass.
The public annotation and identifier-valued representation are accepted.

After validation, lower declarations and existing `#loom.recovery("sync")`
metadata to a shared `NamedTokenSet` representation. Use
`emit_token_membership` to generate `token_membership.g.mbt` membership
functions such as `is_value_start`. Preserve the existing `#loom.recovery`
source syntax and `is_sync_point` public API.

## Rationale

Centralized declarations make the complete set and generated API ownership
visible in one reviewable location. Identifier-valued references improve typo
visibility and preserve a path toward editor completion, rename, and
definition navigation; strict variant validation is required for both
identifier and string representations. The shared lowering IR prevents recovery
and ordinary set membership emitters from duplicating payload wildcard, ordering,
and signature logic.

This feature is deliberately limited to token-tag membership. It does not add
context-sensitive grammar power, Pratt precedence, payload-aware matching, or a
replacement for `Pred::HostGuard`.

## Consequences

Loomgen gains an enum-level annotation and a generated token membership file.
At least one existing hand-written token-set consumer must be migrated so the
feature has an end-to-end behavioral signal. Token roles and lexer metadata stay
variant-local; named parser/recovery sets are centralized. Existing recovery
annotations and generated APIs remain stable while sharing the new emitter core.
