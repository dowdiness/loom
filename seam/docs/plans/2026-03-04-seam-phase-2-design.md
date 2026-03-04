# seam Phase 2 — Design

This document records the design for the Phase 2 completion of `seam`.
See [../design.md](../design.md) for the three-layer API model and the
Phase 1 / Phase 2 boundary that defines this work.

**Status:** Approved — ready for implementation

---

## Goal

Complete the three-layer API model defined in `design.md`:
- **Harden** the `SyntaxNode` struct (privatise `parent` and `offset` fields)
- **Add Layer 2** checked functions (explicit `Option` signalling)
- **Add Layer 3** error-information methods (IDE diagnostic support)
- **Fix** the one external caller of `SyntaxNode::new` in `term_convert.mbt`

---

## Breaking changes

Exactly one breaking callsite:

```
examples/lambda/src/term_convert.mbt:334
  @seam.SyntaxNode::new(cst, None, offset)   // breaks when priv added to fields
```

Fix: replace with `@seam.SyntaxNode::from_cst(cst)`. The function is always
called with `offset=0` in practice. No behavioural difference.

Zero other external callers access `.parent` or `.offset` directly (confirmed
by codebase search — all 18 `.offset` references are internal to
`seam/syntax_node.mbt`; no `.parent` references exist outside it).

---

## Field changes — `seam/syntax_node.mbt`

```moonbit
// Before (Phase 1):
pub struct SyntaxNode {
  priv cst : CstNode
  parent : SyntaxNode?       // readable by external callers
  offset : Int               // readable by external callers
}

// After (Phase 2):
pub struct SyntaxNode {
  priv cst : CstNode
  priv parent : SyntaxNode?  // internal implementation detail
  priv offset : Int          // internal implementation detail
}
```

`SyntaxNode::new` remains public — it constructs the struct but callers
can no longer read the fields back. `SyntaxNode::from_cst` remains the
recommended construction path for root nodes.

---

## Layer 2 — Checked functions

All four are thin wrappers or span-checks over existing Layer 1 functions.
No new tree traversal logic is needed.

```moonbit
/// None when this is the root node.
pub fn SyntaxNode::parent(self : SyntaxNode) -> SyntaxNode? {
  self.parent
}

/// None when this is a leaf or has no child nodes.
/// Thin wrapper over nth_child(0).
pub fn SyntaxNode::first_child(self : SyntaxNode) -> SyntaxNode? {
  self.nth_child(0)
}

/// None when the subtree contains no tokens.
/// Scans children left-to-right; returns the first SyntaxToken found.
pub fn SyntaxNode::first_token(self : SyntaxNode) -> SyntaxToken? {
  for child in self.all_children() {
    match child {
      SyntaxElement::Token(t) => return Some(t)
      SyntaxElement::Node(_) => ()
    }
  }
  None
}

/// None when offset is outside this node's span.
/// Wraps find_at with an explicit span check so callers get a type-level
/// signal instead of the Layer 1 fallback (which returns self on bad input).
pub fn SyntaxNode::find_at_checked(
  self : SyntaxNode,
  offset : Int,
) -> SyntaxNode? {
  if offset < self.start() || offset >= self.end() {
    None
  } else {
    Some(self.find_at(offset))
  }
}
```

---

## Layer 3 — Error information

Both delegate to `CstNode::has_errors` which already exists and traverses
the green tree. `SyntaxNode` exposes these so callers do not need to reach
through `.cst_node()`.

```moonbit
/// True when this node's kind equals error_kind.
/// Does not traverse children — use contains_errors for subtree check.
pub fn SyntaxNode::is_error(self : SyntaxNode, error_kind : RawKind) -> Bool {
  self.kind() == error_kind
}

/// True when the subtree rooted at this node contains any error node
/// (kind == error_node_kind) or error token (kind == error_token_kind).
/// Delegates to CstNode::has_errors.
pub fn SyntaxNode::contains_errors(
  self : SyntaxNode,
  error_node_kind : RawKind,
  error_token_kind : RawKind,
) -> Bool {
  self.cst_node().has_errors(error_node_kind, error_token_kind)
}
```

---

## Testing

New tests in `seam/syntax_node_wbtest.mbt`:

| Test | Expected |
|------|----------|
| `parent()` on root | `None` |
| `parent()` on child node | `Some(parent_node)` |
| `first_child()` on leaf | `None` |
| `first_child()` on node with children | `Some(first_child_node)` |
| `first_token()` on empty node | `None` |
| `first_token()` on node with tokens | `Some(first_token)` |
| `find_at_checked()` with in-span offset | `Some(node)` |
| `find_at_checked()` with out-of-span offset | `None` |
| `find_at_checked()` vs `find_at()` fallback contrast | `None` vs `self` |
| `is_error()` on error-kind node | `true` |
| `is_error()` on normal node | `false` |
| `contains_errors()` on clean subtree | `false` |
| `contains_errors()` on subtree with error node | `true` |
| `contains_errors()` on subtree with error token | `true` |

---

## Approach

Single commit, two files:
1. `seam/syntax_node.mbt` — field `priv`, five new methods
2. `examples/lambda/src/term_convert.mbt` — one-line fix

Verification: `cd seam && moon test` passes; `cd examples/lambda && moon test`
passes; `moon info` shows clean interface diff (only additions to `.mbti`).

---

## References

- [../design.md](../design.md) — three-layer API model, Phase 1/2 boundary
- [rowan](https://github.com/rust-analyzer/rowan) — `covering_element` is total;
  `token_at_offset` is checked (returns enum)
