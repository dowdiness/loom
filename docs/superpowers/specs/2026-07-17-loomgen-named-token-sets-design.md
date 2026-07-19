# Loomgen Named Token Sets Design

**Date:** 2026-07-17  
**Issue:** [#687](https://github.com/dowdiness/loom/issues/687)  
**Status:** Accepted  
**Lifecycle:** Permanent loomgen annotation and generated token API; implemented and verified by parser, emitter, generated-consumer, and full-suite tests.

## Goal

Replace repeated hand-written `Token -> Bool` matches such as `is_value_start`,
`is_binary_operator`, and `is_block_boundary` with declarative named token-set
metadata and generated membership functions.

The feature describes finite sets of token variants. It does not add
context-sensitive grammar power, Pratt precedence, payload-aware matching, or
parser-state predicates.

## Concrete consumer and success signal

Current examples contain hand-written token-set classifiers, including
`is_value_start` in `examples/json` and `examples/graph-dsl`, while generated
`is_sync_point` is already consumed by the HTML parser. The feature succeeds
when at least one existing hand-written token-set classifier is migrated to a
generated function and the generated source compiles and preserves the
consumer's behavior.

## First-principles model

A named token set is a set of token variant tags. A token may belong to multiple
sets; the sets are not an exclusive partition.

```text
value_start = { LBrace, LBracket, StringLit, NumberLit }
```

The generated function is the membership test for that set:

```text
is_value_start : Token -> Bool
```

This is distinct from token roles. A role describes what a token is for
lexing/syntax-kind generation (`#loom.punct`, `#loom.literal`, `#loom.eof`, and
so on). A token-set membership describes a parser or recovery policy applied to
an already classified token.

## Source API

The proposed source API declares each named set once at enum level, then lists
its variant identifiers in that declaration:

```moonbit
#loom.token_set(value_start, LBrace, LBracket, StringLit, NumberLit)
#loom.token_set(binary_operator, Plus, Minus, Star)

#loom.token
pub(all) enum Token {
  #loom.punct("{")
  LBrace

  #loom.punct("[")
  LBracket

  #loom.literal
  StringLit

  #loom.literal
  NumberLit

  #loom.punct("+")
  Plus

  #loom.punct("-")
  Minus

  #loom.punct("*")
  Star
}
```

The identifier-argument fixture gate passed in
`loomgen/attribute_ast_wbtest.mbt`, and the end-to-end parser, emitter, generated
consumer, and full-suite tests now pass. The selected source representation is
therefore accepted.

The set declaration is centralized because membership is a cross-cutting
parser policy, not an intrinsic property of an individual variant. Centralized
declarations make the complete set, generated API ownership, and review scope
visible in one place. Variant-local annotations remain appropriate for roles and
lexer metadata.

Identifier arguments are preferred because they improve typo visibility and
leave a path toward editor completion, rename, and definition navigation.
Strict variant validation is required for both identifier and string
representations. The implementation must use identifier-valued
`#loom.token_set(value_start, LBrace, ...)` and reject any referenced variant
that is absent from the token enum.

## Validation

The annotation parser rejects:

- `#loom.token_set` outside a `#loom.token` enum;
- empty or invalid set names;
- duplicate set declarations;
- empty sets;
- variant identifiers not present in the token enum;
- duplicate variants within one set;
- generated names that collide with existing generated token functions or the
  reserved recovery name `is_sync_point`.

Set declarations are source-level names, not arbitrary strings. The generated
function is `is_<name>` and its name must be a valid, non-conflicting public
MoonBit function name.

## Validated lowering IR

Keep source declarations separate from the shared emitter input:

```moonbit
struct NamedTokenSet {
  name : String
  variants : Array[String]
}
```

The lowering step preserves set declaration order and variant list order. The
set contents are semantically unordered, but deterministic source order keeps
generated diffs reviewable.

Existing `#loom.recovery("sync")` annotations retain their public source and
`is_sync_point` API. Their validated variant collection lowers to the same
`NamedTokenSet` shape internally, with the reserved generated name
`sync_point`. Recovery semantics are not renamed or exposed as a generic user
set by this change.

## Emission

Use one shared membership emitter for ordinary named sets and recovery sets:

```text
emit_token_membership
```

Generate `token_membership.g.mbt` containing one public function per named set:

```moonbit
pub fn is_value_start(token : Token) -> Bool {
  match token {
    LBrace | LBracket | StringLit | NumberLit => true
    _ => false
  }
}
```

Payload fields are ignored with arity-aware wildcard constructor patterns
(for example, `Variant(_, _)` for a two-field constructor). Functions and
variants follow their validated source order. The shared emitter must use one
pattern helper for ordinary sets and recovery sets; it must not reproduce the
current single-wildcard recovery shortcut. The existing recovery output file
and public function may remain separate while sharing this emitter core during
the migration.

## Alternatives considered

### Distributed membership annotations

```moonbit
#loom.member(value_start)
LBrace
```

This preserves locality but repeats set names, hides the complete set, makes
API ownership unclear, and cannot distinguish a misspelled set name from a new
singleton set without a separate declaration.

### Declaration plus local membership references

```moonbit
#loom.token_set(value_start)
...
#loom.member(value_start)
LBrace
```

This detects unknown names but duplicates the relationship across a declaration
and every member site. It retains local editing convenience at the cost of
scattered set review and weak identifier navigation. It is not the canonical
API.

### Centralized declaration with variant list

```moonbit
#loom.token_set(value_start, LBrace, LBracket, StringLit)
```

This is the selected centralized model. It provides one source of truth for the
set, strict variant validation, clear generated API ownership, and a shared
lowering/emission boundary. The exact public argument representation remains
pending the fixture gate above.

## Non-goals

- No `#loom.predicate` annotation name.
- No context-dependent or parser-state-dependent predicate mechanism.
- No replacement for `Pred::HostGuard`.
- No changes to `@prefix`, `@prec`, or Pratt lowering.
- No payload-based token classification.
- No ranged or category-inference predicates.
- No term/SyntaxKind named sets in this issue.
- No public API rename for existing `is_sync_point` recovery output.

## Test plan

1. Add a minimal parser fixture proving enum-level `#loom.token_set` and
   multiple identifier arguments are preserved by the MoonBit attribute AST.
2. Add parser tests for valid declarations, duplicate sets, empty sets,
   unknown variants, duplicate members, invalid names, and generated-name
   collisions.
3. Add emitter tests for multiple sets, declaration order, variant order,
   payload variants with both one-field and multi-field constructors, and the
   no-set case. The recovery path must also pass a multi-field payload fixture.
4. Add a generated-source compilation fixture that calls the generated
   `is_<name>` functions.
5. Refactor one existing token-set consumer, preferably `examples/json`'s
   `is_value_start`, to use generated output and preserve its parser tests.
6. Verify that the shared emitter preserves existing HTML `is_sync_point`
   behavior.
7. Run MoonBit formatting, focused tests, native loomgen checks/tests,
   generated-source verification, interface/API drift checks, and independent
   review before implementation is merged.
