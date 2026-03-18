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
Tree edit:  TreeEditOp → compute_text_delta(op, source_map, flat_proj) → TextDelta → CRDT → reparse → projection updates
```

Both editing modes converge at `TextDelta → CRDT`. The text CRDT is the single source of truth. The incremental parser keeps the projection up to date after either kind of edit.

The ProjNode tree becomes **read-only** — a projection derived from text, never mutated directly.

### `compute_text_delta`

```moonbit
pub fn compute_text_delta(
  op : TreeEditOp,
  source_map : SourceMap,
  flat_proj : FlatProj,
) -> Array[TextDelta]
```

Pure function. Reads current projection state, produces text deltas. Never mutates the projection.

**Edit operations and their text deltas:**

| Operation | Text Delta |
|-----------|------------|
| Insert def (name, init_text, after_index) | `Retain(insert_offset)` + `Insert("\nlet name = init_text")` |
| Delete def (index) | `Retain(start)` + `Delete(end - start)` |
| Modify init (index, new_text) | `Retain(init_start)` + `Delete(old_len)` + `Insert(new_text)` |
| Rename binding (index, new_name) | `Retain(name_start)` + `Delete(old_len)` + `Insert(new_name)` |
| Insert final expr (text) | `Retain(end)` + `Insert("\ntext")` |
| Delete final expr | `Retain(start)` + `Delete(len)` |
| Reorder defs (old_idx, new_idx) | Delete at old position + Insert at new position |

Position computation uses the source map (`NodeId → (start, end)`) and `FlatProj.defs[i].2` for def-level positions.

### What Changes

**`tree_edit_bridge.mbt`:** Rewired from "apply edit to ProjNode → extract FlatProj → unparse → seed → CRDT" to "compute delta → CRDT". Most of the file is replaced.

**Removed from production code:**
- `apply_edit_to_proj` — ProjNode is now read-only
- `from_proj_node` — no roundtrip needed
- The `seed_flat_proj` mechanism in `tree_edit_bridge.mbt`

**Unchanged:**
- Parsing path: `text → parse → CST → to_flat_proj → reconcile_flat_proj → to_proj_node`
- `reconcile_flat_proj`, `reconcile_ast` — reconciliation logic
- `to_flat_proj`, `to_proj_node` — projection building
- Source map, registry — node lookup
- Reactive memo pipeline in `projection_memo.mbt`
- `print_flat_proj` — kept as utility, removed from edit hot path
- The incremental parser / loom framework
- The CRDT (eg-walker) integration

### FlatProj's New Role

FlatProj becomes a **read-only view coordinator**:

| Role | Before | After |
|------|--------|-------|
| Reconciliation container | Used | **Unchanged** |
| ProjNode factory (to_proj_node) | Used | **Unchanged** |
| Edit result container (from_proj_node) | Used | **Removed** |
| Text renderer (print_flat_proj) in edit path | Used | **Removed from edit path** |

`compute_text_delta` *reads* the current FlatProj for def positions/ordering but doesn't write to it. The next parsing cycle produces a fresh FlatProj from the updated text.

## Migration Path

Migration is incremental — one edit operation at a time. **Benchmark between each phase.**

### Phase 1: First operation + baseline

Implement `compute_text_delta` for "modify init" (simplest operation). Wire through `tree_edit_bridge.mbt` as an alternative path alongside the existing `apply_edit_to_proj` path.

**Benchmark:** Measure edit→text→reparse cycle latency for both old path (ProjNode mutate → unparse → reparse) and new path (text delta → reparse). Establish baseline.

### Phase 2: Migrate remaining operations

Migrate each operation one by one. Each gets a `compute_text_delta` case and a differential test against the old path.

**Benchmark after each op migration:** Track whether any op is slower via the new path. Compare against Phase 1 baseline.

### Phase 3: Remove old path + cleanup

Remove `apply_edit_to_proj`, `from_proj_node` (production usage), the seed-FlatProj logic.

**Benchmark the cleanup:** Removing dead code and allocation paths. Measure memory and latency improvements.

### Benchmark metrics per phase

- Edit-to-text latency (compute_text_delta time)
- Reparse latency (incremental parser time after delta)
- Total round-trip time (edit op → projection updated)
- Peak allocation

## Testing Strategy

- **Differential oracle:** For each edit op, apply via old path AND new path. Assert text results are identical. Catches regressions during migration.
- **Round-trip property:** Apply edit → get new text → reparse → verify ProjNode structure matches expected change.
- **CRDT integration:** Apply edit on two peers, merge, verify convergence. Existing CRDT tests cover this once edits produce text deltas.
- **Source map correctness:** After edit + reparse, verify source map positions are consistent with new text.

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
- [Sapling (Meta)](https://github.com/nickel-org/nickel) — structural editor using text-as-source-of-truth with direct text diffs
- [tree_edit_bridge.mbt](../../editor/tree_edit_bridge.mbt) — current edit path (to be replaced)
- [projection_memo.mbt](../../editor/projection_memo.mbt) — parsing path (unchanged)
