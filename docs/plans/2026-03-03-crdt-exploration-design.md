# Design: CRDT Exploration

**Created:** 2026-03-03
**Status:** Approved

## Goal

Connect the incremental parser to a text CRDT (event-graph-walker) and verify that two
peers applying the same logical edits converge to identical parse trees.

## What Is Already Done

- `TextDelta (Retain|Insert|Delete)` enum — `loom/src/core/delta.mbt`
- `to_edits(Array[TextDelta]) -> Array[Edit]` — same file
- `ImperativeParser.edit(Edit, new_source)` — `loom/src/incremental/imperative_parser.mbt`

## Approach

Minimal footprint (Approach A): no new packages. Three sequential phases, each
independently testable.

```
TextDelta (Retain|Insert|Delete)     ← already done
  ↓ to_edits()
Edit { start, old_len, new_len }
  ↓ ImperativeParser.edit()
CstNode (new tree)
  ↓ tree_diff(old, new)
Array[Edit]   ← changed subtrees as edit spans
```

---

## Phase 1: Green Tree Diff

**File:** `loom/src/core/diff.mbt`

### API

```moonbit
pub fn tree_diff(old : @seam.CstNode, new : @seam.CstNode) -> Array[Edit]
```

Returns the minimal set of `Edit` records describing what changed between two parse
trees. Uses the existing `Edit` type — no new struct needed.

### Algorithm

Simultaneous walk with `CstNode.hash` as O(1) skip key:

1. If `old.hash == new.hash` → return `[]` immediately (entire subtree unchanged)
2. If `old.kind != new.kind` OR child counts differ → emit one `Edit` covering the whole
   node pair; do not recurse
3. Otherwise (same kind, same child count) → walk children pairwise, accumulating
   `old_pos` via `child.text_len()`, recursing into Node pairs

Token-level changes surface when the recursive walk reaches a mismatched `CstToken`
pair at a leaf.

### Why `Edit` not a new `DiffEntry`

`Edit { start, old_len, new_len }` already captures "position of change, how many old
bytes, how many new bytes". Creating a `DiffEntry` with the same fields would be
duplicate type. The diff output can flow directly back into `ImperativeParser.edit()`.

### File footprint

| File | Change |
|------|--------|
| `loom/src/core/diff.mbt` | New — `tree_diff` function |
| `loom/src/core/diff_test.mbt` | New — unit tests |

---

## Phase 2: Simulated Two-Peer Convergence Test

**File:** `examples/lambda/src/crdt_peer_test.mbt`

### Peer model

Each peer is a plain struct:

```moonbit
struct Peer {
  mut text   : String
  parser     : ImperativeParser[@ast.Term]
}
```

`apply(delta)`: `to_edits(delta)` → string surgery on `text` → `parser.edit()` for
each resulting `Edit`.

### Convergence scenario

```
Peer A types "λx. x"   → delta_a = [Insert("λx. x")]
Peer B types " + 1"    → delta_b = [Retain(4), Insert(" + 1")]

A merges B's delta: text → "λx. x + 1"
B merges A's delta: text → "λx. x + 1"

assert peer_a.text == peer_b.text
assert peer_a.parser.cst() == peer_b.parser.cst()
```

The key assertion is CST structural equality (`CstNode.Eq`): if two peers converge to
the same text and produce structurally identical parse trees, the
`TextDelta → to_edits → parser.edit` pipeline is sound.

### File footprint

| File | Change |
|------|--------|
| `examples/lambda/src/crdt_peer_test.mbt` | New — convergence test |

---

## Phase 3: event-graph-walker Integration Demo

**File:** `examples/lambda/src/crdt_egw_test.mbt`

### Bridging: SyncMessage → TextDelta

`SyncSession.apply(message)` merges remote ops and updates `TextDoc.text()` but emits
no `TextDelta`. Bridge: snapshot text before applying, diff strings after.

New helper in `loom/src/core/delta.mbt`:

```moonbit
pub fn text_to_delta(old : String, new : String) -> Array[TextDelta]
```

Algorithm: find common prefix length `p` and common suffix length `s`, emit:

```
[Retain(p), Delete(old_len - p - s), Insert(new[p..new_len-s])]
```

Handles any single contiguous change (the common CRDT case) with no LCS required.

### Integration scenario

```
peer_a = EgwPeer { doc: TextDoc("a"), parser: ImperativeParser }
peer_b = EgwPeer { doc: TextDoc("b"), parser: ImperativeParser }

peer_a.doc.insert(0, "λx. x")
peer_b.doc.insert(0, " + 1")

msg_a = peer_a.doc.sync().export_all()
msg_b = peer_b.doc.sync().export_all()

peer_a.bridge_sync(msg_b)   // text_to_delta → to_edits → parser.edit
peer_b.bridge_sync(msg_a)

assert peer_a.doc.text() == peer_b.doc.text()
assert peer_a.parser.cst() == peer_b.parser.cst()
```

`bridge_sync(message)`:
1. `old_text = self.doc.text()`
2. `self.doc.sync().apply(message)`
3. `new_text = self.doc.text()`
4. `delta = text_to_delta(old_text, new_text)`
5. `edits = to_edits(delta)`
6. For each edit: `self.parser.edit(edit, new_text)` (with intermediate source updates)

### Cross-module dependency

`examples/lambda` must declare `event-graph-walker` as a dependency in its
`moon.mod.json`. This is the only structural change outside source files.

### File footprint

| File | Change |
|------|--------|
| `loom/src/core/delta.mbt` | Add `text_to_delta` helper |
| `loom/src/core/delta_test.mbt` | Add `text_to_delta` tests |
| `examples/lambda/src/crdt_egw_test.mbt` | New — event-graph-walker integration demo |
| `examples/lambda/moon.mod.json` | Add `event-graph-walker` dependency |

---

## Exit Criteria

- `tree_diff` tested: unchanged subtrees return `[]`; leaf change returns one `Edit`;
  node kind change returns one `Edit` for the whole node
- `text_to_delta` tested: pure insert, pure delete, replace, no-op (identical strings)
- Simulated peer convergence test passing: both peers produce same text and same CST
- event-graph-walker integration demo passing: same convergence property with real CRDT ops
- `moon test` clean across all affected modules
- `bash check-docs.sh` clean
