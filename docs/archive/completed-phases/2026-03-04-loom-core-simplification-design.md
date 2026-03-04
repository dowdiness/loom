# loom/core — Simplification Design

**Status:** Complete

This document records the design principles for the `loom` parser framework's
internal implementation and the three targeted changes that apply them.
It is written for future implementors who work on the core package.

---

## Core goal

`loom` must produce a correct incremental parse tree for any sequence of edits
on any source text. The grammar sees a clean token stream; error recovery happens
below it. The library must never panic on valid external input.

The one exception to "never panic": internal invariant violations abort
immediately rather than silently producing wrong output. A silent defensive fixup
is worse than an abort — it hides the bug behind corrupted state.

---

## The two-contract model

### Contract 1 — External: the parse API is total

Any `(source, Edit)` pair → a correct tree. No source string is rejected, no
edit sequence is refused. Grammars receive well-formed token streams; when the
source is malformed, error-recovery nodes appear in the tree and `Diagnostic[T]`
values appear in the error list. The grammar writer never needs to handle
impossible token positions.

```moonbit
parse_with(ctx, grammar)           // always produces a CstNode
parse_tokens_indexed(tokens, spec) // always produces a CstNode
token_text(info)                   // returns "" on invalid spans, never aborts
```

`token_text` is the canonical example: a span error from a tokenizer bug or a
grammar invariant violation produces an empty leaf, not a crash. The host process
(an LSP, an IDE) must not die because of a parser edge case.

### Contract 2 — Internal: invariant violations abort

Some code paths are mathematically unreachable from valid external input. When
such a path is reached, it means the library has a programming error — not that
the user gave bad input. Silently patching these cases (e.g., swapping two
indices that should never be out of order) masks the bug and produces wrong
output downstream. The right response is `abort` with an explicit message.

```moonbit
// Example: token_buffer.mbt line 64 — dead code after expand-left
// The swap was reachable only in theory; after the expand-left step the
// invariant holds by construction. The swap was hiding any future regression.
// Replace with:
abort("internal: left_tok_idx > right_tok_idx — invariant violated")
```

**The boundary:** `abort` is for *internal* invariants violated by programming
errors. It is never used on *external* inputs (bad source text, unexpected token
sequences, malformed edit parameters). Those are handled by error recovery and
`Diagnostic[T]`.

---

## Anti-patterns to avoid

| Pattern | Problem |
|---|---|
| Silent defensive swap for an unreachable case | Masks future regressions; produces wrong output instead of surfacing the bug |
| O(width) in a frame-stack algorithm from missing incremental state | Frame resume recomputes child offset from 0 every time; should cache in `CursorFrame` |
| Four unrelated concerns in one file | `lib.mbt` mixed `OffsetIndexed`, `Diagnostic`, `ParserContext`, `AstView` — unreadable and hard to navigate |
| Opaque coordinate variable names | `left_index`, `right_offset` say nothing about coordinate space; `left_tok_idx`, `right_old_offset` are unambiguous |
| `abort` on valid external input | Crashes on error-recovery trees or unusual but valid edit sequences |
| Silent fallback that looks like success | `token_text` returning `""` is documented; an undocumented `""` would be a bug |

---

## Three targeted changes

### Change 1 — Fix O(width) regression in `reuse_cursor.mbt`

**Problem:** `CursorFrame` lacks a `current_child_offset` field. Every time
`seek_node_at` resumes a frame after descending into a child and back, it
recomputes the child's start offset by walking from `child_index = 0` to the
current `child_index`. For a node with W children this is O(W) per resume,
making the whole seek O(width × depth) in the worst case.

**Fix:** Add `mut current_child_offset : Int` to `CursorFrame`. Update it during
the descent loop instead of recomputing it. This restores the intended O(depth)
complexity with no change to external behaviour.

**Bonus:** Extract a `pop_frame` helper. The pattern
`self.stack.pop() |> ignore; self.current = frame` appears three times.
Extracting it reduces 9 lines to 3 calls and makes all three exit paths
structurally identical.

```moonbit
// Before (110-line seek_node_at with recomputation loop)
// After (same algorithm, O(depth), pop_frame used at all three exits)
```

### Change 2 — Split `lib.mbt` into focused files

**Problem:** `lib.mbt` (994 lines) contains four unrelated concerns:
1. `OffsetIndexed` trait + `lower_bound` — generic binary search utility
2. `TokenInfo`, `Diagnostic`, `LexError`, `format_diagnostic` — data types
3. `LanguageSpec`, `ParserContext`, all grammar API methods, incremental reuse machinery, `parse_with`, `parse_tokens_indexed` — the parser proper
4. `AstView` marker trait — belongs at the `loom` facade layer, not `core`

**Fix:** Split into:
- `parser.mbt` (~400 lines) — `OffsetIndexed`, `lower_bound`, `LanguageSpec`, `ParserContext`, grammar API, `parse_with`, `parse_tokens_indexed`
- `diagnostics.mbt` (~200 lines) — `TokenInfo`, `Diagnostic`, `LexError`, `format_diagnostic`, `replay_reused_diagnostics`, `emit_reused`
- `loom.mbt` (facade) — `AstView` trait moves here
- `parser_wbtest.mbt` — inline whitebox tests move here (matching the new source filename)

The goal is that each file has one clear purpose and can be read without scrolling
past unrelated code.

### Change 3 — Clarify coordinate spaces in `token_buffer.mbt`

**Problem:** `token_buffer.mbt` operates in four coordinate spaces simultaneously:
old token index, new token index, old source offset, new source offset. The
current variable names (`left_index`, `right_offset`, `left_offset`) do not
encode which space they are in.

**Fix:** Rename to make the coordinate space explicit at the point of use:

| Before | After |
|---|---|
| `left_index` | `left_tok_idx` |
| `right_index` | `right_tok_idx` |
| `left_offset_old` | `left_old_offset` |
| `right_offset_old` | `right_old_offset` |
| `left_offset_new` | `left_new_offset` |
| `right_offset_new` | `right_new_offset` |
| `left_offset` | `left_clamped` |
| `right_offset` | `right_clamped` |

**Replace dead swap with abort:**

The `if left_tok_idx > right_tok_idx { swap }` (line 64) is dead code. After the
expand-left step (`left_tok_idx = left_tok_idx - 1`), the invariant
`left_tok_idx <= right_tok_idx` holds by construction for any valid `Edit`. The
swap silently masked future regressions. Replace it with:

```moonbit
if left_tok_idx > right_tok_idx {
  abort("internal: left_tok_idx > right_tok_idx after expand-left")
}
```

The second guard at line 85 (`right_clamped = left_clamped` when
`right_clamped < left_clamped`) is left as-is: offset arithmetic after a large
deletion can produce `right_new_offset < left_new_offset` in degenerate cases,
and the clamp is a legitimate safety net, not dead code.

---

## Design references

- [seam/docs/design.md](../../seam/docs/design.md) — the analogous design
  principles for the `seam` CST layer; same two-contract model applied to
  tree queries
- [rowan](https://github.com/rust-analyzer/rowan) — Rust CST library that both
  `seam` and `loom` draw from; all queries are total over error nodes
- [diamond-types](https://github.com/josephg/diamond-types) — stores edit lengths
  not endpoints, the same convention `loom/core`'s `Edit` uses
- [ADR 2026-02-28](../decisions/2026-02-28-edit-lengths-not-endpoints.md) — why
  `Edit` stores `old_len`/`new_len`, not endpoint offsets
