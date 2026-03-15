# Incremental Parser Overhead: Low-Hanging-Fruit Waste Elimination

**Status:** Implemented; benchmarked on flat-grammar parser benchmarks.

**Context:** Incremental parsing is slower than full reparse on right-recursive let chains (320-deep). This document records actionable waste elimination opportunities found during investigation.

**Related:** [ADR: physical_equal interner](../decisions/2026-03-14-physical-equal-interner.md) (O(n^2) interner fix)

---

## Finding 1: `buffer.update()` returns unnecessary copy — **Resolved**

`TokenBuffer::update` returned `Array[TokenInfo[T]]` via `self.tokens.copy()`, creating an O(n) copy per edit. Changed to return `Unit`. All call sites updated to use `buffer.get_tokens()` when needed.

## Finding 2: `collect_old_tokens` walks entire old CST upfront — **Resolved**

`ReuseCursor::new` eagerly called `collect_old_tokens`, flattening the entire old CST. Replaced with a lazy `OldTokenCache` shared across snapshots — the table is built once on first `trailing_context_matches` call and reused across speculative branches.

## Finding 3: `emit_reused` serializes then deserializes reused nodes — **Resolved**

Added `ReuseNode(CstNode)` variant to `ParseEvent`. Reused subtrees are attached directly via a single event instead of recursively emitting StartNode/Token/FinishNode. `build_tree_fully_interned` re-interns the node through `NodeInterner` (O(1) cache hit for already-interned nodes).

---

## Benchmark Summary (2026-03-15)

Key incremental benchmarks, before vs after (lambda module, `moon bench --release`):

| Benchmark | Before | After | Change |
|-----------|--------|-------|--------|
| phase3: cursor reuse, edit at end (110 tok) | 40.04 µs | 33.79 µs | -16% |
| phase3: cursor reuse, edit at start (110 tok) | 34.01 µs | 30.94 µs | -9% |
| phase4: nested let body - multiple reused | 4.05 µs | 3.63 µs | -10% |
| scale: 100 terms - incremental single edit | 148.98 µs | 131.83 µs | -12% |
| scale: 500 terms - incremental single edit | 829.47 µs | 750.24 µs | -10% |
| scale: 1000 terms - incremental single edit | 1.84 ms | 1.63 ms | -11% |
| heavy: typing session - 100 edits at end | 5.02 ms | 3.29 ms | -34% |
| heavy: typing session - 100 edits in middle | 6.26 ms | 5.29 ms | -15% |

---

## Fundamental Limitation: Right-Recursive Grammars

Right-recursive grammars with tail edits are worst-case for incremental parsing:

- Every spine node overlaps the damage range, so only leaf nodes can be reused.
- Leaf nodes (IntLiteral, VarRef) are trivially cheap to parse — reuse overhead exceeds savings.
- The correct fix for the editor is switching to a flat grammar structure (`source_file_grammar` with `LetDef*`), not optimizing the reuse protocol.
