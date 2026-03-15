# emit_reused Fast Path for Healthy Nodes

**Status:** Complete

**Goal:** Eliminate O(subtree) work per reuse hit in `emit_reused` for healthy nodes (no errors).

**What was done:**
- Added `has_any_error : Bool` field to `CstNode`, computed at construction via optional `error_kind` / `incomplete_kind` parameters
- `emit_reused` checks `node.has_any_error` to skip `collect_reused_error_spans` and `Array[ReusedErrorSpan]` allocation for healthy nodes
- `next_sibling_has_error` uses `n.has_any_error` (O(1)) instead of triple `has_errors` calls (O(subtree))
- `has_any_error` folded into cached `self.hash` for consistent Eq/Hash behavior
- Error metadata propagated through all tree-building paths (rebuild_subtree, re_intern_tokens_only, re_intern_subtree)

**What was NOT done (blocked):**
- `advance_past_reused` token_count jump — blocked because `token_count` excludes trivia and CST leaf count differs from token-stream entry count (zero-width synthetic tokens cause overshoot). Safe alternatives: cache total token span on CstNode, or advance non-trivia by token_count then scan remaining trivia.

**Architectural finding:**
The ~2.5x incremental overhead is fundamental to loom's per-node reuse architecture, not a bug in any single operation. rust-analyzer avoids this by using block-level reparse + structural sharing instead of per-node revalidation. See `docs/performance/incremental-overhead.md` for details.
