# Projectional Edit via Text Delta — Design Document

**Date:** March 18, 2026
**Status:** Draft
**Scope:** `editor/` and `projection/` (parent crdt repo)

## Goal

Eliminate the lossy ProjNode → FlatProj → text roundtrip in the tree edit path. Structural edits produce text deltas directly, converging with text editing on a single `TextDelta → CRDT → reparse` pipeline.

## Problem

The current tree edit path:

```
TreeEditOp → apply_edit_to_proj(ProjNode) → from_proj_node → print_flat_proj → text → CRDT
```

Has two issues introduced by the `Term::Module` refactoring:

1. **Identity loss:** `from_proj_node` uses init child `node_id` as def identity. Editing an init changes the def's NodeId, causing unnecessary ID churn in reconciliation.
2. **Span shift:** `from_proj_node` uses `init_child.start` for def start position, but the real start is the `let` keyword. Roundtripping shifts the Module's start span.

These are symptoms of a deeper architectural problem: **any structure → text → structure cycle loses identity.** Fixing `from_proj_node` moves the problem; eliminating the roundtrip solves it.

## Design

### New Architecture

```
Text edit:  keystroke → TextDelta → CRDT → reparse → projection updates
Tree edit:  TreeEditOp → compute_text_delta(op, source_map, source_text) → TextDelta → CRDT → reparse → projection updates
```

Both editing modes converge at `TextDelta → CRDT`. The text CRDT is the single source of truth. The incremental parser keeps the projection up to date after either kind of edit.

The ProjNode tree becomes **read-only** — a projection derived from text, never mutated directly.

### Core Insight: All Ops Reduce to Span Replacements

Every structural edit is a **text span replacement**: replace the text at `source_text[start:end]` with new text. The span comes from the source map. The replacement text is computed per operation.

```moonbit
pub fn compute_text_delta(
  op : TreeEditOp,
  source_text : String,
  source_map : SourceMap,
  registry : Map[NodeId, ProjNode],
) -> Result[Array[TextDelta], String]
```

Pure function. Reads current projection state and source text, produces text deltas. Never mutates the projection.

### Edit Operation Classification

#### Category 1: Replace-in-place (node span → new text)

These replace a node's source span with computed replacement text.

**CommitEdit(node_id, new_value):**
- Span: `source_map.get(node_id) → (start, end)`
- Replacement: `new_value` (user-provided text)
- Delta: `Retain(start) + Delete(end - start) + Insert(new_value)`
- The parser handles validation on reparse — if `new_value` is malformed, error recovery produces an error node. This is more consistent than the current approach which parses `new_value` independently and splices the result.

**Delete(node_id):**
- Span: `source_map.get(node_id) → (start, end)`
- Replacement: `placeholder_text_for_kind(node.kind)`
- Delta: `Retain(start) + Delete(end - start) + Insert(placeholder)`
- Special case: deleting a child of an error node removes the child entirely (delete span, no placeholder).

**WrapInLambda(node_id, var_name):**
- Span: `source_map.get(node_id) → (start, end)`
- Existing text: `source_text[start:end]`
- Replacement: `"(λ" + var_name + ". " + existing_text + ")"`
- Delta: `Retain(start) + Delete(end - start) + Insert(replacement)`
- Note: wrapping in parens ensures correct precedence regardless of context. The current code uses `print_term(existing.kind)` which normalizes formatting; using the source slice preserves user formatting. Both are valid — source-slice is preferred for a projectional editor (preserves user intent).

**WrapInApp(node_id):**
- Span: `source_map.get(node_id) → (start, end)`
- Existing text: `source_text[start:end]`
- Replacement: `"(" + existing_text + ") a"`
- Delta: `Retain(start) + Delete(end - start) + Insert(replacement)`

#### Category 2: Insertion (compute position, insert text)

**InsertChild(parent, index, kind):**
- Parent span: `source_map.get(parent) → (parent_start, parent_end)`
- Insertion position depends on parent kind and index:
  - **Module parent (flat defs):** Insert between defs. Position = `defs[index].start` (before the target def) or end of `defs[index-1]` (after the previous def). Inserted text: `"\nlet x = " + placeholder_text_for_kind(kind)` or just `"\n" + placeholder_text_for_kind(kind)` for final expressions.
  - **Other parents (App, Bop, If, Lam):** These have fixed arity. InsertChild for these is structurally constrained and may need to restructure the node. The replacement text for the entire parent node can be computed via `print_term` with the new child inserted.
- The FlatProj defs array provides positions for Module children. For other node types, child positions are derivable from the source map (children have their own NodeIds and spans).

#### Category 3: Move (delete + insert)

**Drop(source, target, position):**
- Source span: `source_map.get(source) → (src_start, src_end)`
- Source text: `source_text[src_start:src_end]`
- Target position: computed from `source_map.get(target)` and `position` (Before/After/Inside)
- Two deltas applied in order:
  1. Delete source span (with delimiter cleanup — consume preceding or following newline/whitespace)
  2. Insert source text at target position (with appropriate delimiter)
- Position adjustment: if target is after source in the document, the target position shifts left by `src_end - src_start` after the deletion. Compute both positions first, then emit deltas in document order.

#### No-op operations (produce empty delta)

`Select`, `SelectRange`, `StartEdit`, `CancelEdit`, `StartDrag`, `DragOver`, `Collapse`, `Expand` — return `Ok([])`.

### Trivia and Delimiter Handling

The parser treats newlines as real top-level delimiters for `LetDef` items. Structural edits must handle delimiters correctly:

**Rules:**
1. **Inserting a def:** Prefix with `\n` to ensure a newline delimiter before the new `let`.
2. **Deleting a def:** Delete from the def's `let` keyword to the start of the next def (or end of file). This consumes the trailing newline.
3. **Inserting at end:** Prefix with `\n` if there's preceding content.
4. **Empty document:** No delimiter needed.

**Position sources:**
- `FlatProj.defs[i].2` gives the `let` keyword start for each def (from `to_flat_proj`, which reads CST `child.start()`).
- `source_map.get(node_id)` gives node spans for any ProjNode.
- Def end position: `defs[i+1].2` (next def's start) or end of file for the last def.

### Error Recovery Handling

**Principle:** `compute_text_delta` operates on text positions, not on tree structure. Error nodes have valid spans in the source map. The replacement text is just text — the parser handles recovery on reparse.

**Specific cases:**
- **CommitEdit on error node:** Replace error span with user text. Parser re-recovers.
- **Delete error node:** Replace with placeholder. If the error node is a child of another error node, remove entirely (delete span, no placeholder).
- **WrapInLambda on error node:** Wrap the error span's source text. Reparsing may produce a different structure — that's fine, the parser is authoritative.
- **InsertChild into node with error children:** Compute position from source map. The error children have spans; position computation works the same.

**Fallback:** If `source_map.get(node_id)` returns None (node not in map), return `Err("Node not found")`. This matches the current error handling.

### CRDT Concurrency Semantics

Structural edits are resolved to text deltas **locally** before broadcast. Two peers editing "the same def" from different snapshots produce independent text deltas that merge via the text CRDT's convergence rules.

**Guarantee:** Text convergence (identical text after merge). This is the text CRDT's guarantee.

**Non-guarantee:** Structural intent preservation. If peer A renames def 0 and peer B wraps def 0's init in a lambda, the merge produces valid text, but the resulting structure may not match either peer's intent. This is acceptable — the same limitation exists for concurrent text edits. Stronger structural intent preservation would require a tree CRDT, which is out of scope.

### What Changes

**`tree_edit_bridge.mbt`:** Rewired from "apply edit to ProjNode → extract FlatProj → unparse → seed → CRDT" to "compute delta → CRDT". Most of the file is replaced.

**Removed from production code:**
- `apply_edit_to_proj` — ProjNode is now read-only
- `from_proj_node` — no roundtrip needed
- The `seed_flat_proj` mechanism in `tree_edit_bridge.mbt`
- `update_node_in_tree`, `remove_child_at`, `insert_child_at`, `find_parent_recursive` — tree mutation helpers

**Unchanged:**
- Parsing path: `text → parse → CST → to_flat_proj → reconcile_flat_proj → to_proj_node`
- `reconcile_flat_proj`, `reconcile_ast` — reconciliation logic
- `to_flat_proj`, `to_proj_node` — projection building
- Source map, registry — node lookup
- Reactive memo pipeline in `projection_memo.mbt`
- `print_flat_proj` — kept as utility, removed from edit hot path
- The incremental parser / loom framework
- The CRDT (eg-walker) integration
- `placeholder_text_for_kind` — still used for delete placeholders and insertions

### FlatProj's New Role

FlatProj becomes a **read-only view coordinator**:

| Role | Before | After |
|------|--------|-------|
| Reconciliation container | Used | **Unchanged** |
| ProjNode factory (to_proj_node) | Used | **Unchanged** |
| Edit result container (from_proj_node) | Used | **Removed** |
| Text renderer (print_flat_proj) in edit path | Used | **Removed from edit path** |
| Position provider for def-level edits | N/A | **New** (compute_text_delta reads defs for positions) |

`compute_text_delta` *reads* FlatProj for def positions/ordering but doesn't write to it. The next parsing cycle produces a fresh FlatProj from the updated text.

## Migration Path

Migration is incremental — one edit operation at a time. **Benchmark between each phase.**

### Phase 1: CommitEdit + baseline

Start with `CommitEdit` — the simplest real operation. It's a direct span replacement: `source_map.get(node_id) → (start, end)`, replace with `new_value`. No position computation or delimiter handling needed.

Wire through `tree_edit_bridge.mbt` as an alternative path alongside the existing `apply_edit_to_proj` path.

**Differential test:** Apply via old path AND new path. Compare resulting text. Note: the new path may produce slightly different text than the old path because the old path re-parses `new_value` independently (which may normalize it), while the new path inserts `new_value` literally. Document when divergence is expected vs. unexpected.

**Benchmark:** Measure edit→text→reparse cycle latency for both paths. Establish baseline.

### Phase 2: Migrate remaining ops one by one

Order by complexity:
1. `Delete` (span replacement with placeholder)
2. `WrapInLambda`, `WrapInApp` (span replacement with computed text)
3. `InsertChild` (position computation + insertion)
4. `Drop` (two-position computation + move)

Each gets a `compute_text_delta` case and differential testing.

**Benchmark after each op migration.** Track whether any op is slower via the new path.

### Phase 3: Remove old path + cleanup

Remove `apply_edit_to_proj`, `from_proj_node` (production usage), `update_node_in_tree`, `remove_child_at`, `insert_child_at`, `find_parent_recursive`, the seed-FlatProj logic.

**Benchmark the cleanup.** Measure memory and latency improvements.

### Benchmark metrics per phase

- Edit-to-text latency (compute_text_delta time)
- Reparse latency (incremental parser time after delta)
- Total round-trip time (edit op → projection updated)
- Peak allocation

## Testing Strategy

- **Differential oracle:** For each edit op, apply via old path AND new path. Assert text results match (with documented exceptions for normalization differences).
- **Round-trip property:** Apply edit → get new text → reparse → verify ProjNode structure matches expected change.
- **CRDT integration:** Apply edit on two peers, merge, verify text convergence. Structural intent is not guaranteed — document this.
- **Source map correctness:** After edit + reparse, verify source map positions are consistent with new text.
- **Error recovery:** Apply edits targeting error nodes. Verify the edit produces valid text deltas and the parser re-recovers gracefully.
- **Delimiter correctness:** Insert/delete defs, verify no double newlines, no missing newlines, correct layout at file boundaries.

## What This Does NOT Change

- The incremental parser / loom framework
- The CST, SyntaxNode, Term types
- The CRDT (eg-walker) integration
- `reconcile_flat_proj` / `reconcile_ast` reconciliation
- The reactive memo pipeline in `projection_memo.mbt`
- Any loom submodule code

## References

- [FlatProj lossy roundtrip issue](../../ROADMAP.md) — ROADMAP TODO item that motivated this design
- [Term::Module design](../archive/completed-phases/2026-03-18-flat-ast-module-variant.md) — the refactoring that exposed the roundtrip problem
- [tree_lens.mbt](../../projection/tree_lens.mbt) — current TreeEditOp enum and apply_edit_to_proj
- [tree_edit_bridge.mbt](../../editor/tree_edit_bridge.mbt) — current edit path (to be replaced)
- [projection_memo.mbt](../../editor/projection_memo.mbt) — parsing path (unchanged)
- [source_map.mbt](../../projection/source_map.mbt) — NodeId → span mapping
