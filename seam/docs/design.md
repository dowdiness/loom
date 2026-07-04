# seam — Design Principles

This document records the design principles for the `seam` library's public API.
It is written for future implementors extending the library, particularly the
`SyntaxNode` and `SyntaxToken` layer.

---

## Core goal

`seam` must run gracefully on all input — including trees produced by
error-recovery parsers — while providing explicit, type-level signals when a
query produces no meaningful result. It must never panic on well-typed input.

---

## The three-layer API model

### Layer 1 — Total functions (never panic)

Every basic query returns a value for any input. A tree produced by error
recovery, a zero-length node, or an offset that falls outside the tree will
all produce a valid return value rather than an abort or exception.

```moonbit
find_at(offset)               -> SyntaxNode   // returns self when no child covers offset
start()                       -> Int
end()                         -> Int
kind()                        -> RawKind
children()                    -> Array[SyntaxNode]
tokens()                      -> Array[SyntaxToken]
all_children()                -> Array[SyntaxElement]
direct_children_of_kind(kind) -> Array[SyntaxNode]
direct_tokens_of_kind(kind)   -> Array[SyntaxToken]
```

**Why:** IDEs always operate on partially-formed source. A panic mid-traversal
during an incremental re-parse is worse than a conservative fallback. The
fallback contract must be documented in the function's doc comment so callers
know what "nothing found" looks like.

**Tradeoff:** A total function that returns `self` on bad input can look like
success to a careless caller. This is why Layer 2 exists.

### Layer 2 — Checked functions (explicit `Option` signalling)

Operations where "nothing here" is a meaningful, common outcome return `T?`.
The IDE gets a type-level signal rather than a fallback it must detect manually.

```moonbit
find_at_checked(offset)    -> SyntaxNode?   // None = offset outside span
parent()                   -> SyntaxNode?   // None = this is the root
first_child()              -> SyntaxNode?   // None = leaf or empty node
first_token()              -> SyntaxToken?  // None = no tokens in subtree
find_token(kind)           -> SyntaxToken?  // None = no matching direct token
direct_token_of_kind(kind) -> SyntaxToken?  // None = no matching direct token
```

**Why:** Without this layer, every IDE caller must manually re-check spans after
calling a total function. Option types encode the contract in the type system.

**Relationship to Layer 1:** Layer 2 functions are thin wrappers over Layer 1.
`find_at_checked` is just `find_at` with a span check. Layer 1 is the efficient
recursive workhorse; Layer 2 is the safe public entry point for consumers.

### Layer 3 — Error information

For IDE diagnostics and semantic projections, callers need to know whether a
query failed because input is malformed — not just that a query returned a
fallback.

```moonbit
is_error(error_kind : RawKind) -> Bool
contains_errors(error_node_kind : RawKind, error_token_kind : RawKind) -> Bool
required_direct_token_of_kind(kind, message~) -> Result[SyntaxToken, ProjectionShapeError]
```

`CstNode::has_errors` exists at the concrete layer. `SyntaxNode` exposes both
methods directly so callers do not need to reach through `.cst_node()`.

Projection cardinality helpers are the direct-shape branch of this layer. They
keep language-specific wording in the projection (`message~`) while `seam`
provides structured source ranges, actual counts, and expected cardinality.

**Why:** An IDE wants to skip hover/completion logic on error subtrees, show a
distinct diagnostic highlight, or reject a malformed semantic slot. This
requires knowing *why* a subtree is malformed, not just that a query produced a
fallback.

---

## Direct vs recursive queries

The `SyntaxNode` navigation surface is intentionally direct by default:
`children()`, `all_children()`, `tokens()`, `find_token()`,
`tokens_of_kind()`, and the `direct_*` helpers all inspect direct visible
children only. `RepeatGroup` nodes are transparent so repeated grammar elements
still look like siblings, but ordinary interior nodes are not searched.

For semantic projection and argument-shape validation, prefer the explicit
`direct_*` names. A method projection that accepts `.fast(2)` should require a
direct `NumberToken` on the method-call node; `.fast(slow(2))` must not pass
validation merely because the callback child contains a descendant number token.
If a projection needs recursive extraction, write that traversal at the call
site so the recursion boundary is visible in review.

`token_text(kind)` is intentionally a convenience helper, not a validation
helper. It returns `""` when the token is absent, which is useful for display
views but can hide missing semantic slots. Projection code that validates shape
should keep the `Option` from `direct_token_of_kind(kind)` and branch explicitly.

## Anti-patterns to avoid

| Pattern | Problem |
|---|---|
| `abort` / `panic` on bad input | Crashes on error-recovery trees; hard to debug |
| Silent fallback that looks like success | `find_at(9999)` returns root — caller cannot distinguish from a real result without a span check |
| Recursive search for direct semantic slots | A nested callback token accidentally satisfies a method argument slot |
| Magic sentinel values | `RawKind(-1)`, returning `-1` for "not found" — implicit, easy to forget to check |
| Public constructors with unchecked offsets | `SyntaxNode::new(cst, None, arbitrary_offset)` bypasses the invariant that offset must derive from tree structure |

---

## Implementation status

**Complete.** All three layers are fully implemented and tested.

- All `SyntaxNode` fields (`cst`, `parent`, `offset`) are `priv`.
- Layer 1 total functions: `find_at`, `start`, `end`, `kind`, `children`, `tokens`, `all_children`, `direct_children_of_kind`, `direct_tokens_of_kind`.
- Layer 2 checked functions: `find_at_checked`, `parent`, `first_child`, `first_token`, `find_token`, `direct_token_of_kind`.
- Layer 3 error information: `is_error`, `contains_errors`, `ProjectionShapeError`, and direct cardinality helpers.
- Additional navigation: `nth_child`, `child_of_kind`, `direct_child_of_kind`, `tokens_of_kind`, `tight_span`, `token_at_offset`, `cst_node`.
- View helpers: `token_text`, `children_from`, `nodes_and_tokens` — reduce boilerplate when writing typed views and fold algebras.

The library satisfies all four structural independence properties (completeness,
context-freedom, uniform error representation, transparent structure) described in
[Incremental Hylomorphism §2](https://github.com/dowdiness/canopy/blob/main/docs/architecture/Incremental-Hylomorphism.md).

---

## Design references

- [rowan](https://github.com/rust-analyzer/rowan) — the Rust CST library that
  `seam` is modelled after. Its `SyntaxNode::covering_element` is total;
  `SyntaxNode::token_at_offset` returns an enum that explicitly represents the
  "nothing here" and "on boundary" cases.
- [rust-analyzer architecture](https://github.com/rust-analyzer/rust-analyzer/blob/master/docs/dev/architecture.md) —
  describes the green/red tree split that corresponds to `CstNode`/`SyntaxNode`.
- [tree-sitter](https://tree-sitter.github.io/tree-sitter/) — error recovery
  design; all queries are total over error nodes.
