# Loom Framework: Comprehensive Code Analysis Report

## 1. Overview

Loom is a **generic incremental parser framework** written in MoonBit, structured as three independent modules with a clear dependency hierarchy:

```
incr  <-  loom  ->  seam
  (reactive signals)    (CST infrastructure)
```

| Module | Package | Purpose |
|--------|---------|---------|
| **seam** (`dowdiness/seam`) | Standalone | Language-agnostic Concrete Syntax Tree (CST) data structures, event-based tree construction, and structural hashing/interning |
| **incr** (`dowdiness/incr`) | Standalone | Salsa-inspired incremental recomputation engine: signals, memos, dependency tracking, backdating, durability |
| **loom** (`dowdiness/loom`) | Depends on both | Parser framework that connects seam's CST layer to incr's reactivity, providing edit protocols, damage tracking, error recovery, and two parser frontends |

The framework implements a **two-tree model**: an immutable, position-independent green tree (`CstNode`) for structural sharing, and ephemeral positioned facades (`SyntaxNode`) for consumer-facing navigation. This design is directly inspired by the rowan/rust-analyzer architecture.

---

## 2. Execution Flow in Order

The framework supports two distinct parser pipelines. Both are traced from input to output.

### 2.1 Reactive Pipeline (ReactiveParser)

```
String -> Signal[String] -> Memo[CstStage] -> Memo[Ast]
```

1. **Construction** (`ReactiveParser::new`): Creates a `Runtime`, wraps the initial source in a `Signal[String]`, and chains two `Memo` nodes:
   - `cst_memo`: calls `Language::parse_source(source_text.get())` -- this invokes the language's lexer + parser, producing a `CstStage` (containing a `CstNode`, diagnostics, and lex-error flag).
   - `term_memo`: reads `cst_memo.get()`, converts the `CstNode` to a `SyntaxNode`, and calls `Language::to_ast` (or `on_lex_error` if `is_lex_error` is set).

2. **Source update** (`set_source`): Calls `Signal::set(source)`. If the source string is unchanged (by `Eq`), this is a no-op. Otherwise, the signal's revision bumps and both memos become stale.

3. **Read** (`term()`): Calls `term_memo.get()`, which triggers the incr verification chain:
   - Check `verified_at` against `current_revision`
   - If stale, `maybe_changed_after` walks the dependency graph
   - `cst_memo` recomputes if the source changed
   - `term_memo` recomputes only if `CstStage` structurally changed (via `CstNode::Eq` using hash fast-path)
   - **Backdating**: if the new `CstStage` equals the old one (edit in whitespace, for example), `cst_memo.changed_at` stays old, and `term_memo` skips recomputation entirely.

### 2.2 Imperative Pipeline (ImperativeParser)

```
String + Edit -> ImperativeLanguage -> SyntaxNode -> Ast
```

1. **Construction** (`ImperativeParser::new`): Stores the source and an `ImperativeLanguage[Ast]` vtable (closures for `full_parse`, `incremental_parse`, `to_ast`, `on_lex_error`).

2. **Initial parse** (`parse()`): Calls `full_parse(source)`, receives a `ParseOutcome` (either `Tree(SyntaxNode, reuse_count)` or `LexError(msg)`), and runs `accept_tree` to build the AST.

3. **Incremental edit** (`edit(edit, new_source)`): Passes the old `SyntaxNode`, the `Edit`, and new source to `incremental_parse`. The language-specific closure internally uses a reuse cursor over the old tree's `CstNode` to skip reparsing unchanged subtrees.

4. **accept_tree optimization**: Compares the new `CstNode` against `prev_cst` via `CstNode::Eq`. If structurally identical (e.g., edit was within whitespace), the old `Ast` is reused without calling `to_ast` again. This is an AST-level backdating mechanism.

---

## 3. Core Logic by Component

### 3.1 seam: CST Infrastructure

#### CstToken and CstNode (cst_node.mbt)

`CstToken` is a leaf: `{kind: RawKind, text: String, hash: Int}`. The hash is FNV-1a over kind and text, computed at construction.

`CstNode` is an interior node: `{kind, children: Array[CstElement], text_len, hash, token_count}`. All derived fields are computed once in `CstNode::new`:
- `text_len`: sum of children's text lengths (O(children))
- `hash`: FNV-1a chain over kind and each child's variant-tagged hash
- `token_count`: number of non-trivia leaf tokens (recursive via children's `token_count`)

**Key design**: `Eq` uses hash as a fast rejection path but always falls through to full structural comparison on hash match. This means hash collisions never cause false equality.

#### SyntaxNode (syntax_node.mbt)

An ephemeral positioned view: `{cst: CstNode, parent: SyntaxNode?, offset: Int}`. Created on-demand by `SyntaxNode::from_cst(cst)` at offset 0.

**Critical Eq design**: `SyntaxNode::Eq` compares only the underlying `CstNode`, deliberately ignoring `offset` and `parent`. This is documented as enabling `Memo[SyntaxNode]` to skip recomputation when only positions shift (e.g., inserting a leading space) but the tree structure is unchanged.

Navigation methods (`children()`, `all_children()`, `find_at()`, `token_at_offset()`) lazily compute child `SyntaxNode`s with correct absolute offsets.

#### Event-based tree construction (event.mbt)

Three `build_tree` variants convert a flat `ParseEvent` stream into a `CstNode`:

1. **`build_tree`**: Allocates fresh tokens/nodes
2. **`build_tree_interned`**: Deduplicates tokens via `Interner`
3. **`build_tree_fully_interned`**: Deduplicates both tokens and nodes

All three use the same stack-based algorithm:
- `StartNode(kind)` -> push new children list and kind
- `Token(kind, text)` -> append to current children list (with optional interning)
- `FinishNode` -> pop children, create `CstNode`, attach to parent
- `Tombstone` -> skip (unclaimed marks from retroactive `start_at` pattern)

The `EventBuffer::mark()` / `start_at()` pattern enables left-recursive grammar disambiguation: reserve a slot, parse the body, then retroactively decide the node kind.

#### Interning (interner.mbt, node_interner.mbt)

`Interner`: two-level hashmap `RawKind -> (String -> CstToken)`. On the hit path, no allocation occurs -- existing strings/kinds serve as lookup keys.

`NodeInterner`: `HashMap[CstNode, CstNode]`. Uses `CstNode::Hash` (the cached structural hash, O(1)) for bucket selection, then `CstNode::Eq` for collision resolution.

**Invariant**: all nodes fed to one `NodeInterner` must use the same `trivia_kind`, because `token_count` varies by trivia policy but is not included in `Eq`.

### 3.2 incr: Incremental Recomputation

#### Revision and Durability (revision.mbt)

`Revision` is a monotonically increasing integer. `Durability` has three levels: `Low` (index 0, frequent changes), `Medium` (1), `High` (2, rare). The Runtime maintains `durability_last_changed: FixedArray[Revision]` of size 3 -- when a signal of durability `d` changes, all entries at index <= `d` are updated to the new revision.

#### Runtime (runtime.mbt)

The central coordinator holding:
- `current_revision`: global logical clock
- `cells: Array[CellMeta?]`: O(1) cell lookup by ID
- `tracking_stack: Array[ActiveQuery]`: dependency recording during memo computation
- `durability_last_changed`: per-durability revision tracking
- Batch state: `batch_depth`, `batch_pending_signals`, `batch_frames`

Each `Runtime` gets a unique `runtime_id` via global counter, preventing cross-runtime `CellId` misuse.

#### Signal (signal.mbt)

Input cell. `Signal::get()` records a dependency (if inside a memo computation) and returns the value. `Signal::set()` has three paths:

1. **Normal path**: equality check -> if different, update value, bump revision, mark changed, fire callback
2. **Batch path**: store `pending_value`, register `commit_pending`/`rollback_pending` closures
3. **Unconditional path**: skip equality check, always bump

#### Memo (memo.mbt)

Derived cell. `Memo::get_result()` implements the core verification protocol:

1. **No cached value** -> force recompute
2. **Already verified this revision** -> return cached (fast path)
3. **Stale** -> call `maybe_changed_after` on dependencies

`force_recompute()`:
1. Check `in_progress` for cycle detection
2. Push tracking frame -> execute compute function -> pop tracking frame
3. Diff old vs new dependency sets (using `HashSet` for O(1) membership)
4. Update subscriber links (reverse edges) for changed deps
5. **Backdating**: if new value equals old value, preserve old `changed_at`

#### Verification Algorithm (verify.mbt)

`maybe_changed_after` is the heart of the framework. For input cells, it's trivial: `changed_at > after_revision`. For derived cells, it uses an **explicit stack** (`Array[VerifyFrame]`) to avoid call-stack overflow:

**Fast paths** (in `try_start_verify`):
1. Already verified at current revision -> return `changed_at > after_revision`
2. Durability shortcut: if `durability_last_changed[cell.durability] <= after_revision`, no input of this durability changed -> mark verified, return false
3. Cycle detection: if `in_progress`, return `CycleError`

**Iterative walk**:
- For each frame on the stack, iterate through its dependencies
- Input deps are checked inline
- Derived deps go through `try_start_verify` -> either resolved immediately or pushed as a new frame
- When all deps checked without change -> green path (mark verified, pop)
- When any dep changed -> recompute (call `recompute_and_check`, pop)

#### Batch Support (runtime.mbt)

`Runtime::batch(f)` groups signal updates:
1. Increment `batch_depth`, push a `BatchFrame`
2. Execute `f` -- `Signal::set` calls store pending values instead of committing
3. On success: commit pending values (two-phase: commit each, then single revision bump for any that actually changed)
4. On error: rollback pending values using undo entries
5. Nested batches merge undo entries into parent frame; only the outermost batch commits

**Revert detection**: if a signal is set to X then back to its original value within a batch, `commit()` sees no change and skips the revision bump.

### 3.3 loom: Parser Framework

#### Edit Protocol (edit.mbt, delta.mbt)

`Edit { start, old_len, new_len }` -- stores lengths, not endpoints (matching Loro/Quill/diamond-types convention). The `Editable` trait abstracts over edit-like types.

`TextDelta` (Retain/Insert/Delete) converts to `Edit` via `to_edits()`. Adjacent Delete+Insert are merged into a single replace Edit. `text_to_delta(old, new)` computes a minimal delta by finding common prefix and suffix.

#### Damage Tracking (damage.mbt)

`DamageTracker` maintains sorted, non-overlapping `Range`s of damaged regions. Key operations:
- `new(edit)` -> creates initial damage from edit range
- `add_range` -> merge overlapping ranges
- `expand_for_node` -> if a node overlaps any damaged range, expand damage to include the whole node
- `is_damaged` -> check if a range overlaps any damage

Referenced as implementing the Wagner-Graham algorithm (commented in `expand_for_node`).

#### Error Recovery (recovery.mbt)

Five combinators on `ParserContext`:
1. **`expect`**: consume if matching, else emit error placeholder
2. **`skip_until`**: skip tokens until sync point, wrapping skipped tokens in error node
3. **`skip_until_progress`**: like `skip_until` but guarantees forward progress
4. **`skip_until_balanced`**: skip respecting bracket nesting
5. **`node_with_recovery`**: wrap node parsing with automatic recovery on failure
6. **`expect_and_recover`**: expect token -> on mismatch, skip garbage -> retry once

All combinators produce well-formed CST subtrees, maintaining compatibility with reuse cursors and incremental machinery.

#### Language Abstraction (language.mbt, imperative_language.mbt)

Both `Language[Ast]` and `ImperativeLanguage[Ast]` are **token-erased vtables** -- the language-specific token type `T` disappears into closures. This allows the framework to be generic over `Ast` without carrying `T` through the entire API surface.

`Language::from(lang, to_ast~, on_lex_error~)` bridges from a `Parseable` trait implementation to a closure-based vtable. `ImperativeLanguage` adds `incremental_parse` for edit-based reparsing.

#### Global Interners (interners.mbt)

A session-global `core_interner` (shared across all parsers) and per-`trivia_kind` `NodeInterner`s. The separation by trivia_kind prevents cross-grammar corruption of `token_count` values.

#### Tree Diff (diff.mbt)

`tree_diff(old, new)` walks two CST trees simultaneously:
- Equal hashes -> skip (O(1) fast path)
- Kind or child-count mismatch -> emit one Edit for the whole pair
- Same structure -> recurse pairwise on children

Positions are in old-document coordinates. Primarily for convergence verification (asserting empty diff after CRDT merge).

---

## 4. Algorithms and Data Structures

| Algorithm/Pattern | Location | Description |
|---|---|---|
| **Salsa-style incremental verification** | `incr/cells/verify.mbt` | Pull-based verification with explicit stack, fast paths (durability shortcut, already-verified), and backdating |
| **FNV-1a hashing** | `seam/hash.mbt` | Structural content hashing for O(1) tree equality rejection |
| **Stack-based tree construction** | `seam/event.mbt` | Convert flat event stream to tree using parallel kind/children stacks |
| **Two-level interning** | `seam/interner.mbt` | `RawKind -> (String -> CstToken)` -- no allocation on cache hits |
| **Dependency tracking via tracking stack** | `incr/cells/tracking.mbt` | `ActiveQuery` with `HashSet`-based deduplication during memo computation |
| **Two-phase batch commit** | `incr/cells/runtime.mbt` | Phase 1: commit pending values and collect changed set. Phase 2: single revision bump for all changes |
| **Wagner-Graham damage tracking** | `loom/src/incremental/damage.mbt` | Sorted non-overlapping ranges for identifying reparse regions |
| **Prefix/suffix diff** | `loom/src/core/delta.mbt` | `text_to_delta` finds longest common prefix and suffix for minimal delta |
| **Mark/start_at retroactive placement** | `seam/event.mbt` | Reserve tombstone slots for retroactive left-recursive node wrapping |

---

## 5. State Changes and Data Flow

### 5.1 Reactive Pipeline Data Flow

```
User calls set_source("new code")
  -> Signal[String].set("new code")
    -> If value changed: Runtime.bump_revision(Low)
      -> current_revision increments
      -> durability_last_changed[0] = current_revision

User calls .term()
  -> term_memo.get()
    -> verified_at < current_revision -> stale
    -> maybe_changed_after walks deps:
      -> cst_memo: stale, walk its deps:
        -> source_text signal: changed_at > cst_memo.verified_at -> changed
      -> cst_memo: dep changed -> recompute
        -> call parse_source(source_text.get())
        -> produces new CstStage
        -> if CstStage == old CstStage -> backdate (changed_at stays)
        -> else -> changed_at = current_revision
      -> if cst_memo backdated -> term_memo green path (no recompute)
      -> else -> term_memo recomputes -> call to_ast(SyntaxNode::from_cst(cst))
```

### 5.2 Imperative Pipeline Data Flow

```
User calls edit(Edit{start, old_len, new_len}, new_source)
  -> self.source = new_source
  -> If syntax_tree exists:
    -> incremental_parse(new_source, old_syntax, edit)
      -> Language-specific: use reuse cursor over old CstNode
      -> Returns Tree(new_syntax, reuse_count) or LexError
    -> accept_tree:
      -> Compare new_cst with prev_cst via CstNode::Eq
      -> If equal: reuse existing Ast (AST-level backdating)
      -> If different: call to_ast(new_syntax)
```

### 5.3 Mutation Points

Observable mutable state resides in:
- `Runtime.current_revision` -- bumped by `Signal::set`
- `CellMeta.{changed_at, verified_at, dependencies, in_progress}` -- updated by verification/recomputation
- `Signal.value` / `Signal.pending_value` -- set by user, committed by batch
- `Memo.value` -- updated by `force_recompute`
- `ImperativeParser.{source, tree, syntax_tree, prev_cst}` -- updated by `edit`/`parse`
- Global `core_interner` and `core_node_interners` -- grow monotonically, never shrink

---

## 6. Error Handling and Edge Cases

### 6.1 Cycle Detection

Cycles in the dependency graph are detected at two levels:
1. **Memo::force_recompute**: checks `cell.in_progress` before pushing tracking frame
2. **try_start_verify**: checks `cell.in_progress` during verification walk

Both return `CycleError` with the full dependency path. `Memo::get()` aborts on cycle; `Memo::get_result()` returns `Err(CycleError)`.

### 6.2 Batch Error Handling

If the batch closure raises an error:
- The current batch frame's undo entries are rolled back in reverse order
- `batch_depth` is decremented
- The error is re-raised

`abort()` inside a batch is explicitly documented as non-recoverable -- runtime state may be left inconsistent.

### 6.3 Cross-Runtime Safety

`Runtime::get_cell` validates `id.runtime_id != self.runtime_id` and aborts. `cell_info` returns `None` for mismatched runtimes. This prevents accidental cross-runtime cell access.

### 6.4 Tree Construction Safety

All three `build_tree` variants abort on:
- Unbalanced `FinishNode` (no matching `StartNode`)
- Missing `FinishNode` (stack not returned to size 1)
- Empty parent stack when attaching nodes

`EventBuffer::start_at` enforces the mark/start_at contract: mark must be in bounds and point to a `Tombstone`.

### 6.5 Edge Cases in Edit Protocol

`Edit::apply_to_position`: positions before the edit are unchanged, positions within the edit range map to `start`, positions after shift by `delta`. The "within" range includes the endpoint (`pos <= old_end`), which maps to `start` rather than being shifted -- this is a conservative choice that collapses overlapping cursors to the edit origin.

`text_to_delta`: handles edge cases via `try?` on string slicing, falling back to empty string.

---

## 7. Assumptions and Uncertainties

### 7.1 Direct Observations

- The framework is designed for single-threaded use -- no synchronization primitives, `Interner` and `NodeInterner` are documented as "not thread-safe"
- `CstNode` children are documented as "frozen after construction" but enforced only by convention (the `Array` is mutable in MoonBit)
- Hash collisions in `CstNode::Eq` cannot produce false equality -- the hash is a fast rejection path only, with full structural comparison on match

### 7.2 Reasonable Inferences

- The `LanguageSpec` type defines `error_kind`, `trivia_kind`, and tokenization/parsing functions, bridging the generic framework to concrete languages
- The `ReuseCursor` implements a 6-condition reuse protocol for the imperative pipeline -- used by `try_reuse` / `emit_reused` methods on `ParserContext`
- The framework targets IDE-like use cases: the `token_at_offset` API with `Between` result, `find_at` navigation, and `tight_span` trivia-skipping all serve editor integration

### 7.3 Uncertainties

- Whether `CstNode` nodes are reference-compared or structurally compared in the `NodeInterner` is implementation-dependent on MoonBit's `HashMap` semantics -- the code relies on `Hash` + `Eq` traits which are implemented structurally
- The `MemoMap` and `TrackedCell` types are thin wrappers (over `HashMap[K, Memo[V]]` and `Signal[T]` respectively) with straightforward delegation

---

## 8. Key Findings

### 8.1 Three-Layer Backdating

The framework implements backdating at three distinct levels:
1. **incr Memo**: if recomputed value equals old value, `changed_at` is preserved -> downstream memos skip work
2. **CstStage equality**: `CstNode::Eq` uses cached hash for O(1) rejection -> whitespace-only edits produce equal `CstStage` -> AST memo skips
3. **ImperativeParser::accept_tree**: compares `prev_cst` via `CstNode::Eq` -> reuses old `Ast` without calling `to_ast`

### 8.2 Type Erasure Strategy

Both parser frontends erase the language-specific token type `T` into closures at the call site. `Language[Ast]` and `ImperativeLanguage[Ast]` expose only the `Ast` type parameter. This allows the framework to provide a uniform API (`ReactiveParser[Ast]`, `ImperativeParser[Ast]`) without requiring consumers to carry the token type.

### 8.3 Position-Independent Green Tree

`CstNode` stores no positions. `SyntaxNode` computes positions on-the-fly from `offset` and children's `text_len`. This separation enables:
- Structural sharing: identical subtrees in different positions share the same `CstNode`
- Interning: `NodeInterner` deduplicates by structure alone
- Incremental reuse: unchanged subtrees can be spliced into new trees regardless of position shifts

### 8.4 The Durability Optimization

The three-level durability system creates a fast path in verification: if `durability_last_changed[cell.durability] <= after_revision`, no input of that durability level changed since the cell was last verified. This allows high-durability memos (depending on configuration signals) to skip verification entirely when only low-durability inputs (source text) change.

### 8.5 Explicit Stack for Verification

`maybe_changed_after_derived` uses an explicit `Array[VerifyFrame]` stack instead of recursion. This prevents stack overflow on deep dependency graphs and enables a consistent `cleanup_stack` error recovery path (clearing all `in_progress` flags on cycle detection failure).

---

## 9. What Became Clearer Through Analysis

1. **The two-tree model is deeper than it appears.** `SyntaxNode::Eq` deliberately ignoring position means that `Memo[SyntaxNode]` gets free backdating on position-only changes. This is not an accident -- it's an architectural decision that propagates through the entire system: position-independent CST -> position-ignoring equality -> automatic backdating in the reactive pipeline.

2. **The mark/start_at pattern in EventBuffer solves a real parsing problem.** When the parser encounters `a + b`, it doesn't know whether `a` will be a standalone expression or the left-hand side of a binary expression until it sees `+`. The mark reserves a slot before `a`, and `start_at` retroactively wraps `a + b` in a `BinaryExpr` node. This is the same technique used by rust-analyzer's parser.

3. **The `trivia_kind` threading is a subtle invariant.** `CstNode::token_count` depends on which kind is considered trivia. The framework carefully isolates `NodeInterner`s by `trivia_kind` (via `get_core_node_interner`) to prevent cross-grammar corruption. This invariant is documented but enforced only at the architectural level -- violating it produces silently incorrect `token_count` values.

4. **Batch semantics are more sophisticated than simple grouping.** The nested batch frame system with per-frame undo logs, revert detection (setting a signal back to its original value within a batch produces no revision bump), and callback re-entrancy handling (temporarily raising `batch_depth` during callbacks) represents a significant amount of careful state management.

5. **The `accept_tree` optimization in `ImperativeParser` is a third-level cache.** Beyond incr's Memo backdating and CstStage equality, `ImperativeParser` directly compares `prev_cst` to avoid calling `to_ast` when the tree structure is unchanged. This means that an edit within comments (producing identical CstNode) skips not just the parser but also the AST construction.

6. **The framework does not include `ParserContext` in the loom module's public facade.** `ParserContext` and `ReuseCursor` live in `loom/src/core/` and are used by grammar implementations and the incremental parse driver (`parse_tokens_indexed`), but are not re-exported through `loom/src/loom.mbt`. Grammar authors import `@core` directly.
