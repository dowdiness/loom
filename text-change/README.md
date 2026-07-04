# text-change

`compute_text_change(old, new) -> TextChange` — diff two strings into a single half-open splice (`start`, `delete_len`, `inserted`). Grapheme-aware: the diff respects extended grapheme clusters via [`moji`](../moji/), so combining marks, emoji ZWJ sequences, and regional indicators are never split.

This module is a "minimal text diff": intentionally tiny, with no opinion about how the resulting splice is then applied to a CRDT or buffer. It lives in the loom monorepo (migrated from canopy in 2026-05, #147); its primary consumers are in the canopy repository.

## Public API

- `TextChange { start : Int, delete_len : Int, inserted : String }` — half-open replacement
- `TextChange::is_noop(self) -> Bool` — true when both sides are empty
- `compute_text_change(old : String, new : String) -> TextChange` — the single diff entry point

## Consumers

canopy's `editor` module (computes edits for tree-edit round-trip and FlatProj splice translation). Used indirectly by every editor host.

## Dependencies

`dowdiness/moji` — UAX #29 grapheme boundaries, for cluster-safe splice alignment.

## Stability

Internal but stable — the `TextChange` shape is consumed by canopy's editor tree-edit path. Field renames would propagate up through canopy's `editor/` and into its `protocol/` `ViewPatch::TextChange`.

## Notes

The diff is single-splice (one contiguous delete + insert), not Myers-style multi-edit. That keeps it cheap and matches how the editor's downstream consumers expect to apply it. Callers expecting multi-edit diffs should chain multiple `compute_text_change` calls instead.
