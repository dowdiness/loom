# Parser-Directed Goal Tokenization (GoalTokenSource)

**Status:** Design note — resolves architectural premises for [#657]
**Date:** 2026-07-09
**Issues:** [#657], [#532], js_engine incremental reuse

[#657]: https://github.com/dowdiness/loom/issues/657
[#532]: https://github.com/dowdiness/loom/issues/532

## 1. Problem

loom's current token model is:

- `TokenBuffer[T]` — linear `Array[TokenInfo[T]]` indexed by position
- Token identity depends only on source content and lexer state
- No mechanism for the parser to say "tokenize this offset under a different lexical goal"

This fails for languages like ECMAScript where the same `/` at the same source offset
must produce `Slash` (division) or `Regex(pattern, flags)` depending on whether the
parser is in `DivGoal` or `RegExpGoal`.

## 2. Persistent artifact

**TokenBuffer is the minimal artifact that persists across edits.** It provides:

- `get_tokens()` — linear token array (baseline, lexer-inferred goals)
- `update(edit)` — range re-lex + offset patching, O(edit size)
- `mode_relex` — optional ModeRelexState for lexer-driven mode switching (Markdown)

**No CST or AST tree persists yet.** Parse reuse (skipping unchanged regions) requires
a persisted tree with span annotations — that is deferred. This design covers
**incremental re-lexing only**.

## 3. GoalTokenSource: overlay, not replacement

```
Before (current):
  ParserContext.get_token(position) → TokenBuffer.get_token(i)

After:
  ParserContext.get_token(position) → TokenBuffer.get_token(i)   (baseline)
  ParserContext.token_at(offset, goal) → GoalTokenSource         (goal-directed)
```

GoalTokenSource is a **parallel access path**, not a wrapper around TokenBuffer:

- **TokenBuffer** owns the baseline token array, indexed by position (linear index).
  Tokens are lexed with the lexer's own contextual inference (current behavior).
- **GoalTokenSource** answers `(source_offset: Int, goal: Int) -> (Token, end_offset: Int)`.
  On cache miss: lex one token at the given offset with the explicit goal.
  Returns the token **and** its exclusive end offset (start + len, matching
  TokenBuffer's convention).
- **No shared state** between the two paths. Both call the same underlying lexer,
  but with different starting assumptions about goal.

This means the same offset can produce different tokens depending on which
path the parser uses — that is the intended behavior.

### The span mismatch problem

The overlay model has a critical constraint: goal-produced tokens can subsume
**multiple positions** in TokenBuffer's linear index.

```
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

Cost: O(log N) per goal-directed advance. For JS, at most the count of `/`
tokens per parse (typically ≤ 100). Acceptable.

`peek_nth(n)` after a goal advance works correctly — the position index is
already past the subsumed region, so peek_nth(1) sees the token after the
regex body.

Baseline `advance()` (no goal) still increments position by 1 — unchanged.
Mixing `advance()` and `advance_with_goal()` is safe; both update the same
position index.

### No mixing in speculative parsing

Checkpoint captures `position` (linear index). If a speculative branch calls
`advance_with_goal`, the position advances past subsumed positions. On
`restore()`, position is rolled back — all subsumed positions are restored.
The GoalTokenSource cache entries from the speculative branch persist, but
that is safe (cache entries are idempotent for the current source).

### Why separate paths instead of one unified path?

TokenBuffer's position index is used for `peek_nth`, `advance`, `position` tracking,
and `ReuseCursor` matching. Making all of these goal-aware would require every
indexed position to carry potential goal alternatives — a global architecture change.

The overlay keeps the existing pipeline untouched. Goal-directed queries are used
only at parser-chosen positions (typically `/` tokens and other goal-ambiguous
sites), while the position index handles routine token navigation.

## 4. Invalidation model

### Edit lifecycle

```
1. Source edit occurs
2. TokenBuffer.update(edit) — re-maps offset→position, re-lexes changed range
3. GoalTokenSource.invalidate() — clears entire cache
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

The cache is bounded by the number of goal-directed queries in a single parse
pass. For ECMAScript, this is at most the number of `/` tokens (each of which
may be queried as both `Div` and `RegExp` in speculative branches), plus
goal transitions for `yield`/`await` context. Empirically ≤ a few hundred
entries for typical files. No eviction policy needed — entries live for one
parse pass and are cleared on the next edit.

## 5. Relationship with existing consumers

### ModeLexer / ModeRelexState (JSON, Lambda, Markdown)

**Independent axes.** ModeLexer handles *lexer-driven* mode switching: the lexer
itself decides when to switch modes (Markdown's ` ``` ` switching to CodeBlock).
GoalTokenSource handles *parser-driven* goal direction: the parser tells the
lexer which goal to use.

They can coexist in the same `TokenBuffer`:

- `TokenBuffer.mode_relex` — lexer-driven mode switching (existing).
- `GoalTokenSource` — parser-driven goal direction (new, overlay).
- A grammar can use both: Markdown uses `ModeLexer` for code-fence switching
  AND `GoalTokenSource` for inline goal-ambiguous constructs (if any).

### ParserContext

`ParserContext.peek()` / `ParserContext.advance()` continue to use the
TokenBuffer linear index. A new method is added for goal-directed access:
```moonbit
// Returns the token at the given source offset, tokenized with the
// specified lexical goal, and its exclusive end offset.
// Returns the best-effort result: if the lexer cannot produce output
// for the given goal (e.g. nonsense goal value), returns the baseline
// token from TokenBuffer.
fn ParserContext::token_at(self, offset: Int, goal: Int) -> (Token, Int)
```

### ReuseCursor

ReuseCursor is **indirectly affected**: it matches old CST nodes to new token
ranges by start offset. Goal-produced tokens may have spans that subsume
multiple baseline TokenBuffer positions (e.g. a `Regex` token spanning offsets
42–48 subsumes positions that the baseline would have split across `Slash` +
body tokens). This means:

- CST nodes inside a goal-subsumed region cannot be reused — they correspond
  to baseline tokens that no longer exist in the goal-aware token stream.
- ReuseCursor matching remains correct for positions NOT queried through
  GoalTokenSource (the common case — most tokens use the baseline path).
- A concrete invalidation rule for reuse inside goal-subsumed regions is
  **deferred to implementation** — the current design ensures correctness
  (baseline STILL exists, so reuse never references dead tokens) but may
  miss reuse opportunities inside goal-directed regions.

### Checkpoint / restore

Checkpoint captures `position` (linear index), `events_len`, `node_stack`,
`lex_mode`. GoalTokenSource entries are **not checkpointed** — the cache
is shared across speculative branches. This is safe because:

- Cache entries are idempotent for the current source: `(offset, goal)` always
  produces the same token for the same source content.
- A speculative branch may populate cache entries that a later committed
  branch also needs — sharing is beneficial.
- If speculative parsing restores and the source has not changed, cached
  entries remain valid.

## 6. peeking with goals

`peek_nth(n)` returns the nth token from the current position using TokenBuffer's
linear index **with the lexer's baseline goal inference**. This is correct because
peek_nth is used for lookahead decisions (FIRST sets, token classification), not
for tokenizing goal-ambiguous positions.

For goal-directed lookahead at a specific position, the parser calls:

```moonbit
let goal = if ctx.in_regex_context() { RegExpGoal } else { DivGoal }
let tok = ctx.token_at(ctx.current_offset(), goal)
```

This keeps peek_nth cheap (no goal parameter threading) while providing the
escape hatch for positions where the goal matters.

## 7. Open questions for #657 implementation

These are deferred to the implementation plan but constrained by this design:

1. **TokenBuffer API** — where does `GoalTokenSource` live? On `TokenBuffer`
   as a field? Independent struct passed alongside? First option preferred
   (makes invalidation colocated with edit handling).

2. **Goal type** — `Int` (same as `ParserContext.lex_mode`) or generic `G`?
   Same reasoning as [#532] Q1: `Int` is cheap, comparable, and the grammar
   maps `Int` → semantic goal. If grammar needs richer goal types, it can
   own a side-channel.

3. **Goal-to-offset mapping** — The parser must know the source offset of the
   current token to call `token_at`. ParserContext already has this via
   `get_start(position)`. No new offset tracking needed.

4. **Lexer reuse** — Re-lexing one token at an offset requires the lexer to be
   able to start at an arbitrary offset, not just from the beginning. This is
   the existing contract of `PrefixLexer` and `ModeLexer` — they accept a
   `(source, pos)` or `(source, pos, mode)` pair. No new capability needed.

## 8. Summary: what this design does and does not provide

| Provides | Does not provide |
|---|---|
| Parser-directed goal queries by source offset | Parse reuse (CST/AST across edits) |
| Memoized re-lex for speculative goal branches | Unified goal-aware `peek_nth` |
| Coexistence with TokenBuffer's linear index | Automatic edit invalidation of cached entries (clear-on-edit) |
| Coexistence with ModeLexer/ModeRelexState | Goal-transition trace (#509 deferred) |
