# text-change

`TextChange` represents either one exact half-open UTF-16 replacement or a complete text replacement. `compute_text_change(old, new)` derives one grapheme-aligned `ReplaceRange`; callers that already know a complete replacement construct `ReplaceAll` directly.

The module is intentionally independent of parsers, CRDTs, and UI code. It lives in the Loom monorepo (migrated from Canopy in 2026-05, #147), and its primary consumers are in the Canopy repository.

## Public interface

- `TextChange::ReplaceRange(start~, delete_len~, inserted~)` — one exact half-open UTF-16 replacement
- `TextChange::ReplaceAll(String)` — adopt one complete replacement without claiming an exact range
- `TextChange::apply(self, source) -> String?` — apply the change, rejecting invalid or surrogate-splitting ranges
- `TextChange::is_noop(self) -> Bool` — true only for an empty `ReplaceRange`
- `compute_text_change(old, new) -> TextChange` — derive one grapheme-aligned `ReplaceRange`

## Consumers

Canopy's editor uses `compute_text_change` for tree-edit round trips and projection splice translation. Loom uses it for text deltas and projection-identity fallback alignment. Browser editors can construct either variant directly when they already have the corresponding operation.

## Dependencies

`dowdiness/moji` provides UAX #29 grapheme boundaries for `compute_text_change`.

## Stability

The module is internal to the repositories that consume it. Changes to the enum require an atomic Loom and Canopy consumer migration; compatibility aliases are not retained.

## Notes

`compute_text_change` derives one contiguous replacement rather than a Myers-style multi-edit diff. It never returns `ReplaceAll`. `ReplaceAll` is reserved for callers that have a complete replacement but no exact range.
