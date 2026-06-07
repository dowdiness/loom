# Correctness: Incremental Parser

This document defines what correctness means for the incremental parser, how it
is achieved, and what is continuously verified.

## Correctness Goals

### Primary Invariant

For any edit, the incremental parse must produce a tree structurally identical
to a full reparse of the edited source.

In other words:

incremental_parse(source, edit, new_source) == full_parse(new_source)

Structural identity ignores node IDs and other incidental metadata. The raw
green-tree structure, kinds, token boundaries, and internal `RepeatGroup` layout
must match.

`RepeatGroup` is a transparent physical balancing wrapper, not semantic CST
structure. During reuse, tree building flattens reused `RepeatGroup` fragments
and rebalances the current event frame, so incremental parsing reaches the same
layout as a full reparse.

### Secondary Invariants

- Tokenization correctness: incremental lexing must match full lexing.
- Error recovery determinism: for the same source, recovery produces the same
  green tree and diagnostic sequence on each run.
- Termination: all inputs (including malformed ones) must terminate without
  panic, producing a tree with ErrorNode/ErrorToken where needed.

## How Correctness Is Achieved

### 1) Validated CST Reuse Contract

Loom provides validated CST subtree reuse: a subtree may be shared from the old
green tree only after the parser proves it is still valid at the current grammar
boundary. The public contract is structural equivalence with a full reparse, not
stable parser-owned token or subtree identity across edits.

Subtree reuse is permitted only when multiple checks succeed:

- Node kind matches the expected kind at the parser checkpoint.
- Node is outside the damaged range. The default cursor policy keeps
  left-adjacent nodes strict, while the parser-owned edit path opts into
  left-adjacent reuse for pure deletions only.
- Leading token kind/text matches the current token stream.
- Trailing context must match (Option B: follow-token equality).

If any check is uncertain, reuse is skipped and a fresh parse is performed.
Correctness is never traded for reuse.

### 2) Damage Tracking

Edits produce a damaged range using the Wagner-Graham algorithm. Reuse is
disallowed for any subtree overlapping this range, so rebuilt regions are
always parsed from the new source.

### 3) Incremental Lexer Oracle

TokenBuffer updates are verified against full lexing. Token boundaries and
TokenInfo ranges must match exactly. This makes the incremental parser's token
stream a reliable source of truth for both parsing and reuse checks.

### 4) Error Recovery Is Part of Parsing

The parser does not raise on syntax errors. Instead it inserts ErrorNode and
ErrorToken while continuing to parse. This ensures incremental parsing always
has a well-defined output tree, even for incomplete or malformed input.

### 5) Green Tree Reuse and Source-Span Rebasing

Green tree nodes are immutable. The parser may validate an old subtree for
reuse, but source-span tokens require tree building to rebase that subtree onto
the current source buffer. The generic parser therefore rebuilds fresh CST
objects for reused regions instead of promising physical identity with the old
tree. Correctness rests on structural equivalence with a full reparse and on the
reuse checks above; downstream identity-sensitive projections should use
structural equality or explicit domain IDs.

For reuse boundaries, source-backed provenance and structural offsets are
separate checks. A source-backed zero-width lexer token at a reused subtree's
right boundary may be consumed as lexer context; a parser-synthetic zero-width
placeholder is not lexer context. Boundary ownership is determined by walking
children and accumulating their `text_len` from the containing node's start, not
by reading `CstToken::start_offset()` / `end_offset()` backing spans.

RepeatGroup reuse has one extra canonicalization rule:

- The parser may reuse a fragment from an old balanced run.
- Tree building must not preserve that old fragment boundary.
- It flattens reused `RepeatGroup` wrappers into the current event frame,
  combines them with newly parsed siblings, and balances the frame again.
- This keeps the raw green tree equal to a full reparse even when reuse cuts
  through a previous group.

Coverage and scope:

- PR #242 covers the invariant.
- `seam/event_wbtest.mbt` has the `build_tree canonicalizes reused RepeatGroup
  fragments before balancing` regression.
- `loom/src/core/parser_zero_width_boundary_properties_wbtest.mbt` has the
  repeat-group property cases.
- This is separate from explicit token ownership/provenance work tracked in
  #224.

The reused-boundary protocol is:

- First advance past ordinary token-stream entries whose start offset is inside
  the reused node's structural range.
- Then match source-backed zero-width lexer leaves structurally owned by the
  reused node's right edge. These leaves may advance the lexer stream when the
  new stream has the same kind/text run at the reused node end.
- Never let parser-synthetic zero-width leaves advance the lexer stream.
  Placeholders from `emit_zero_width()`, `emit_error_placeholder()`, EOF
  recovery, or incomplete-token recovery are CST structure, not lexer context.
- Never consume a zero-width lexer token owned by the following subtree. Sharing
  the same source offset is not enough; ownership comes from accumulated child
  offsets in the reused tree.
- Treat each boundary run as all-or-nothing. Missing, partial, extra, or
  reordered zero-width boundary tokens reject reuse before the old node is
  emitted. The same rule applies to repeat-group reuse.

PR #221 locked this down with `loom/src/core/parser_wbtest.mbt` regressions:
`ParserContext reuse: zero-width lexer leaf at reused boundary advances position`,
`ParserContext reuse: interned zero-width lexer boundary advances position`,
`ParserContext reuse: custom synthetic zero-width leaf is not a lexer boundary token`,
`ParserContext reuse: custom synthetic zero-width leaf does not consume lexer token`,
`ParserContext reuse: EOF recovery token is synthetic lexer context`,
`ParserContext reuse: extra zero-width token after empty owned boundary rejects reuse`,
`ParserContext reuse: partial zero-width boundary match rejects reuse`,
`ParserContext reuse: extra zero-width boundary token rejects reuse`,
`ParserContext reuse: partial zero-width RepeatGroup boundary match rejects reuse`,
`ParserContext reuse: extra zero-width RepeatGroup boundary token rejects reuse`,
and `ParserContext reuse: zero-width lexer leaf owned by following subtree is not consumed`.

### 6) Event-Stream Balance Guard Rails

Green tree construction depends on a balanced parse-event stream:

- Every emitted StartNode must have a matching FinishNode.
- `mark()` / `start_at()` must only claim Tombstone slots exactly once.
- The SourceFile root is implicit and supplied as `root_kind` to
  `build_tree`, not emitted as StartNode/FinishNode events.

To make this robust and maintainable, checks exist at two layers:

- Producer-side (`GreenParser`):
  `open_nodes` tracks StartNode/FinishNode balance during event emission and
  `assert_event_balance()` verifies the stream before calling `build_tree`.
- Consumer-side (`EventBuffer` / `build_tree`):
  `start_at()` validates mark bounds + Tombstone ownership, and `build_tree`
  aborts on unbalanced FinishNode or missing FinishNode at end-of-stream.

This two-layer approach catches regressions both where events are emitted and
where they are consumed.

## Continuous Verification

### Differential Oracle

Every incremental edit is compared against a full reparse. This is the main
correctness oracle and is expected to run in CI.

### Property-Based Fuzzing

Random edits and random inputs are used to validate:

- Incremental vs full parse identity
- Termination under malformed input
- Error recovery stability

### Regression Tests

Any bug found becomes a permanent regression test. The test captures:

- Source before the edit
- Edit specification
- Expected tree after edit
- Event-stream invariant tests:
  `seam/event_wbtest.mbt` and `src/examples/lambda/cst_parser_wbtest.mbt`

## Current Edge-Case Findings

These are documented to keep the correctness story honest:

- Reuse is conservative around leading whitespace, reducing reuse on
  whitespace-only edits but preserving correctness.
- Left-adjacent insertion remains unsafe by default. Pure deletion may reuse
  the left-adjacent node only when the leading and trailing token checks still
  match, so token-merge cases are reparsed.
- The current deletion-preservation contract does not require a separate
  parser-owned token/subtree identity projection. Add that separate projection
  only for a concrete downstream workflow that needs stable logical identity
  through insertion, replacement, token split/merge, full reparse, or
  AST/domain projection.

## Performance Findings (Profiling)

### Problem Identified

Root-invalidating edits produce many reuse attempts with zero hits. The hot path
was recursive `find_node_at_offset` searches starting from the root on every
call — O(tree) per lookup.

### Optimizations Implemented

Two optimizations reduce search overhead:

1. **Fast path skip:** When the byte offset being queried falls within the
   damaged range (half-open: [start, end)), skip the expensive tree search
   immediately. Tracked via `fast_path_skips` in perf stats.

2. **Stateful cursor:** `ReuseCursor` maintains traversal state using a stack of
   `CursorFrame`s (node + child_index + start_offset). Instead of searching from
   root on every call, the cursor advances incrementally through the tree:
   - Sequential lookups (left-to-right parsing): O(depth) per lookup
   - Backward seeks (shouldn't happen normally): O(tree) reset, then O(depth)

### Measured Results (During Development)

Direct cursor test (4 sequential VarRef lookups in "a b c d e"):
- 4 find_node calls
- 10 total steps (avg 2.5 steps per lookup)
- 1 successful reuse hit

With O(tree) search, each lookup would traverse the entire tree from root.

Note: Production code has instrumentation removed to avoid overhead. These
measurements were taken during profiling.

### Why Timing Benchmarks Show Minimal Change

1. **Small test trees:** Current lambda calculus examples have ~15-30 tokens.
   The O(tree) vs O(depth) difference is more pronounced with larger trees.

2. **Wagner-Graham damage expansion:** For single-expression files, any edit
   causes the root node to overlap with damage, expanding damage to the entire
   tree. This triggers the fast-path skip for all positions.

3. **Tree structure:** Lambda calculus produces deeply nested left-leaning
   spines. The real performance win comes with Phase 5's `let` bindings, which
   create independent top-level subtrees where localized damage is possible.

### When These Optimizations Help

- **Fast path skip:** Any root-invalidating edit (edit at start, structural
  changes) — avoids all tree traversal.
- **Stateful cursor:** Large trees with localized damage and multiple sequential
  reuse lookups — achieves O(depth) instead of O(tree) per lookup.

## Scope of Correctness

Correctness here is strictly about parse tree equivalence between incremental
and full parsing. It does not guarantee:

- Any particular reuse rate or performance improvement
- Semantic equivalence beyond the syntax tree
- Conflict resolution for concurrent edits (CRDT is out of scope)

## Future Work

- Semantics-aware follow-set checks for projectional/live editors
