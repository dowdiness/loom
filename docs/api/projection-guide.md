# CST Projection Guide

This guide is for language authors who turn a `@seam.SyntaxNode` tree into a
private projection IR and then into a semantic model. The goal is not to add a
query language; it is to make the safe, reviewable projection shape explicit.

## Recommended pipeline

1. Parse with the unified parser:

   ```mbt nocheck
   let parser = @loom.new_parser(source, my_grammar)
   // Share parser.runtime() with downstream reactive cells.
   let syntax = parser.syntax_tree().read_or_abort()
   let diagnostics = parser.diagnostics().read_or_abort()
   ```

2. Treat parser diagnostics as a semantic gate. Recovery CSTs are useful for
   editor display, but semantic models should not silently accept syntax the
   parser already marked invalid. In a stateful authoring attachment, publish
   parser diagnostics for the current text immediately while retaining the last
   successful semantic document until projection succeeds again; see the
   [last-good semantic attachment guide](last-good-semantic-attachment.md).

3. Validate direct CST shape and lower into a private IR owned by the language
   package.

4. Lower the private IR into the public semantic model.

5. Keep recursive traversals explicit. If a projection intentionally walks all
   descendants, write that traversal so reviewers can see the recursive boundary.

## Why insert a private IR?

A CST is concrete and parser-shaped. A semantic model is user-facing and should
not expose recovery placeholders, punctuation tokens, repetition scaffolding, or
parser-local grouping. A private IR gives the language package a place to record
validated structure before committing to semantic meaning.

Use the private IR to make these boundaries clear:

- **CST shape:** direct tokens and direct child nodes are present where the
  grammar says they belong.
- **Recovery policy:** missing tokens, error nodes, and malformed groups become
  explicit private-IR errors instead of accidental defaults.
- **Semantic lowering:** names, literals, and operators are converted after the
  shape is known, not while recursively searching for any matching descendant.

The private IR can be as small as a few private enums or structs near the
conversion code. It does not need to become public API.

## Direct shape queries

Projection code should prefer the explicit direct-child helper names when it is
checking the immediate shape of a syntax node:

| Intent | Prefer | Notes |
|---|---|---|
| First direct token of a kind | `node.direct_token_of_kind(kind)` | Use for singleton slots such as an identifier, literal token, keyword flag, or opening fence. |
| Exactly one direct token of a kind | `node.required_direct_token_of_kind(kind, message=...)` | Use when absence or duplication is a projection error. |
| Optional direct token of a kind | `node.optional_direct_token_of_kind(kind, message=...)` | Use when zero or one is valid, but duplicates are malformed. |
| No direct tokens of a kind | `node.expect_no_direct_tokens_of_kind(kind, message=...)` | Use for disallowed punctuation such as a comma in a single-argument slot. |
| All direct tokens of a kind | `node.direct_tokens_of_kind(kind)` / `node.required_direct_tokens_of_kind(kind, message=...)` | Use when repetition makes multiple same-kind tokens legal at the same level. |
| Direct child nodes of a kind | `node.direct_child_of_kind(kind)` / `node.direct_children_of_kind(kind)` | Use when the grammar has singleton or repeated child nodes of one kind. |
| Cardinality-checked direct child nodes | `required_direct_child_of_kind`, `optional_direct_child_of_kind`, `expect_no_direct_children_of_kind`, `required_direct_children_of_kind` | Use when missing or duplicate child nodes should become projection errors. |
| Ordered direct node/token zipper | `node.nodes_and_tokens()` | Use when the direct sequence matters, such as binary operator + operand pairs. |

The direct-visible-child contract is:

- `RepeatGroup` nodes are transparent, so repeated grammar elements appear as
  direct siblings.
- Ordinary nested nodes are not searched.
- `find_token()` and `tokens_of_kind()` are also direct-visible-child helpers,
  but projection and semantic-validation code should use `direct_*` names so the
  boundary is visible at the call site.

`token_text(kind)` is a display-oriented convenience for typed views and JSON
presentation where an empty string is an acceptable fallback. Do not use it for
semantic validation: a missing identifier slot and a present zero-length token
both become `""`. For semantic projection, keep the `Option` from
`direct_token_of_kind` and choose an explicit error branch.

## Example: direct token slot

For a JSON member, the key must be a direct `StringToken` on the member node. A
recursive search would be wrong: `{ : "value" }` must not borrow the value token
as the missing key.

```mbt nocheck
let key_text = match member.direct_token_of_kind(StringToken.to_raw()) {
  Some(tok) => tok.text()
  None => "" // or a private-IR error variant
}
```

For stronger error reporting, either branch into a private IR variant or use a
cardinality helper that preserves the projection-owned message:

```mbt nocheck
let key = match member.required_direct_token_of_kind(
  StringToken.to_raw(),
  message="JSON member requires exactly one direct string key",
) {
  Ok(tok) => tok.text()
  Err(err) => return MemberIr::MalformedMember(message=err.message)
}
```

```mbt nocheck
enum MemberIr {
  Member(key~ : String, value~ : ValueIr)
  MalformedMember(message~ : String)
}
```

## Example: direct node/token sequence

Binary expressions often need the direct child nodes and direct operator tokens
in source order. `nodes_and_tokens()` is still direct-shape style: it partitions
the node's direct visible children rather than searching descendants.

```mbt nocheck
let (operands, tokens) = node.nodes_and_tokens()
let ops : Array[Bop] = []
for tok in tokens {
  if tok.kind() == PlusToken.to_raw() {
    ops.push(Bop::Plus)
  } else if tok.kind() == MinusToken.to_raw() {
    ops.push(Bop::Minus)
  }
}
```

Use this style when child-node order and token order must be interpreted
together. If the conversion starts needing arbitrary descendant lookups, split
that into a named recursive helper and document why recursion is intended.

## Anti-pattern: recursive token search for validation

Do not validate an immediate argument slot by asking whether any descendant token
exists. For example, a method-call projection that accepts `.fast(2)` should not
accept `.fast(slow(2))` just because the nested callback contains a
`NumberToken`.

```mbt nocheck
// Preferred: the number must be a direct argument token on this node.
match call.direct_token_of_kind(NumberToken.to_raw()) {
  Some(n) => lower_number(n)
  None => report_shape_error(call)
}
```

If a recursive query helper is added in the future, its name should make
recursion visible, such as `descendant_*` or `recursive_*`. Until then, write the
recursive walk directly.

## Projection review checklist

Before shipping projection code, check:

- Does each semantic slot use `direct_*`, `nth_child`, `child_of_kind`,
  `nodes_and_tokens`, or another direct helper?
- Are parser diagnostics checked before producing a trusted semantic model?
- If the projection is stateful, does malformed parser or projection state retain
  the last-good semantic document instead of replacing it?
- Are missing direct tokens and missing direct children represented explicitly,
  rather than converted to a successful semantic default?
- Are recursive walks named and localized so reviewers can tell they are
  intentional?
- Do tests include nested invalid shapes that would have passed if the code used
  a recursive descendant search?

See [ADR 2026-05-25](../decisions/2026-05-25-direct-cst-projection-queries.md)
for the decision behind the `direct_*` helper names and cardinality helpers.
