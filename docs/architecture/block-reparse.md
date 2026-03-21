# Block Reparse: Architecture

**Status:** Design
**Prerequisite:** Balanced RepeatGroup trees (Phase 2, merged)

---

## Overview

Block reparse is a fast path for incremental parsing. Instead of running the full reuse-cursor protocol on every grammar node, it identifies the smallest syntactic block containing the edit, re-lexes and re-parses just that block, and splices the result into the old tree.

Cost: O(block_size + depth), independent of document size.

This document describes the five properties a grammar must satisfy for block reparse to be correct, the API for grammar authors, and the framework's responsibilities.

---

## The Five Properties

Block reparse is correct when the grammar satisfies five properties. Each is independently testable.

### Property 1: Lexical Containment

The tokens within a reparseable node's text range are determinable from that text alone, without surrounding context.

Formally: if you extract bytes `[start, end)` from the source and re-lex them, you get the same tokens as the original lex produced for that range (plus a trailing EOF).

**Holds when:**
- Context-free lexing (no lexer state carried across boundaries)
- No multi-line tokens spanning the block boundary
- Token kind doesn't depend on surrounding tokens

**Fails when:**
- Heredocs (`<<EOF ... EOF`) — token extends beyond block
- Nested template strings (`` `${`${x}`}` ``) — lexer nesting state
- Significant indentation (Python) — indentation level is lexer state
- C++ `>>` — one token or two depends on template nesting

**Test:** For any reparseable node N in tree T:
```
lex(source[N.start : N.end]) == tokens_of(N) ++ [EOF]
```

### Property 2: Syntactic Independence

A grammar rule exists that can parse the block's text in isolation, producing the same tree structure as parsing it within the full document.

The rule's behavior must not depend on surrounding parse context — no inherited attributes, no context-dependent keyword interpretation within the block.

**Holds when:**
- `{}`-delimited blocks (Rust, C, Java, JavaScript)
- `()`-delimited groups
- Module-level item lists
- Any construct with explicit delimiters and a self-contained grammar rule

**Fails when:**
- Dangling-else ambiguity (depends on enclosing `if`)
- Context-dependent keywords (`async` changes `await` parsing)
- Python's significant whitespace (indentation determines block membership)
- Operator precedence that depends on context

**Test:** For any reparseable node N, edit E inside N:
```
block_reparse(tree, E).subtree(N) == full_reparse(apply(source, E)).subtree(N)
```

### Property 3: Structural Integrity Verification

There's a cheap (O(n) or better) check that the re-lexed text forms a complete, well-bounded syntactic unit. This check must reject edits that break the block's structural boundaries.

When the integrity check fails, block reparse falls through to full incremental reparse. This makes the check a **performance guard**, not a correctness requirement — false negatives (rejecting valid block reparses) are safe, false positives (accepting broken reparses) are bugs.

**Examples by delimiter style:**

| Delimiter | Integrity check |
|-----------|----------------|
| `{ ... }` | Bracket balance: count `{` and `}`, verify equal |
| `( ... )` | Parenthesis balance |
| `begin ... end` | Keyword matching |
| `let ... newline` | Starts with keyword, no unmatched parens |
| Indentation | Indentation level consistent with parent |

**Test:** For edits that break boundaries (delete a delimiter):
```
is_balanced(re_lex(damaged_text)) == false
```

### Property 4: Deterministic Block Discovery

Given an edit position, we can efficiently find the smallest reparseable ancestor node. The set of reparseable node kinds is fixed, finite, and known to the framework.

The algorithm: walk up the tree from the edit position, checking each ancestor against `is_reparseable`. Return the first match.

With balanced RepeatGroup trees, the ancestor walk is O(log n) for flat sibling lists, O(depth) for nested structures.

**Holds when:** A grammar declares upfront which node kinds are reparseable. The tree structure supports efficient ancestor traversal.

**Fails when:** Every node is potentially reparseable (unclear boundaries), or the "right" reparseable ancestor depends on the edit content.

**Test:**
```
find_reparseable_ancestor(tree, edit) returns the smallest
reparseable node strictly containing edit.range
```

### Property 5: Boundary Stability

An edit inside a block doesn't change the block's boundaries. The delimiters or markers that define the block are stable across the edit.

**Holds when:**
- Editing inside `{ ... }` doesn't move the `{` or `}`
- Editing a LetDef's value doesn't change the `let` keyword or trailing newline
- The edit is strictly interior to the block

**Fails when:**
- Editing a `"` changes string boundaries
- Editing a `}` changes block boundaries
- Editing a newline in Python changes indentation block membership

When boundary stability fails, the integrity check (Property 3) should detect it and reject the block reparse. This makes boundary instability a **performance concern** (more fallbacks to full reparse), not a correctness concern.

**Test:** For edits strictly inside a block (not touching delimiters):
```
reparseable_node(tree_before, edit).text_range ==
reparseable_node(tree_after, edit).text_range
```

---

## Property Satisfaction by Language Family

| Language | Lexical Containment | Syntactic Independence | Integrity Check | Block Discovery | Boundary Stability |
|----------|--------------------|-----------------------|-----------------|-----------------|-------------------|
| Rust / C / Java | Yes (`{}` blocks) | Yes (blocks are independent) | Bracket balance | `ITEM_LIST`, `BLOCK_EXPR` | Yes (delimiters explicit) |
| Lambda calculus | Yes (context-free lexer) | Partial (LetDef is independent, but no block delimiters) | Paren balance + keyword check | `SourceFile` | Mostly (newlines are boundaries) |
| Python | No (indentation is lexer state) | No (indentation determines block membership) | Indentation level check | Difficult | No (newlines change blocks) |
| Lisp / Scheme | Yes | Yes (`()` are self-contained) | Paren balance | Any `()` list | Yes |
| ML / Haskell | Partial (layout rule) | Partial (where/let blocks) | Keyword matching | `let ... in`, `where` | Partial |

---

## API

### Grammar Author Provides

```
BlockReparseSpec[T, K]
  is_reparseable : (RawKind) -> Bool
  get_reparser : (RawKind) -> ((ParserContext[T, K]) -> Unit)?
  is_balanced : (Array[TokenInfo[T]]) -> Bool
```

**`is_reparseable(kind)`** — returns true for node kinds that can be reparsed in isolation. Only "container" kinds (lists, blocks) should return true — not individual items. For Rust: `ITEM_LIST`, `BLOCK_EXPR`, `MATCH_ARM_LIST`. For lambda: `SourceFile`.

**`get_reparser(kind)`** — returns the parse function for a reparseable kind. This should be the **same grammar function** that produced the node originally, ensuring structural consistency. Returns `None` if the kind has no reparser (should not happen if `is_reparseable` returned true).

**`is_balanced(tokens)`** — structural integrity check on the re-lexed tokens. Returns false to reject the block reparse and fall through to full incremental reparse. Should be cheap — O(n) scan of the token array.

### Framework Provides

**`find_reparseable_ancestor(tree, edit, spec)`** — walks the old tree to find the smallest reparseable node whose text range contains the edit. Returns the node and its path from root (for splice).

**`reparse_block(tree, edit, source, spec)`** — orchestrates: find node → extract text → re-lex → integrity check → reparse → splice. Returns `None` to fall through.

**`CstNode::replace_child_at(index, new_child, ...)`** — path-copy splice: replace one child in an immutable CstNode, rebuild ancestors with updated `text_len`, `hash`, `token_count`, `has_any_error`.

**`merge_diagnostics(old, new, range, edit)`** — combines old diagnostics (offset-adjusted for edits outside the reparsed range) with new diagnostics (offset-adjusted from local to global positions).

**`tokenize_range(source, start, end)`** — public subrange tokenization (exposes existing private `tokenize_range_impl`).

### Integration Point

Block reparse is a **pre-check** before the existing incremental parse. In `ImperativeParser::edit()`:

```
Edit arrives
    │
    ├── block reparse spec provided?
    │       │
    │       yes → find_reparseable_ancestor(old_tree, edit)
    │              │
    │              ├── found → re-lex, is_balanced?
    │              │            │
    │              │            ├── yes → reparse, splice, return new tree
    │              │            └── no  → fall through
    │              └── not found → fall through
    │
    └── Fall through to existing incremental parse
        (ReuseCursor + try_reuse + balanced RepeatGroup)
```

The three strategies compose: block reparse handles the common case (small edit in one block), balanced RepeatGroup handles medium edits (reuse undamaged groups), and per-node reuse handles the rest.

---

## Prior Art

**rust-analyzer** (`crates/syntax/src/parsing/reparsing.rs`):
- Two-level strategy: token reparse → block reparse → full reparse
- Reparseable kinds: `BLOCK_EXPR`, `ITEM_LIST`, `VARIANT_LIST`, `MATCH_ARM_LIST`, etc.
- Integrity check: `is_balanced()` counts `{` and `}`
- Tree splice: rowan's `SyntaxNode::replace_with()` — O(depth) path copying
- Error handling: `merge_errors()` translates offsets across the splice

**Lezer** (CodeMirror 6):
- Fragment-based reuse rather than block reparse
- Balanced repeat nodes enable O(log n) fragment reuse
- No explicit block reparse — the per-node reuse with balanced trees is sufficient

**Tree-sitter:**
- Edit-based invalidation with subtree reuse
- No explicit block reparse
- Relies on grammar structure for reuse granularity

---

## References

- [rust-analyzer reparsing.rs](https://github.com/rust-lang/rust-analyzer/blob/master/crates/syntax/src/parsing/reparsing.rs)
- [rust-analyzer grammar.rs reparser()](https://github.com/rust-lang/rust-analyzer/blob/master/crates/parser/src/grammar.rs)
- [rowan SyntaxNode::replace_with](https://docs.rs/rowan/latest/rowan/api/struct.SyntaxNode.html)
- [Lezer system guide](https://lezer.codemirror.net/docs/guide/)
- `docs/plans/2026-03-21-incremental-parser-optimization-design.md` — Phase 3 design spec
