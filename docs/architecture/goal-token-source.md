# Parser-Directed Goal Tokenization (GoalTokenSource)

**Status:** Implemented — low-level opt-in goal-directed tokenization
**Date:** 2026-07-09 (updated 2026-07-25)
**Issues:** [#657], [#532], js_engine incremental reuse

[#657]: https://github.com/dowdiness/loom/issues/657
[#532]: https://github.com/dowdiness/loom/issues/532

## 1. Problem

loom's baseline token path is:

- `TokenBuffer[T]` — linear `Array[TokenInfo[T]]` indexed by position
- Token identity depends only on source content and lexer state
- No mechanism for the parser to say "tokenize this offset under a different lexical goal" without opting into the explicit goal-query path described here

This fails for languages like ECMAScript where the same `/` at the same source offset
must produce `Slash` (division) or `Regex(pattern, flags)` depending on whether the
parser is in `DivGoal` or `RegExpGoal`.

## 2. Persistent artifact

`TokenBuffer` owns tokenization state across edits. It provides:

- `get_tokens()` — linear token array (baseline, lexer-inferred goals)
- `update(edit)` — range re-lex plus offset patching
- `mode_relex` — optional `ModeRelexState` for lexer-driven mode switching
- `GoalCache` — lazy goal-directed results, invalidated on every source edit

Incremental parser sessions may separately retain old syntax and a
`ReuseCursor`. GoalTokenSource owns neither. Its low-level APIs expose
goal-directed results and a goal-span check that callers can wire into reuse.

## 3. GoalTokenSource: overlay, not replacement

```text
Baseline:
  ParserContext.get_token(position) → TokenBuffer.get_token(i)

With explicit goal-source wiring:
  ParserContext.get_token(position) → TokenBuffer.get_token(i)   (baseline)
  ParserContext.token_at(offset, goal) → GoalTokenSource         (goal-directed)
```

GoalTokenSource is a **parallel access path**, not a wrapper around the
baseline path:

- **TokenBuffer** owns the baseline token array, `GoalCache`, and an optional
  goal-step closure installed with `set_goal_step`.
- **ParserContext** receives a goal-source closure and optional subsumption
  predicate through `set_goal_source`.
- **Standard `Grammar` and parser factories do not wire these closures.** A
  caller must opt in explicitly.
- When wired through `TokenBuffer`, the paths share source and edit lifecycle
  but keep separate token results and query semantics. The goal step is
  explicitly supplied; Loom does not derive it from the baseline lexer or
  `ModeLexer`.

This means the same offset can produce different tokens depending on which
path the parser uses — that is the intended behavior.

### The span mismatch problem

The overlay model has a critical constraint: goal-produced tokens can subsume
**multiple positions** in TokenBuffer's linear index.

```text
TokenBuffer baseline:
  pos 5: Slash(@ "/", start=42, len=1)
  pos 6: Ident("x", start=43, len=1)
  pos 7: ...at offset 44

GoalTokenSource:
  token_at(42, RegExp) = Regex("foo", "g")   ← len=6, end=48
```

If the parser calls `token_at(42, RegExp)` and the TokenBuffer cursor is at
position 5, `advance()` would only move to position 6 — which is inside the
regex body. The position→offset mapping is desynchronized.

### Solution: offset-based advancement

`ParserContext.advance_with_goal(goal)` does NOT increment the position index
by 1. Instead it:
1. Get current offset: start = get_start(position)
2. Query GoalTokenSource: (token, end_offset) = token_at(start, goal)
3. Binary-search TokenBuffer's starts array for first entry ≥ end_offset
4. Set position = found_index
5. Return token

This is valid because ParserContext already has the building blocks:

- `get_start(position)` — current token's source offset
- TokenBuffer's `starts` array is monotonic (non-decreasing offsets)
- `lower_bound` (binary search) already exists in parser.mbt for OffsetIndexed

Cursor alignment costs O(log N) per goal-directed advance.

After a goal advance, the position index is already past the subsumed region,
so `peek_nth(0)` sees the next non-trivia token after the regex body.

Normal `emit_token` continues to advance over the baseline path.
`emit_token_with_goal` advances the same cursor to the goal token's returned
end offset.

### No mixing in speculative parsing

Checkpoint captures `position` (linear index). If a speculative branch calls
`advance_with_goal`, the position advances past subsumed positions. On
`restore()`, position is rolled back — all subsumed positions are restored.
Goal-cache entries from the speculative branch persist. The goal-step contract
must therefore return a stable result for the same source, offset, and goal;
`TokenBuffer::update` invalidates entries when the source changes.

### Why separate paths instead of one unified path?

TokenBuffer's position index is used for `peek_nth`, `advance`, `position` tracking,
and `ReuseCursor` matching. Making all of these goal-aware would require every
indexed position to carry potential goal alternatives — a global architecture change.

The overlay keeps the existing pipeline untouched. Goal-directed queries are used
only at parser-chosen positions (typically `/` tokens and other goal-ambiguous
sites), while the position index handles routine token navigation.

## 4. Invalidation model

### Edit lifecycle

```text
1. Source edit occurs
2. TokenBuffer.update(edit) — re-maps offset→position, re-lexes changed range
3. TokenBuffer clears GoalCache
4. Future goal queries re-lex as needed (cache miss → populate)
```

### Design choice: full cache clear on edit

Rationale:

- GoalTokenSource keys are absolute `source_offset` values
- An edit shifts offsets for all tokens after the edit point
- Determining which cached entries are still valid requires comparing
  each entry's offset against the edit range — more complex than re-populating
- Cache population is lazy: only offsets the parser queries with a specific goal
  generate entries. Typical JS files have few goal-ambiguous `/` tokens per edit.
- Cost is proportional to goal-directed queries in the new parse, not to total
  tokens or total cache size.

Rejected alternatives:

- **Offset-translation table:** TokenBuffer already owns offset→position mapping.
  Translating cached offsets through the edit delta would be possible but adds
  complexity without proven benefit (cache miss rate is low when goal queries
  are sparse).
- **Per-entry version stamps:** Increment a counter on edit; cache hit checks
  `entry.version == current_version`. Equivalent to full clear but with memory
  overhead for stale entries until GC.

### Cache size bound

The cache contains successful `(offset, goal)` queries accumulated since the
most recent source edit. Repeated parses can add entries when they query new
offsets or goals. No eviction policy is currently implemented; the full cache
is cleared on the next edit.

## 5. Relationship with existing consumers

### ModeLexer / ModeRelexState

These are the two supported lexical mechanisms, with separate state and
trigger semantics:

- `ModeLexer` chooses its next native mode while lexing and stores mode snapshots
  for incremental re-lex. Use `ModeLexer`/`ModeRelexFactory` for persistent
  lexer-decided modes.
- GoalTokenSource accepts an explicit opaque goal at each query. Use its
  explicit query APIs for parser-directed lexical goals.

Mode re-lex and goal queries can coexist on one `TokenBuffer`, but there is no
automatic parser-to-lexer mode bridge.

### ParserContext

`ParserContext::peek` and `advance` continue to use the baseline linear index.
The low-level `token_at`, `advance_with_goal`, and `emit_token_with_goal`
methods use an explicitly installed goal-source closure. Without one,
`token_at` falls back to the baseline token.

### ReuseCursor

ReuseCursor is **indirectly affected**: it matches old CST nodes to new token
ranges by start offset. Goal-produced tokens may have spans that subsume
multiple baseline TokenBuffer positions (e.g. a `Regex` token spanning offsets
42–48 subsumes positions that the baseline would have split across `Slash` +
body tokens). This means:

- CST nodes inside a goal-subsumed region cannot be reused safely because
  their baseline token boundaries differ from the goal-produced span.
- ReuseCursor matching remains correct for positions NOT queried through
  GoalTokenSource (the common case — most tokens use the baseline path).
- The implemented reuse path invokes the installed goal-subsumption predicate
  before accepting a candidate. It bypasses reuse when a cached goal span at
  the current offset exceeds the baseline token length.

### Checkpoint / restore

Checkpoints restore parser-owned state, including the cursor and other
parser-owned checkpoint fields. They do not snapshot or roll back `GoalCache`; entries are shared across
speculative branches. The goal-step contract must return stable results for a
given source, offset, and goal, and source edits invalidate the cache.

## 6. peeking with goals

`peek_nth(n)` returns the nth token from the current position using TokenBuffer's
linear index **with the lexer's baseline goal inference**. This is correct because
peek_nth is used for lookahead decisions (FIRST sets, token classification), not
for tokenizing goal-ambiguous positions.

A caller that needs goal-directed lookahead must supply both the source offset
and goal to `token_at`. Loom does not infer either value from unrelated
parser-owned state. Keeping this path explicit leaves `peek_nth` cheap and
baseline-only.

## 7. Implemented boundary

1. `TokenBuffer` owns `GoalCache` and the optional goal-step closure, keeping
   cache invalidation coupled to source edits.
2. Goals are opaque `Int` values whose meaning belongs to the caller.
3. `ParserContext` receives the goal-source and subsumption closures explicitly.
4. Offset-based advancement keeps the baseline cursor aligned when a goal token
   spans several baseline positions.
5. The reuse path can reject candidates inside goal-subsumed spans.
6. Standard `Grammar` and parser factories do not install this capability.

## 8. Summary

| Provides | Does not provide |
|---|---|
| Explicit goal queries by source offset | Standard `Grammar`/factory auto-wiring |
| Memoized results with full invalidation on edit | Unified goal-aware `peek_nth` |
| Offset-based cursor advancement | Parser-driven mode switching |
| Reuse suppression for goal-subsumed spans | Automatic parser-to-lexer mode bridge |
| Coexistence with `ModeRelexState` | Parser-local mode setter |
