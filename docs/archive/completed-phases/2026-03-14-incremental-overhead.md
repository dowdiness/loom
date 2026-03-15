# Incremental Parser Overhead: Waste Elimination

**Status:** Complete

**Goal:** Remove measured constant-factor overhead from loom's incremental parse path.

**Non-goal:** Prove that incremental parsing always beats full reparse. Right-recursive grammars remain worst-case; the target is to reduce avoidable overhead and improve the flat-grammar / reusable-subtree cases that the current benchmarks exercise.

**Architecture:** Three focused fixes:
- `TokenBuffer::update` stops returning an unused defensive copy.
- `ReuseCursor` stops flattening old tokens eagerly and instead builds the old-token table lazily on first trailing-context use.
- Reused CST subtrees are attached directly through a `ReuseNode(CstNode)` event instead of being serialized back into StartNode/Token/FinishNode events.

**References:**
- [`docs/performance/incremental-overhead.md`](../performance/incremental-overhead.md)
- [`docs/performance/benchmark_history.md`](../performance/benchmark_history.md)

---

## Preflight

Use the correct MoonBit module root for each command. The repository layout is:

- loom module root: `/home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom`
- seam module root: `/home/antisatori/ghq/github.com/dowdiness/crdt/loom/seam`
- parent integration / benchmark module root: `/home/antisatori/ghq/github.com/dowdiness/crdt`

Do not rely on `moon test -p dowdiness/loom/core` or `moon test -p dowdiness/seam` in this repo. Use file-based commands from the correct module root instead.

Verified command shapes in the current workspace:

- `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom && moon test src/core/token_buffer_wbtest.mbt`
- `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom && moon test src/core/parser_wbtest.mbt`
- `cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/seam && moon test event_wbtest.mbt`

Success criteria for this plan:

- All targeted loom and seam tests pass.
- The plan preserves existing reuse / diagnostic replay behavior.
- Benchmarks are recorded with explicit before/after numbers.
- [`docs/performance/incremental-overhead.md`](../performance/incremental-overhead.md) is only marked complete once the benchmark notes are updated.

---

## Chunk 1: Fix 1 + Fix 2

### Task 1: Remove defensive copy from `TokenBuffer::update`

**Files:**
- Modify: `loom/src/core/token_buffer.mbt`
- Modify: `loom/src/core/token_buffer_wbtest.mbt`
- Modify: `loom/src/core/lex_step_wbtest.mbt`
- Modify: `loom/src/factories.mbt`
- Modify: `examples/lambda/src/lexer/lexer_test.mbt`
- Modify: `examples/lambda/src/lexer/lexer_properties_test.mbt`
- Modify: `examples/lambda/src/benchmarks/performance_benchmark.mbt`

`TokenBuffer::update` currently returns `Array[TokenInfo[T]]` and ends with `self.tokens.copy()`, but that defensive copy is not part of the intended API and several callers only use it because the function exposes it. Removing the return value eliminates one O(n) array copy per edit, but every caller that still binds the returned array must be updated in the same change.

- [ ] **Step 1: Replace the obsolete defensive-copy test**

In `loom/src/core/token_buffer_wbtest.mbt`, replace the current "returns a defensive copy" test with a behavioral regression test that only checks mutation of internal state:

```moonbit
///|
test "TokenBuffer::update updates internal state without a return value" {
  let buf = TokenBuffer::new(
    "ab",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
  )
  buf.update(Edit::insert(1, 1), "axb")
  let stored = buf.get_tokens()
  inspect(stored[0].token, content="char")
  inspect(stored[0].len, content="1")
  inspect(buf.get_start(1), content="1")
  inspect(buf.get_end(1), content="2")
}
```

Do not try to manufacture a runtime-failing test for the return type change. The compiler will catch any remaining callers that still expect `Array[TokenInfo[T]]`.

- [ ] **Step 2: Change `TokenBuffer::update` to return `Unit`**

In `loom/src/core/token_buffer.mbt`:

1. Change the signature from `-> Array[TokenInfo[T]] raise LexError` to `-> Unit raise LexError`.
2. In the full-retokenize branch, replace `return self.tokens.copy()` with `return`.
3. Remove the final `self.tokens.copy()` from the end of the function body.

- [ ] **Step 3: Update all current call sites**

Update:

- `loom/src/factories.mbt`
- `loom/src/core/lex_step_wbtest.mbt`
- `examples/lambda/src/lexer/lexer_test.mbt`
- `examples/lambda/src/lexer/lexer_properties_test.mbt`
- `examples/lambda/src/benchmarks/performance_benchmark.mbt`

Specific changes:

- In `factories.mbt`, replace `let _ = buffer.update(edit, source)` with `buffer.update(edit, source)`.
- Simplify the catch block in `factories.mbt` so it no longer returns a dummy `[]`.
- In `lex_step_wbtest.mbt`, remove the now-unnecessary `ignore(...)` wrapper.
- In `lexer_test.mbt`, stop binding `let updated = ...`; call `buffer.update(...)`, then read back `buffer.get_tokens()` for assertions.
- In `lexer_properties_test.mbt`, replace destructuring of `try? buffer.update(...)` with a sequencing check that calls `buffer.update(...)` and then inspects `buffer.get_tokens()`.
- In `performance_benchmark.mbt`, drop `let result = ...`; benchmark the in-place update call directly and, if needed, read `buf.get_tokens()` separately to consume the updated state.

After editing, run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
rg -n '\.update\(' ../loom ../examples/lambda/src
```

Confirm there are no remaining callers that rely on the old return value. The search should still find call sites, but none should bind, destructure, or `ignore(...)` the return value.

- [ ] **Step 4: Run targeted checks**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon check
moon test src/core/token_buffer_wbtest.mbt
moon test src/core/lex_step_wbtest.mbt
```

- [ ] **Step 5: Run loom regression coverage**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon test src/core/parser_wbtest.mbt
moon test
```

Also run lambda coverage that exercises the external callers changed in this task:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon test src/lexer/lexer_test.mbt
moon test src/lexer/lexer_properties_test.mbt
moon test src/benchmarks/performance_benchmark.mbt
```

- [ ] **Step 6: Update interfaces and format**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon info
moon fmt
```

Verify the only intended API change is the `TokenBuffer::update` return type.

- [ ] **Step 7: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add loom/src/core/token_buffer.mbt
git add loom/src/core/token_buffer_wbtest.mbt
git add loom/src/core/lex_step_wbtest.mbt
git add loom/src/factories.mbt
git add examples/lambda/src/lexer/lexer_test.mbt
git add examples/lambda/src/lexer/lexer_properties_test.mbt
git add examples/lambda/src/benchmarks/performance_benchmark.mbt
git add -u -- '*.mbti'
git commit -m "perf: remove defensive copy from TokenBuffer::update"
```

---

### Task 2: Lazy old-token table for trailing-context checks

**Files:**
- Modify: `loom/src/core/reuse_cursor.mbt`
- Modify: `loom/src/core/parser_wbtest.mbt`

The current code eagerly calls `collect_old_tokens` in `ReuseCursor::new`, flattening the full old CST into `Array[OldToken]` before parsing starts. That work should be deferred until `trailing_context_matches` actually needs it.

Do **not** replace the flat token table with a fresh root-to-leaf tree walk on every lookup. That would trade one eager O(n) pass for repeated rescans from `old_root`. The implementation here should be:

- lazy on first use
- built once
- shared across `ReuseCursor::snapshot` so checkpoint/restore does not rebuild it

- [ ] **Step 1: Add white-box regression tests in `parser_wbtest.mbt`**

Add tests next to the existing `new_follow_token` / `ReuseCursor` coverage in `loom/src/core/parser_wbtest.mbt`. Reuse the existing `test_spec`, `test_tokenize`, and `test_grammar` helpers in that file instead of creating a new `reuse_cursor_wbtest.mbt`.

Add at least:

```moonbit
///|
test "old_follow_token_lazy: finds first non-trivia token at or after offset" {
  let (tree, _) = parse_with("1 + 2", test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts("1 + 2")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    test_spec,
  )
  let result = old_follow_token_lazy(cursor, 1)
  inspect(result is Some(_), content="true")
  let tok = result.unwrap()
  inspect(tok.start, content="2")
  inspect(tok.text, content="+")
}

///|
test "old_follow_token_lazy: returns None past end of tree" {
  let (tree, _) = parse_with("42", test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts("42")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    test_spec,
  )
  let result = old_follow_token_lazy(cursor, 99)
  inspect(result is Some(_), content="false")
}
```

Keep the existing multi-node reuse tests in `parser_wbtest.mbt` as the main regression coverage for behavior.

- [ ] **Step 2: Make the old-token table lazy, not eager**

In `loom/src/core/reuse_cursor.mbt`:

1. Change `ReuseCursor` so the immutable old-tree inputs stay public and the lazy cache is held in a shared cache cell. Do not store `old_tokens` as a plain `Array[OldToken]?` on the cursor itself, because `ParserContext::checkpoint()` snapshots the cursor before speculative branches run. If branch A materializes the cache and then restores, branch B must see the same materialized cache rather than rebuilding it.

Use a shape along these lines:

```moonbit
pub struct OldTokenCache {
  mut tokens : Array[OldToken]?
}

old_root : @seam.CstNode
ws_raw : @seam.RawKind
err_raw : @seam.RawKind
incomplete_raw : @seam.RawKind
cache : OldTokenCache
```

If MoonBit requires a different helper type name or wrapper shape, keep the same semantics: snapshots must share the same mutable cache cell.

2. In `ReuseCursor::new`, remove the eager `collect_old_tokens(...)` call. Always store the root and raw kinds, and initialize the shared cache cell with `tokens: None`.

3. Keep `collect_old_tokens(...)` as the flattening helper.

4. Add a helper that materializes the flattened token table on first use:

```moonbit
fn[T, K] ReuseCursor::ensure_old_tokens(self : ReuseCursor[T, K]) -> Array[OldToken] {
  match self.cache.tokens {
    Some(tokens) => tokens
    None => {
      let tokens : Array[OldToken] = []
      collect_old_tokens(
        self.old_root,
        0,
        tokens,
        self.ws_raw,
        self.err_raw,
        self.incomplete_raw,
      )
      self.cache.tokens = Some(tokens)
      tokens
    }
  }
}
```

5. Replace the eager-array helper with a cursor-based lazy lookup:

```moonbit
fn[T, K] old_follow_token_lazy(
  cursor : ReuseCursor[T, K],
  offset : Int,
) -> OldToken? {
  let old_tokens = cursor.ensure_old_tokens()
  let lo = lower_bound(old_tokens, offset)
  if lo < old_tokens.length() {
    Some(old_tokens[lo])
  } else {
    None
  }
}
```

6. Update `trailing_context_matches(...)` to call `old_follow_token_lazy(cursor, node_end)`.

7. Update `snapshot(...)` so it preserves:

- `old_root`
- raw-kind fields
- the shared cache cell itself, not just the currently materialized array value

This is the correctness requirement for speculative parse branches: once any branch materializes the old-token table, later branches restored from an earlier checkpoint must reuse that same table.

- [ ] **Step 3: Run targeted white-box tests**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon check
moon test src/core/parser_wbtest.mbt
```

Pay particular attention to the existing tests covering:

- post-damage reuse
- follow-token rejection
- checkpoint / restore with reuse cursor snapshots
- reused diagnostic replay and synthesis

- [ ] **Step 4: Run full loom regression coverage**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon test
```

- [ ] **Step 5: Update interfaces and format**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon info
moon fmt
```

`ReuseCursor` is public in `loom/src/core/pkg.generated.mbti`, so field changes here are a public API change. Expect `.mbti` updates, review them deliberately, and update any docs that describe the concrete struct layout.

- [ ] **Step 6: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add loom/src/core/reuse_cursor.mbt
git add loom/src/core/parser_wbtest.mbt
git add -u -- '*.mbti'
git commit -m "perf: make ReuseCursor old-token table lazy"
```

---

## Chunk 2: Fix 3

### Task 3: Internal reuse-node fast path to skip serialize/deserialize round-trip

**Files:**
- Modify: `loom/src/core/parser.mbt`
- Modify: `loom/src/core/parser_wbtest.mbt`
- Modify: `seam/event.mbt` only if needed for a non-public internal helper

When a subtree is reused, `ParserContext::emit_node_events` currently walks the entire node and re-emits StartNode/Token/FinishNode events. `build_tree_fully_interned` then reconstructs the same subtree. The optimization target is real, but making `ReuseNode(CstNode)` a public `ParseEvent` weakens the existing seam builder contract: external callers could pass non-interned nodes into `build_tree_interned(...)` or `build_tree_fully_interned(...)`, and those builders would no longer guarantee that the resulting tree is interned through the provided interner(s).

Keep the fast path internal to loom's incremental parser path instead. Acceptable implementations include:

- a loom-private event type or buffer that can carry reused nodes directly to the final tree builder
- an internal builder entry point used only by the reuse parser path
- a validating/re-interning adapter, if a public `ParseEvent` change is still desired

Do **not** land a public seam API where `build_tree_interned(...)` / `build_tree_fully_interned(...)` attach arbitrary `CstNode`s unchanged.

- [ ] **Step 1: Design the fast path so seam's public builder contract stays intact**

Before editing code, choose one of these two safe directions and keep the rest of the task aligned with it:

1. loom-private reuse event / builder path: preferred, because it preserves seam's public API and avoids adding validation overhead to normal callers.
2. public `ReuseNode`, but with explicit validation or re-interning in the public builders before the child is attached.

If option 2 is chosen, treat it as a seam API change and update tests/docs accordingly. If option 1 is chosen, do not expose `ReuseNode` in `seam/pkg.generated.mbti`.

- [ ] **Step 2: Implement the internal fast path in loom**

Update `loom/src/core/parser.mbt` so reused subtrees avoid serialize/deserialize churn without changing the public guarantees of `@seam.build_tree_interned(...)` and `@seam.build_tree_fully_interned(...)`.

The concrete code shape is up to implementation, but preserve these invariants:

- `emit_reused(...)` still advances positions and replays diagnostics exactly as today
- public seam builders still produce trees interned through the provided interner(s)
- external callers cannot bypass interning guarantees by fabricating a reused subtree

- [ ] **Step 3: Add regression tests at the loom parser layer**

In `loom/src/core/parser_wbtest.mbt`, add tests that prove the fast path preserves behavior. Focus on parser-observable guarantees rather than a new public seam event shape. At minimum cover:

- reused subtree parsing still produces the same CST shape as before
- reused diagnostic replay still works
- if the implementation depends on existing interners, reused children remain consistent with those interners

Only add seam-level tests if you introduce a seam-internal helper that needs direct coverage.

- [ ] **Step 4: Run seam regression coverage if seam code changes**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/seam
moon check
moon test
```

If Task 3 stays entirely loom-internal, `moon check` plus `moon test` is enough; there is no need to add `ParseEvent`-exhaustiveness churn in seam tests.

- [ ] **Step 5: Run loom parser regression coverage**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon check
moon test src/core/parser_wbtest.mbt
moon test
```

Parser white-box tests are the main guardrail here because they already cover:

- reused diagnostic replay
- zero-width boundary errors
- EOF ownership rules
- checkpoint / restore of reuse state

- [ ] **Step 6: Run parent-module integration tests**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon test
```

- [ ] **Step 7: Update interfaces and format**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/seam
moon info
moon fmt

cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon info
moon fmt
```

Only expect `.mbti` updates if Task 3 actually changes a public seam or loom interface. If the implementation stays loom-private, there should be no public `ParseEvent` change to review.

- [ ] **Step 8: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add loom/src/core/parser.mbt
git add loom/src/core/parser_wbtest.mbt
git add seam/event.mbt
git add -u -- '*.mbti'
git commit -m "perf: attach reused CST subtrees directly"
```

---

## Chunk 3: Benchmarks + Documentation

### Task 4: Measure, document, and then mark complete

**Files:**
- Modify: `docs/performance/incremental-overhead.md`
- Modify: `docs/performance/benchmark_history.md`

Do not mark the performance note complete until numbers are recorded.

- [ ] **Step 1: Run the benchmark suite from the parent module**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon bench --release > bench-after.txt 2>&1
```

The relevant parser benchmarks currently live in `editor/performance_benchmark.mbt`, including:

- `parser benchmark - reactive full reparse medium`
- `parser benchmark - imperative incremental medium`
- `parser benchmark - reactive full reparse large`
- `parser benchmark - imperative incremental large`

- [ ] **Step 2: Record the result in `benchmark_history.md`**

Add a dated entry to `docs/performance/benchmark_history.md` summarizing:

- the command used
- the git ref
- the benchmark names above
- before/after means for the incremental vs full-parse comparisons
- a short interpretation

If the project baseline workflow is being maintained in the same change, also update it with:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
bash bench-check.sh --update
```

- [ ] **Step 3: Update `incremental-overhead.md` conservatively**

In `docs/performance/incremental-overhead.md`:

- add a status line near the top
- mark each finding as resolved only if the code landed
- include one short benchmark summary
- keep the right-recursive limitation section intact

Suggested wording:

- `Status: implemented; benchmarked on flat-grammar parser benchmarks`
- not `Status: incremental is always faster than full reparse`

- [ ] **Step 4: Final regression pass**

Run:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/seam
moon test

cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/loom
moon test

cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon test
```

- [ ] **Step 5: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add docs/performance/incremental-overhead.md
git add docs/performance/benchmark_history.md
git add docs/performance/bench-baseline.tsv
git commit -m "docs: record incremental overhead implementation results"
```
