# Block Reparse Implementation — Design Spec

**Date:** 2026-03-22
**Status:** Draft
**Scope:** loom (framework), seam (CstNode splice), lambda (first consumer)
**Prerequisite:** Grammar extension (ParamList + BlockExpr) — merged

---

## Goal

Add a framework-level block reparse fast-path to loom's incremental parser. When an edit falls entirely inside a reparseable block (e.g., `{ ... }`), re-lex and re-parse only that block and splice the result into the old tree. Cost: O(block_size + depth), independent of document size.

Any grammar can opt in by providing a `BlockReparseSpec` — no per-language framework changes needed. JSON, YAML, Markdown, or any future grammar gets block reparse by implementing 3 functions.

---

## BlockReparseSpec API

Grammar authors provide a struct with 3 function fields:

```
pub struct BlockReparseSpec[T, K] {
  is_reparseable : (RawKind) -> Bool
  get_reparser : (RawKind) -> ((ParserContext[T, K]) -> Unit)?
  is_balanced : (Array[TokenInfo[T]]) -> Bool
}
```

**`is_reparseable(kind)`** — Returns true for node kinds that can be reparsed in isolation. Only "container" kinds with explicit delimiters should return true. Examples: `BlockExpr` (lambda), `BLOCK_EXPR` / `ITEM_LIST` (Rust-like), `Object` / `Array` (JSON).

**`get_reparser(kind)`** — Returns the parse function for a reparseable kind. This must be the same grammar function that produced the node originally (e.g., `parse_block_expr` for `BlockExpr`). Returns `None` for non-reparseable kinds.

**`is_balanced(tokens)`** — Structural integrity check on the re-lexed tokens. Returns false to reject the block reparse and fall through to normal incremental parse. For brace-delimited blocks: count `{` and `}`, verify equal. O(n) scan.

### Integration with Grammar

Added as an optional field on `Grammar` (`loom/src/grammar.mbt`):

```
pub struct Grammar[T, K, Ast] {
  // ... existing fields (spec, tokenize, fold_node, on_lex_error, error_token, prefix_lexer) ...
  block_reparse_spec : BlockReparseSpec[T, K]?  // NEW, default None
}
```

The `Grammar::new()` constructor (also in `grammar.mbt`) must be updated to accept `block_reparse_spec? : BlockReparseSpec[T, K]? = None` as an optional labelled parameter, defaulting to `None` for backward compatibility. All existing callers remain unchanged.

The `new_imperative_parser()` factory in `factories.mbt` must thread `grammar.block_reparse_spec` into the `incremental_parse` closure where the pre-check occurs.

Follows the existing struct-of-functions pattern used by `LanguageSpec[T, K]`. MoonBit traits don't support type parameters, so struct-of-functions is the established idiom for generic configuration in this codebase.

---

## Framework Infrastructure

### 1. find_reparseable_ancestor (loom)

```
fn find_reparseable_ancestor(
  tree : SyntaxNode,
  edit : Edit,
  is_reparseable : (RawKind) -> Bool,
) -> (SyntaxNode, Array[Int])?
```

- Start at `SyntaxNode::find_at(edit.start)`
- Walk up via `.parent()`
- Return first node where `is_reparseable(kind)` is true AND the edit is strictly interior (not touching the first or last byte of the node)
- Also returns the path (**physical** CstNode child indices from root to target) for splice
- Returns `None` if no reparseable ancestor found
- O(depth) — with balanced RepeatGroup trees, O(log n) for flat sibling lists

**"Strictly interior" check:** `edit.start > block.start()` AND `edit.new_end() < block.end() + edit.delta()`. The edit must not touch the opening or closing delimiter. This ensures boundary stability (Property 5).

**RepeatGroup-aware path computation:** `SyntaxNode::parent()` skips transparent RepeatGroup nodes, but `CstNode.children` includes them. The path must track **physical** child indices in the raw CstNode tree, not logical SyntaxNode indices. Implementation approach: after finding the reparseable ancestor via SyntaxNode walk, build the path by drilling **down** from the root CstNode to the target using `find_at`-style offset matching on `CstNode.children` directly. This correctly traverses through RepeatGroup levels and records physical indices at each step.

### 2. CstNode::with_replaced_child (seam)

```
fn CstNode::with_replaced_child(
  self,
  index : Int,
  new_child : CstElement,
  trivia_kind? : RawKind,
  error_kind? : RawKind,
  incomplete_kind? : RawKind,
) -> CstNode
```

- Creates a new CstNode with `children[index]` replaced by `new_child`
- Recomputes `text_len`, `hash`, `token_count`, `has_any_error` from the new children array
- Requires `trivia_kind`, `error_kind`, `incomplete_kind` for correct metadata computation (same parameters as `CstNode::new()`): `token_count` must exclude trivia tokens, `has_any_error` must check error/incomplete kinds
- Delegates to `CstNode::new(self.kind, new_children, trivia_kind~, error_kind~, incomplete_kind~)` internally — no need to duplicate the computation logic
- Pure function — original CstNode is unchanged (immutable)

### 3. splice_tree (loom or seam)

```
fn splice_tree(
  root : CstNode,
  path : Array[Int],
  new_node : CstNode,
) -> CstNode
```

- Applies `with_replaced_child` bottom-up along the path
- Each step creates a new ancestor with the replaced child
- Returns the new root CstNode
- O(depth) new CstNode allocations

### 4. reparse_block — Orchestrator (loom)

```
fn reparse_block[T, K](
  old_syntax : SyntaxNode,
  edit : Edit,
  new_source : String,
  spec : BlockReparseSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  language_spec : LanguageSpec[T, K],
  old_diagnostics : Array[Diagnostic[T]],
) -> (CstNode, Array[Diagnostic[T]])?
```

Flow:
1. `find_reparseable_ancestor(old_syntax, edit, spec.is_reparseable)` → `(block_node, path)` or `None`
2. Compute new block text range: `block_start = block_node.start()`, `block_end = block_node.end() + edit.delta()`
3. Extract `new_source[block_start..block_end]`
4. `tokenize(block_text)` — tokenize the substring as standalone source
5. `spec.is_balanced(tokens)` → if false, return `None`
6. **Parse the block in isolation.** Current `parse_tokens_indexed` always uses `spec.root_kind` as the wrapper — there is no root override parameter. To avoid modifying `parse_tokens_indexed`, create a **dedicated `parse_block` helper** that:
   - Creates a `ParserContext` from the block tokens (using `build_starts`, indexed closures, and the existing `LanguageSpec`)
   - Calls `spec.get_reparser(block_kind)(ctx)` directly
   - Calls `ctx.flush_trivia()` and builds the tree via `build_tree_fully_interned` with `root_kind = block_kind`
   - This produces `BlockExpr(BlockExpr(...))` — a double-wrapped tree

   **Note:** `parse_block_expr` is currently private in `cst_parser.mbt`. Either make it `pub` or introduce a `pub fn block_reparser(kind: RawKind) -> ((ParserContext) -> Unit)?` wrapper in the lambda grammar module that `BlockReparseSpec.get_reparser` returns.

7. **Unwrap the parse result:** Extract the inner node from the double-wrapped tree: take the first `Node` child from `result.children`, skipping trivia tokens. This yields the actual `BlockExpr` CstNode.

8. `splice_tree(old_syntax.cst_node(), path, unwrapped_block_cst)` → new root CstNode

9. **Merge diagnostics with offset adjustment:**
   - **Before block range** (`diag.end <= block_start`): keep as-is
   - **Inside block range**: discard old, replace with new block diagnostics offset-adjusted (`diag.start + block_start`, `diag.end + block_start`)
   - **After block range** (`diag.start >= old_block_end`): shift by `edit.delta()` (`diag.start + delta`, `diag.end + delta`)

10. Return `Some((new_root, merged_diagnostics))`

Returns `None` at any step to fall through to normal incremental parse.

---

## Integration Point

In `factories.mbt`'s `incremental_parse` closure, add block reparse as a pre-check **before** `TokenBuffer::update()`:

```
edit arrives
    │
    ├── block_reparse_spec provided?
    │       │
    │       yes → reparse_block(old_syntax, edit, new_source, spec, ...)
    │              │
    │              ├── Some((new_tree, diagnostics)) → return Tree(new_tree, 1)
    │              │
    │              └── None → fall through
    │
    └── Normal incremental parse (existing flow):
        update TokenBuffer → build ReuseCursor → parse_tokens_indexed
```

**Key property:** Block reparse tokenizes the substring independently, so the full `TokenBuffer` doesn't need updating if block reparse succeeds. This avoids the incremental re-lex cost.

If block reparse fails (returns `None`), the normal incremental path runs exactly as before. Zero overhead on the existing path — just one function call that returns `None`.

**Reuse count:** Block reparse returns `reuse_count = 1`, signaling "block reparse was used" for observability.

**TokenBuffer consistency:** When block reparse succeeds, the `TokenBuffer` is stale (it hasn't been updated with the edit). If the next edit falls through to normal incremental parse, `TokenBuffer::update(edit, source)` would apply an incremental update against stale state, producing incorrect results.

**Design decision:** After a successful block reparse, invalidate the TokenBuffer by setting `token_buf.val = None`. The existing factory code already handles `token_buf.val == None` by rebuilding from scratch. This means the first fallback after a block reparse is a full re-lex (not incremental), but this is correct and simple. The common case (consecutive block reparses) has zero TokenBuffer overhead.

---

## Lambda Grammar Implementation

### is_reparseable

```moonbit
fn(kind) { kind == @syntax.BlockExpr.to_raw() }
```

Only `BlockExpr`. `SourceFile` is the root — reparsing it is just a full reparse.

### get_reparser

```moonbit
fn(kind) {
  if kind == @syntax.BlockExpr.to_raw() {
    Some(parse_block_expr)
  } else {
    None
  }
}
```

Returns the existing `parse_block_expr` — the same function used during normal parsing.

### is_balanced

```moonbit
fn(tokens) {
  let mut depth = 0
  for token in tokens {
    if token.token == @token.LBrace { depth += 1 }
    if token.token == @token.RBrace { depth -= 1 }
    if depth < 0 { return false }
  }
  depth == 0
}
```

O(n) bracket balance scan.

### Wiring

Add `block_reparse_spec` to the existing `lambda_grammar`:

```moonbit
let lambda_grammar = Grammar::new(
  spec=lambda_spec,
  tokenize=...,
  fold_node=...,
  block_reparse_spec=Some(BlockReparseSpec {
    is_reparseable,
    get_reparser,
    is_balanced,
  }),
)
```

---

## Testing Strategy

### Correctness tests (lambda)

- Block reparse produces identical CstNode to full incremental reparse for edits inside blocks
- Property: `reparse_block(tree, edit, src) == incremental_parse(tree, edit, src)` for all edits strictly inside a BlockExpr
- Edits touching delimiters (`{` or `}`) fall through to normal incremental
- Nested blocks: edit in inner block reparses inner, not outer
- Empty block after edit (delete content inside `{ }`) — `is_balanced` succeeds (`{` and `}` match), block reparse succeeds, parser emits "Empty block expression" diagnostic. This is correct behavior.

### Edge cases

- Edit spans multiple blocks → falls through (edit not strictly inside one block)
- Edit at block boundary (touching `{` or `}`) → falls through
- Block with errors (missing `;`) → block reparse succeeds, diagnostics correct
- No reparseable ancestor found → falls through
- Document with no blocks → falls through (zero overhead)

### Performance test (benchmark)

- Single-def edit in 320-let file with blocks: block reparse should be O(block_size), not O(document_size)
- Compare reparse_block path vs full incremental path timing

### Framework tests (loom)

- `CstNode::with_replaced_child` — correct recomputation of text_len, hash, token_count, has_any_error
- `splice_tree` — path-copy produces structurally correct tree
- `splice_tree` through RepeatGroup — physical path indices correctly traverse transparent nodes
- `find_reparseable_ancestor` — finds correct block, returns None when edit crosses boundary
- Diagnostic offset adjustment — diagnostics after the edited block are shifted by `edit.delta()`
- TokenBuffer invalidation — block reparse sets `token_buf.val = None`, subsequent non-block edit rebuilds TokenBuffer correctly
- Unwrap correctness — double-wrapped tree (`root(BlockExpr(...))`) yields correct inner BlockExpr

---

## Scope & Deliverables

**Single PR** covering framework (loom/seam) and lambda implementation:

| Module | Change |
|--------|--------|
| seam | `CstNode::with_replaced_child` |
| loom/core | `BlockReparseSpec` struct |
| loom/core or loom/incremental | `find_reparseable_ancestor`, `splice_tree`, `reparse_block` |
| loom/factories | Pre-check integration in `incremental_parse` closure |
| loom/grammar | Optional `block_reparse_spec` field on `Grammar` |
| lambda | `is_reparseable`, `get_reparser`, `is_balanced`, wiring, tests |

**Out of scope:**
- `tokenize_range` API — use `tokenize(substring)` instead (see memory: project_tokenize_range.md)
- Other reparseable kinds beyond `BlockExpr`
- `SourceFile`-level block reparse (that's just a full reparse)
- Diagnostic merging edge cases for overlapping edits (single-edit model only)

---

## References

- `docs/architecture/block-reparse.md` — Five properties, API design, prior art
- Canopy repo `docs/plans/2026-03-21-incremental-parser-optimization-design.md` — Phase 3 design (in parent monorepo, not this submodule)
- [rust-analyzer reparsing.rs](https://github.com/rust-lang/rust-analyzer/blob/master/crates/syntax/src/parsing/reparsing.rs) — Prior art
