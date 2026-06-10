# Separated-list grouping helper + parser combinator implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

## Goal
Implement two independent deliverables from the approved design: `SyntaxNode::direct_elements_grouped_by` for stable projection-slot reconstruction and `ParserContext::separated_list` for grammar-author list parsing with marker-based retroactive wrapping.

## Architecture
`seam` and `loom` stay independent, each shipping a standalone API addition plus tests and docs protocol updates.  
`direct_elements_grouped_by` converts flat direct child streams into list-slot groups without changing tree shape, while `separated_list` emits wrapped slot nodes and diagnostics directly into the token stream.  
Both pieces share the slot boundary contract: N separators always imply N+1 slots, and absent elements adjacent to separators produce explicit empty slots.

## PR A (seam): direct_elements_grouped_by

### Task 1: Red tests for grouped direct-element behavior (TDD)
**Files:**
- **Modify:** `seam/syntax_node_wbtest.mbt`
- **Test:** `seam/syntax_node_wbtest.mbt`

1. Add and describe new tests for the helper in prose-only assertions:
   - No-separator case: one group, group count is `1`, child payload is all children preserved.
   - Leading/trailing/doubled separators: group count remains `N+1`; for leading, group `0` is empty; for trailing, the last group is empty; for doubled, the middle group is empty.
   - Trivia filtering on/off with `trivia_kind`:
     - `Some(trivia_kind)` removes trivia tokens from all groups.
     - `None` keeps trivia tokens in sequence.
   - Mixed node+token groups: mixed sequence verifies preserved order and correct `SyntaxElement` type per token/node with offsets.
   - Zero-child node grouping: for empty node, output is `[[]]`.
2. Ensure expected assertions include group and slot sizes, and at least one offset sample per case to lock positioned behavior.
3. Run failing test subset:
   - `cd seam && moon test -p dowdiness/seam -f syntax_node_wbtest.mbt`
   - expected: tests fail with missing symbol `direct_elements_grouped_by` / assertion mismatch.

### Task 2: Implement helper with direct-elements fold
**Files:**
- **Modify:** `seam/syntax_node.mbt`

1. Add signature:
   - `SyntaxNode::direct_elements_grouped_by(separator : RawKind, trivia_kind? : RawKind?) -> Array[Array[SyntaxElement]]`
2. Implement using a single forward pass over `self.direct_elements_iter()`; treat separator tokens as slot breaks and keep empty slots for consecutive or edge separators.
3. Preserve source order and inherited positioned `SyntaxNode`/`SyntaxToken` offsets; maintain invariant "N separators -> N+1 groups".
4. Keep trivia filtering semantics equivalent to `nodes_and_tokens`: when `trivia_kind` is provided, only separator and non-trivia tokens are considered as boundary/content based on kind filtering rules; non-separator trivia tokens stay in slots only when `trivia_kind` is `None`.
5. Use a local builder-array accumulator for group assembly and explain in one note why mutability is necessary for streaming fold state.
6. Run focused pass:
   - `cd seam && moon test -p dowdiness/seam -f syntax_node_wbtest.mbt`
   - expected: all new tests pass.

### Task 3: Harden seam PR and close
**Files:**
- **Modify:** `seam/pkg.generated.mbti` (generated), `docs/README.md` (if docs index touched)
- **Test:** `seam/syntax_node_wbtest.mbt`

1. Regenerate signatures and validate:
   - `cd seam && moon info && moon fmt`
   - expected: `pkg.generated.mbti` includes `direct_elements_grouped_by`.
2. Run full seam module checks:
   - `cd seam && moon test`
   - `cd seam && moon check`
3. Verify no unintended API drift:
   - `git diff seam/pkg.generated.mbti`
4. If `docs/README.md` changed, confirm the plan/index entry is updated in same commit.
5. Commit:
   - `git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt seam/pkg.generated.mbti docs/README.md`
   - `git commit -m "feat(seam): add direct_elements_grouped_by"`
6. Run Codex pre-PR review.
7. Draft PR with `Reuse check` section and create:
   - `gh pr create --title "feat(seam): direct_elements_grouped_by slot grouping helper" --body-file /tmp/pr-body-seam.md`
   - body must include required **Reuse check** checklist.

## PR B (loom core): ParserContext::separated_list

### Task 1: Red tests for separator-slot parse contract (TDD)
**Files:**
- **Modify:** `loom/src/core/parser_wbtest.mbt`
- **Modify:** `loom/src/core/parser_zero_width_boundary_properties_wbtest.mbt` (boundary smoke)

1. Add method-level tests in `parser_wbtest.mbt` for:
   - Boundaries `a,b,c`: return `3`, 2 separators emitted.
   - `a,b,` trailing: return `3`, third slot synthetic error placeholder + diagnostic, slot wrapped element node present.
   - `,a` leading: return `2`, first slot is separator-adjacent empty error element.
   - `a,,b` doubled: return `3`, middle slot empty error element.
   - Empty input: return `0`, no emitted nodes.
   - Count-return checks in all positive/empty cases.
   - No-progress guard: parse function returns true without consuming tokens once; loop exits once and returns finite count.
2. In `parser_zero_width_boundary_properties_wbtest.mbt`, add a boundary smoke that places `separated_list` at an element boundary containing zero-width placeholder and asserts no boundary-token over-consumption.
3. Run failing tests:
   - `cd loom && moon test -p dowdiness/loom -f parser_wbtest.mbt`
   - `cd loom && moon test -p dowdiness/loom -f parser_zero_width_boundary_properties_wbtest.mbt`
   - expected: failures for missing `separated_list` behavior and expected diagnostics.

### Task 2: Implement `ParserContext::separated_list`
**Files:**
- **Modify:** `loom/src/core/parser.mbt`

1. Add signature:
   - `ParserContext::separated_list(element_kind : K, separator : T, parse_element : () -> Bool) -> Int`
2. Verify and apply bounds from source (`parser.mbt`):
   - `T : Eq + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind`
   - `K : @seam.ToRawKind`
3. Implement loop with marker/retroactive wrap:
   - mark before each element attempt.
   - if `parse_element()` returns true: `start_at(mark, element_kind)` + `finish_node()`.
   - else when next token is separator or missing after separator: emit `emit_error_placeholder()` and `report_expected(expected="element")` inside an `element_kind` wrapper.
4. Emit separator tokens via `emit_current_token()` only when `at(separator)` is true after slot parse.
5. No checkpoint/restore usage; any empty-input branch returns `0`.
6. Guard against no-progress loops by comparing parser cursor before/after `parse_element` true path and `break` when unchanged (defensive, non-terminating avoidance).
7. Keep the method declarative by limiting mutable state to count/result accumulators and slot-start cursor; explain this as one-line builder rationale.
8. Run focused tests:
   - `cd loom && moon test -p dowdiness/loom -f parser_wbtest.mbt`
   - `cd loom && moon test -p dowdiness/loom -f parser_zero_width_boundary_properties_wbtest.mbt`
   - expected: all cases in Task 1 pass.

### Task 3: Harden loom PR and close
**Files:**
- **Modify:** `loom/src/core/pkg.generated.mbti` (generated), `docs/README.md` (if docs index touched)
- **Test:** `loom/src/core/parser_wbtest.mbt`

1. Regenerate signatures and format:
   - `cd loom && moon info && moon fmt`
   - expected: `src/core/pkg.generated.mbti` includes `ParserContext::separated_list`.
2. Run full loom module checks:
   - `cd loom && moon test`
   - `cd loom && moon check`
3. Verify no unintended `.mbti` drift:
   - `git diff loom/src/core/pkg.generated.mbti`
4. Update docs index in `docs/README.md` if needed for any markdown change introduced by this PR.
5. Commit:
   - `git add loom/src/core/parser.mbt loom/src/core/parser_wbtest.mbt loom/src/core/parser_zero_width_boundary_properties_wbtest.mbt loom/src/core/pkg.generated.mbti docs/README.md`
   - `git commit -m "feat(loom): add ParserContext::separated_list"`
6. Run Codex pre-PR review.
7. Draft PR with `Reuse check` section and create:
   - `gh pr create --title "feat(loom): add separated-list combinator to ParserContext" --body-file /tmp/pr-body-loom.md`
   - body must include required **Reuse check** checklist.

## Resolved decisions (design owner)
1. `direct_elements_grouped_by` lives adjacent to `nodes_and_tokens` in `seam/syntax_node.mbt` — it shares that method's `trivia_kind?` convention, and both answer "give me direct children in a projection-ready shape".
2. Empty-slot diagnostics use uniform `report_expected(expected="element")` for all slot positions (leading/doubled/trailing). Separator-aware wording is a downstream-grammar concern; grammars wanting richer messages can report before/after calling the combinator.

## Branch setup
- **PR A** executes on the existing `feat/279-separated-list-grouping` branch (already carries the design doc + this plan).
- **PR B** executes on a new branch `feat/279-separated-list-combinator` created from `origin/main` — NOT stacked on PR A (this repo's CI does not run on PRs based on feature branches).
