# Incremental Parser Overhead: Low-Hanging-Fruit Waste Elimination

**Context:** Incremental parsing is slower than full reparse on right-recursive let chains (320-deep). This document records actionable waste elimination opportunities found during investigation.

**Related:** [ADR: physical_equal interner](../decisions/2026-03-14-physical-equal-interner.md) (O(n^2) interner fix)

---

## Finding 1: `buffer.update()` returns unnecessary copy

**File:** `loom/src/core/token_buffer.mbt`, line 282

`self.tokens.copy()` creates an O(n) copy of the entire token array on every call. The caller in `factories.mbt:97` discards the return value (`let _ = buffer.update(...)`).

**Fix:** Change return type to `Unit`, or make the copy opt-in.

**Impact:** Eliminates ~2560 token copies per edit (~20us estimated).

## Finding 2: `collect_old_tokens` walks entire old CST upfront

**File:** `loom/src/core/reuse_cursor.mbt`, lines 64-87

`ReuseCursor::new` calls `collect_old_tokens`, which recursively walks the entire old CST to flatten non-trivia tokens into `Array[OldToken]`. For 320 lets this means ~2000 OldToken allocations plus an O(n) tree walk, all before parsing begins — even when most of the tree overlaps the damage range and cannot be reused.

**Fix:** Lazy computation. Only collect old tokens on demand during `trailing_context_matches`, or use the old TokenBuffer directly for follow-token lookups.

**Impact:** Eliminates O(n) upfront allocation and tree walk.

## Finding 3: `emit_reused` serializes then deserializes reused nodes

**File:** `loom/src/core/parser.mbt`, lines 740-780

For each reused node, `emit_node_events` recursively walks the subtree to emit StartNode/Token/FinishNode events, then `build_tree_fully_interned` reconstructs the CstNode from those events. This serialize-then-deserialize round-trip costs more than just parsing small subtrees from scratch.

**Fix:** Add a `ReuseNode(CstNode)` event type so `build_tree_fully_interned` can attach the canonical CstNode directly as a child without the event round-trip.

**Impact:** Significant for large reusable subtrees; marginal for leaf-only reuse (let-chain case).

---

## Fundamental Limitation: Right-Recursive Grammars

Right-recursive grammars with tail edits are worst-case for incremental parsing:

- Every spine node overlaps the damage range, so only leaf nodes can be reused.
- Leaf nodes (IntLiteral, VarRef) are trivially cheap to parse — reuse overhead exceeds savings.
- The correct fix for the editor is switching to a flat grammar structure (`source_file_grammar` with `LetDef*`), not optimizing the reuse protocol.
