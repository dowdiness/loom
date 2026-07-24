# Markdown Container Fact Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the speculative CST-emitting delimiter prepass (`ParserContext::lookahead` in `parse_indexed_inline_container_with_continue_line`) with a Markdown-local container fact plan that walks baseline token facts through `ParserContext::token_at(offset, goal=0)`, records continuation decisions and backtick-run successors without emitting parser events, and feeds the plan to the authoritative inline driver. The investigation is gated: it stops at the isolated prepass benchmark if the speculative cost is not measurable, and stops at the calibrated paired-performance gate if the candidate does not achieve the required improvement. No core parser API, no cache, no goal-source accessor, no arbitrary source-slice API.

**Architecture:** Five gated tasks, each a commit boundary. Task 1 (benchmark stop gate) and Task 5 (performance evidence gate) are stop-or-proceed checkpoints. Tasks 2 (setext token-fact transport), 3 (pure fact observers), and 4 (planner and inline-driver integration) are the implementation core. Mechanical transport (Task 2) is separated from behavioral change (Tasks 3–4) so that lexer parity is a self-contained commit before any parser behavior shifts.

**Tech Stack:** MoonBit 0.10.0+; `dowdiness/loom` core; `examples/markdown`; MoonBit generated `.mbti` interfaces; existing Markdown CST, inline, continuation, incremental, source-fidelity, and MarkdownIR fixture suites.

**Related:** [Design spec](../specs/2026-07-23-markdown-container-fact-plan-design.md); [ADR: defer Markdown delimiter frontier integration](../../decisions/2026-07-20-markdown-delimiter-frontier.md); [continuation decision refactor design](../specs/2026-07-20-markdown-continuation-decision-refactor-design.md)

---

## Global Constraints

- Every task that touches MoonBit code receives `moon check --target wasm-gc` from `examples/markdown` after each file edit. Use `moon ide` for diagnostics/type information while changing APIs.
- Use one file per edit call, `rtk`-prefixed commands, and existing package test targets. Do not run formatters until the final cleanup step of each task.
- No generic core parser API, no `ParserContext` source accessor, no goal-source detection API, no arbitrary source-slice API, no cross-revision cache, no `LanguageSpec` change, no parser-session callback change.
- `ParserContext::token_at(offset, goal=0)` is the sole baseline fact-transport mechanism. Markdown never configures `goal_source` in production; this is a Markdown-local grammar invariant. If a future goal-directed Markdown parser exists, it must obtain a new transport decision before using this planner.
- The planner never advances `ParserContext`, emits a CST event, changes open-node state, changes lex mode, or adds a diagnostic.
- A plan is local to one active inline container and is discarded immediately after that container's authoritative parse.
- Every planned continuation action must equal the owning policy's direct read-only decision at the same newline facts. The authoritative inline parser reads the action from the plan; it must abort on a plan/action offset mismatch rather than infer an alternative action.
- The action's pure fact-cursor advance and its effectful consumer must end at the same token offset.
- Equal-length backtick closer ownership is left-to-right; unmatched or escaped runs retain the current literal fallback.
- One-shot parsing, incremental parsing, and isolated block reparsing produce the same CST, diagnostics, source fidelity, and Markdown IR as before.

## Stop Conditions

1. **Task 1 isolated benchmark stop gate.** For each representative,
   single-container source, measure the prepass-only/full-CST ratio against
   parsing that exact same source. Continue only if the lower endpoint of a
   two-sided 95% bootstrap interval for the median ratio is strictly greater
   than 3.0% for at least one realistic multi-line container. This preflight
   only rules out insufficient isolated headroom; Task 5 alone determines
   whole-document adoption. Otherwise commit the benchmark as a negative-result
   artifact and do not proceed to Tasks 2–5.

2. **Task 5 calibrated performance gate.** Before a candidate implementation is
   evaluated, run three unrecorded warm-up invocations for every metric in each
   of two same-commit worktrees, then at least fifteen counterbalanced A/A
   pairs. Bootstrap the median of paired deltas (10,000 resamples,
   `random.Random(0xC0FFEE)`, two-sided 95% percentile interval). The A/A
   interval for every metric must contain zero. Then run at least fifteen
   candidate-versus-baseline pairs. The candidate is eligible only when the
   upper endpoint of the 95% bootstrap interval for its median paired delta is
   ≤ -3.0% for both realistic CST and realistic CST+AST, and ≤ +2.0% for
   tokenize-only and incremental controls. If any metric fails, retain the
   evidence and do not adopt the production integration.

---

## Task 1: Isolated Prepass Benchmark and Stop Gate

**Purpose:** Measure the current speculative delimiter prepass against full CST
parsing of the same isolated, realistic multi-line container.

**Files:**
- New: `examples/markdown/prepass_benchmark_wbtest.mbt`
- Read-only reference: `examples/markdown/benchmark_test.mbt`, `examples/markdown/inline_parser.mbt:96-135`

**Interfaces:**
- Defines representative single-container fixtures: a root paragraph, a
  block-quote paragraph, and a list-item paragraph, each with continuation
  lines and matched, unmatched, and escaped backtick runs.
- Produces a benchmark that isolates the `ctx.lookahead({... index ...})` block
  currently inside `parse_indexed_inline_container_with_continue_line` at
  `inline_parser.mbt:99-135`, and compares it only with `parse_cst` of the
  same fixture.

### Steps

- [x] **1. Write a test-only benchmark that measures the current speculative prepass in isolation.**

  Create `examples/markdown/prepass_benchmark_wbtest.mbt`. Its test-only helper
  must mirror the current `ctx.lookahead` loop in
  `parse_indexed_inline_container_with_continue_line`
  (`inline_parser.mbt:99–135`) without changing production parser code. For
  each single-container fixture, it starts an ordinary Markdown
  `ParserContext` at that container, runs the loop, builds the existing
  `CodeSpanDelimiterIndex`, and discards it after lookahead restores parser
  state.

  For the same fixture source, separately benchmark that prepass helper and
  `parse_cst`. Capture at least fifteen post-warm-up observations of each;
  pair observations by alternating invocation order, compute one
  prepass/full-CST percentage ratio per pair, and bootstrap its median with
  the seed and percentile convention in the design spec.

  Run:

  ```bash
  cd examples/markdown && rtk moon bench --release --package dowdiness/markdown --file prepass_benchmark_wbtest.mbt --target wasm-gc
  ```

  Expected: benchmark compiles and runs; raw observations and the ratio
  interval are retained as the Task 1 decision evidence.

- [x] **2. Apply the stop condition before changing production behavior.**

  Continue only if the lower 95% bootstrap endpoint for the median
  prepass/full-CST ratio is strictly greater than 3.0% for at least one
  single-container fixture. Otherwise commit the focused benchmark and its
  negative result; production parser code, token transport, and all later
  tasks remain unchanged.

  **Stop gate evidence:** raw observations, the ratio interval, fixture
  identity, bootstrap seed/algorithm, and the go/no-go decision.

**Recorded pre-Task-2 evidence (2026-07-24):**
`docs/performance/2026-07-24-markdown-prepass-stop-gate-pre-task2.json`
records 3 unrecorded warm-ups per ordered variant and 16 alternating pairs per
fixture at `50c18d3275cfb63504828ff1e71b0d0c96199189`, whose parent is
`f430d5a` and contains no Task 2 token transport. This measurement was made
after Task 2 was initially implemented; it repairs source-level provenance and
confirms that the gate would have passed, but cannot reconstruct a historical
pre-implementation decision. With 10,000 `random.Random(0xC0FFEE)`
median-ratio resamples, the lower 95% endpoints are root 13.45%, block quote
10.95%, and list item 11.95%. Each exceeds 3.0%, supporting retention of Task
2 and the start of Task 3.

---

## Task 2: Setext Token-Fact Transport and Lexer Parity

**Purpose:** Enrich exactly the two Markdown tokens whose setext policy reads
spelling: `ThematicBreak(String)` carries the exact thematic token text, and
`ListMarker(UnorderedListMarker)` carries `Dash`, `Star`, or `Plus`. Update
every affected match while preserving all parser behavior. This is a mechanical
transport commit.

**Files:**
- Modify: `examples/markdown/token.mbt` — `Token` variants, `Show`, and raw
  kind conversion for thematic breaks and unordered list markers.
- Modify: `examples/markdown/lexer.mbt` — `lex_line_start` production of both
  thematic breaks and ordinary/lone unordered list markers.
- Modify: every diagnostic-reported Markdown pattern match on either changed
  token variant, including `cst_parser.mbt`, `setext_policy.mbt`,
  `thematic_policy.mbt`, `block_boundary_policy.mbt`, `inline_parser.mbt`, and
  their focused tests.
- Modify: `examples/markdown/lexer_test.mbt` — transport parity fixtures.
- Generated: `examples/markdown/pkg.generated.mbti` after `moon check`.

**Interfaces:**
- `Token::ThematicBreak` becomes `ThematicBreak(String)`. Its string is the
  current thematic token source range: after separate indentation and before
  the newline.
- `Token::ListMarker` becomes `ListMarker(UnorderedListMarker)`. Its payload
  is the marker identity only; it does not alter token length, whitespace
  handling, list-marker classification, or source range.
- All mechanical matches become `ThematicBreak(_)` or `ListMarker(_)`.
  Context-based setext policy retains `current_token_text()` in this commit;
  Task 3 is the sole new token-payload consumer.

### Steps

- [x] **1. Make both token facts explicit and observe compiler fallout.**

  Change the two token variants in `token.mbt`, retaining the existing
  `UnorderedListMarker` type. Use `moon ide` diagnostics and `moon check` to
  enumerate all affected construction and pattern sites before updating them.

  ```bash
  cd examples/markdown && rtk moon check --target wasm-gc
  ```

- [x] **2. Preserve lexer range semantics while supplying both payloads.**

  Update `lex_line_start` so thematic production stores the exact
  marker-to-line-end slice, while each unordered-list production maps its
  matched marker character to the existing `Dash`/`Star`/`Plus` enum before
  constructing `ListMarker`. Keep all current `next_offset` and token-length
  behavior unchanged, including lone markers and markers followed by
  whitespace.

- [x] **3. Update matches mechanically and prove lexed facts.**

  Change all reported variant patterns to ignore payloads unless the test is
  asserting transport. In `lexer_test.mbt`, cover thematic marker spellings
  with and without separate indentation, plus `-`, `*`, and `+` list markers
  both with trailing whitespace and as lone markers. Assert exact thematic
  source-range text, marker identity, and unchanged token ranges.

  ```bash
  cd examples/markdown && rtk moon test --target wasm-gc lexer_test.mbt
  ```

- [x] **4. Run behavioral and interface verification.**

  ```bash
  cd examples/markdown && rtk moon test --target wasm-gc && rtk moon fmt && rtk moon check --target wasm-gc
  ```

  Inspect `pkg.generated.mbti`: the only intended public changes are
  `ThematicBreak(String)` and `ListMarker(UnorderedListMarker)`.

**Commit message:** `markdown: add setext token facts without parser behavior change`

---

## Task 3: Pure Fact Observers and Cursor Advance for Six Continuation Owners

**Purpose:** Extend the existing generic `ContinuationHandler[T]` with two
Markdown-local pure closures: an offset-driven `observe` that returns the same
typed decision from `token_at` facts, and an `advance` that moves only a
caller-owned fact offset through the exact token sequence the consumer emits.
No owner type is erased or dispatched through a shared enum.

**Files:**
- Modify: `examples/markdown/inline_parser.mbt` — extend
  `ContinuationHandler[T]` with typed pure observation and advance closures.
- Modify: `examples/markdown/cst_parser.mbt` — define the six owner-specific
  fact observers and advances beside their existing `decide_*` and `consume_*`
  functions; supply all four closures when constructing each handler.
- Modify: `examples/markdown/setext_policy.mbt` — factor only the existing
  token-fact predicates needed by a pure setext observer, retaining the
  context-based public behavior.
- Modify: `examples/markdown/continuation_wbtest.mbt` — add parity, offset,
  and no-event coverage next to the existing continuation fixtures.

**Six continuation owners and typed decisions:**
1. Root paragraph: `RootContinuationKind`.
2. Block-quote paragraph: `BlockQuoteContinuationKind`.
3. Block-quote setext: `BlockQuoteHeadingContinuationKind`.
4. Root setext: `SetextContinuationKind`.
5. List item: `ListItemContinuationKind`.
6. List-item setext: `ListItemSetextContinuationKind`.

The existing enum types remain package-private and stay in
`cst_parser.mbt`; no `pub(all)` surface or generated-interface change is
required for this task.

**Interfaces:**
- `ContinuationHandler[T]` carries four aligned owner-specific operations:
  context `decide`, effectful `consume`, pure offset `observe`, and pure
  offset `advance`.
- `observe` reads only `ctx.token_at(offset, goal=0)` and facts obtained from
  adjacent offset queries. It must not call `peek`, `peek_nth`, `lookahead`,
  `current_token_text`, an emitter, or any mutating parser operation.
- Setext observation reads `ThematicBreak(payload)` directly from `token_at`
  and applies the existing underline-depth policy to that text. For a
  `ListMarker(marker)`, it uses `Dash`/`Star`/`Plus` identity plus the existing
  following-token trailing-content rule. It obtains indentation and all
  remaining list-line facts from token variants and ends, never from an
  arbitrary source slice.
- `advance` reads `token_at` only. For every `Continue(action)`, it skips the
  entire sequence consumed by that owner’s existing consumer: the newline and
  every prefix token that consumer emits. For example,
  `ThematicBreakPrefix` advances over the newline, indentation, and thematic
  token. `Stop` has no advance.

### Steps

- [ ] **1. Add failing parity tests for all six typed owners.**

  Extend `continuation_wbtest.mbt` using its existing newline-positioning
  helpers. For each owner, cover every `Continue` action and `Stop`: compare
  its existing `decide` result to the new `observe` result at the identical
  source offset; then on a fresh context compare the pure `advance` end offset
  to the end offset after the existing `consume`. Include setext fixtures for
  `Dash`→depth 2 and `Star`/`Plus`→no underline, with every
  `setext_list_marker_line_ends_after_marker` shape: direct
  newline/blank-line/EOF and blank `Text` followed by newline/blank-line/EOF.

  Run:

  ```bash
  cd examples/markdown && rtk moon test --target wasm-gc continuation_wbtest.mbt
  ```

  Expected: failure until the typed pure closures exist.

- [ ] **2. Extend the generic handler without erasing owner types.**

  Update `ContinuationHandler[T]` in `inline_parser.mbt` to carry the pure
  observer and advance closures alongside `decide` and `consume`. Update each
  of the six handler constructions in `cst_parser.mbt` to provide all four
  operations. Preserve the current parser-facing `decide` and `consume`
  signatures and behavior.

- [ ] **3. Implement and co-locate the six fact operations.**

  Beside every owner’s existing decision/consumer pair in `cst_parser.mbt`,
  add its `token_at`-only observer and action advance. Factor only shared
  token-fact predicates that eliminate duplication without moving continuation
  authority out of its owner. The pure setext path must map
  `Dash`→depth 2 and `Star`/`Plus`→no underline, and consume thematic text
  through helpers in `setext_policy.mbt`; the existing context path must retain
  `current_token_text()`.

- [ ] **4. Verify purity and full action/offset correspondence.**

  Extend the focused tests to assert that every observer and advance leaves
  `current_token_range`, current node kind, lex mode, and mark unchanged.
  Verify exact next offsets for every action, especially indented thematic
  prefixes, block-quote marker-plus-prefix cases, and list-item indentation.

  ```bash
  cd examples/markdown && rtk moon test --target wasm-gc continuation_wbtest.mbt
  ```

  Expected: all typed parity, action/offset, and no-event tests pass.

- [ ] **5. Run package verification and format after correctness passes.**

  ```bash
  cd examples/markdown && rtk moon check --target wasm-gc && rtk moon test --target wasm-gc && rtk moon fmt
  ```

**Commit message:** `markdown: add typed continuation fact observation and advance`

---

## Task 4: Typed Container Fact Planner and Inline-Delimiter Integration

**Purpose:** Replace the speculative, CST-emitting delimiter prepass with a
typed, container-local fact plan. The plan walks baseline token facts from the
active container start, owns continuation actions of the same `T` as its
handler, and reuses the existing left-to-right delimiter-index semantics.

**Files:**
- New: `examples/markdown/container_fact_plan.mbt` — private generic plan,
  fact walk, and delimiter-fact collection.
- New: `examples/markdown/container_fact_plan_wbtest.mbt` — plan boundaries,
  typed action parity, no-event behavior, and delimiter fidelity.
- Modify: `examples/markdown/inline_parser.mbt` — construct and consume the
  typed plan; remove only the speculative `lookahead` prepass.

**Interfaces:**
- `ContainerFactPlan[T]` has private fields for its exclusive end offset, a
  `Map[Int, T]` keyed by continuing newline offset, and the current
  `CodeSpanDelimiterIndex` facts. It remains package-private, is built for
  one active container, and is discarded when that parse returns.
- `build_container_fact_plan[T]` receives the current context, container
  start, inline policy, and `ContinuationHandler[T]`. It preserves `T`
  end-to-end: there is no `ContinuationOwner`, uniform action enum, type
  cast, or action-type runtime dispatch.
- At each cursor offset, the planner checks `EOF`, then a `Newline` through
  the handler’s pure observer, then the same policy-specific
  `token_is_inline_block_boundary` predicate used by the driver. `Stop` and a
  block boundary end the plan at the current offset. `Continue(action)`
  records `action` and advances with the matching typed pure advance. Backtick
  facts use the existing equal-length, left-to-right index algorithm. Every
  nonterminal case must strictly advance the local offset or abort.
- The delimiter fact walk resets its preceding-text escape state after every
  successful `Continue(action)`, exactly as the current lookahead prepass does.
  Escapes on one physical line must not make a backtick opener on the next
  continued line ineligible.
- The authoritative `parse_indexed_inline_container` builds the typed plan at
  its current source offset, passes its delimiter facts to the existing inline
  parsing path, and resolves each newline through the plan’s typed action
  before invoking the existing consumer. Missing action at a continuing
  newline is an internal invariant failure. The line-bound,
  no-continuation entry point uses the same fact walker with newlines as
  terminal and records no action.

### Steps

- [ ] **1. Add failing typed planner tests.**

  Create `container_fact_plan_wbtest.mbt`. Cover single-line and multi-line
  ends, `Stop` newline ends, every owner’s recorded typed action, exact
  action/consumer correspondence, no-event planning, equal-length successor
  pairs, unmatched/escaped backticks, and a line-bound container with no
  continuation action. Include a continued line whose preceding line ends in
  an odd number of backslashes and whose next line begins with a backtick run;
  that opener must have the same eligibility and closer as in the current
  prepass. Assert an authoritative parse using the plan produces the same CST
  as the current parser for all corresponding fixtures.

  ```bash
  cd examples/markdown && rtk moon test --target wasm-gc container_fact_plan_wbtest.mbt
  ```

  Expected: failure until the planner exists.

- [ ] **2. Define a private generic plan and fact walk.**

  In `container_fact_plan.mbt`, define `ContainerFactPlan[T]` and the generic
  builder from the interfaces above. Reuse the existing package-private
  `CodeSpanDelimiterIndex` representation and its left-to-right insertion rule
  from `inline_parser.mbt` without relocation or behavior change. Use
  `token_at(offset, 0)` for every fact; do not add any source accessor, cache,
  or parser mutation.

- [ ] **3. Integrate without altering unrelated inline parsing.**

  In `inline_parser.mbt`, replace the `ctx.lookahead` block that builds
  delimiters with plan construction. Keep `parse_inline`, bold, italic, and
  link parsing behavior unchanged; they continue receiving the same delimiter
  facts. Make the continuation closure read the plan’s action at the current
  newline offset and call the handler’s existing typed consumer. Reset
  preceding-text escape state after every successful continuation, preserving
  the current literal fallback for unmatched or escaped backticks.

- [ ] **4. Prove boundaries and parser equivalence.**

  Run the focused plan tests, then the complete Markdown package suite. If a
  differential fixture fails, diagnose and correct the plan before beginning
  performance measurement.

  ```bash
  cd examples/markdown && rtk moon test --target wasm-gc container_fact_plan_wbtest.mbt && rtk moon test --target wasm-gc
  ```

- [ ] **5. Format and verify package interfaces.**

  ```bash
  cd examples/markdown && rtk moon fmt && rtk moon check --target wasm-gc
  ```

  Confirm `pkg.generated.mbti` has no unintended public API drift: all new
  fact-plan and continuation plumbing remains package-private.

**Commit message:** `markdown: replace speculative delimiter prepass with typed fact plan`

---

## Task 5: Behavioral Differential Validation and Calibrated Performance Gate

**Purpose:** Run the complete behavioral differential suite, correct any
behavioral defect before measuring performance, then apply the calibrated
paired-performance adoption gate.

**Files:**
- Read: `examples/markdown/continuation_wbtest.mbt`, `examples/markdown/parser_test.mbt`, `examples/markdown/incremental_test.mbt`, `examples/markdown/source_fidelity_test.mbt`, `examples/markdown/commonmark_html_fixture_test.mbt`, `examples/markdown/commonmark_html_fixture_data_test.mbt`, `examples/markdown/markdown_ir_test.mbt`, `examples/markdown/markdown_ir_properties_test.mbt`, `examples/markdown/inline_test.mbt`, `examples/markdown/error_recovery_test.mbt`, `examples/markdown/delimiter_index_wbtest.mbt`, `examples/markdown/markdown_projection_identity_wbtest.mbt`, `examples/markdown/mdast_fixture_data_test.mbt`, `examples/markdown/mdast_fixture_parity_test.mbt`
- Not modified: any of the above (read-only validation)

### Steps

- [ ] **1. Run the full behavioral differential validation.**

  ```bash
  cd examples/markdown && rtk moon test --target wasm-gc
  ```

  Expected: every test passes. A failure is a parser defect: reproduce and
  correct it, then rerun the complete behavioral suite before performance work.

- [ ] **2. Run the calibrated A/A protocol.**

  In two same-commit worktrees (both at the Task 4 commit), run three unrecorded warm-up invocations for each benchmark metric, then at least fifteen counterbalanced A/A pairs. Use the existing wasm-gc Markdown benchmarks (`benchmark_test.mbt`). The metrics are:
  - realistic CST
  - realistic CST+AST
  - tokenize only
  - incremental paragraph edit

  Bootstrap the median of paired deltas with 10,000 resamples (Python 3, `random.Random(0xC0FFEE)`, `statistics.median`, two-sided 95% percentile interval at indices 250 and 9749). Every metric's A/A interval must contain zero. If not, increase sample size or stabilize environment.

- [ ] **3. Run the candidate-versus-baseline paired benchmark.**

  Build the baseline from the commit immediately before Task 2: it contains
  only the Task 1 benchmark artifact and no token payload, pure handler
  closures, or fact plan. Run at least fifteen counterbalanced
  candidate-versus-baseline pairs.

- [ ] **4. Evaluate the performance gate.**

  Compute the bootstrap 95% percentile interval for the median paired delta of each metric. The candidate is eligible only when:
  - Realistic CST: upper endpoint ≤ -3.0%
  - Realistic CST+AST: upper endpoint ≤ -3.0%
  - Tokenize only: upper endpoint ≤ +2.0%
  - Incremental: upper endpoint ≤ +2.0%

  If any metric fails, the investigation stops. Document the intervals, commit IDs, and the stop decision.

- [ ] **5. If the gate passes, document the evidence.**

  Attach to the candidate PR: raw invocation means, warm-up count, pair ordering, bootstrap seed and algorithm, computed intervals, commands, target, host details, and both commit IDs. Do not update `docs/performance/bench-baseline.tsv` — baseline changes are a separate review decision.

**Commit message (if gate passes):** `markdown: container fact plan — calibrated performance evidence`

---

## Files to Modify (summary)

- `examples/markdown/prepass_benchmark_wbtest.mbt` — new isolated,
  same-container prepass benchmark (Task 1).
- `examples/markdown/token.mbt`, `lexer.mbt`, `block_boundary_policy.mbt`,
  `thematic_policy.mbt`, and every diagnostic-reported `ThematicBreak` match
  site — payload transport only (Task 2).
- `examples/markdown/lexer_test.mbt` — exact payload/source-range parity
  fixtures (Task 2).
- `examples/markdown/inline_parser.mbt` — extend the typed handler (Task 3)
  and replace only its lookahead prepass with plan construction (Task 4).
- `examples/markdown/cst_parser.mbt` and `setext_policy.mbt` — six
  owner-specific fact operations and setext token-fact helper (Task 3).
- `examples/markdown/continuation_wbtest.mbt` — typed decision, advance, and
  no-event parity tests (Task 3).
- `examples/markdown/container_fact_plan.mbt` and
  `container_fact_plan_wbtest.mbt` — private generic planning and integration
  proof (Task 4).
- `examples/markdown/pkg.generated.mbti` — regenerated for the two public
  setext-fact transport changes (Task 2).
- `docs/README.md` — plan index entry (this planning change).

## Validation Plan

### `moon ide` checks before coding

- Locate all `ThematicBreak` and `ListMarker` match sites before Task 2 and
  all six handler constructors before Task 3.
- Inspect `ContinuationHandler[T]`, `parse_indexed_inline_container`, and the
  existing delimiter-index definition before Task 4.

### Build, test, and evidence commands

- Task 1: `rtk moon bench --release --package dowdiness/markdown --file prepass_benchmark_wbtest.mbt --target wasm-gc`;
  retain raw observations and bootstrap calculation.
- Task 2: `rtk moon check --target wasm-gc`, focused lexer tests, then
  `rtk moon test --target wasm-gc`.
- Task 3: `rtk moon test --target wasm-gc continuation_wbtest.mbt`, then the
  package suite.
- Task 4: `rtk moon test --target wasm-gc container_fact_plan_wbtest.mbt`,
  then the package suite.
- Tasks 2–4: after correctness passes, `rtk moon fmt` and
  `rtk moon check --target wasm-gc`.
- Task 5: package suite, calibrated A/A protocol, and at least fifteen
  counterbalanced candidate/baseline pairs under the specified bootstrap
  method.

### Public-interface inspection

After Task 2, inspect `examples/markdown/pkg.generated.mbti` for exactly
`ThematicBreak(String)` and `ListMarker(UnorderedListMarker)`. After Tasks 3
and 4, verify that fact planning and typed continuation plumbing remain
package-private.

## Risks

- **Transport fidelity.** The thematic payload must equal the current token
  source range after separate indentation and before the newline; the list
  payload must preserve `Dash`/`Star`/`Plus` identity. Lexer parity tests prove
  both without changing token ranges.
- **Owner completeness.** Every existing handler construction must provide
  aligned typed decision, consumption, observation, and advance operations;
  no fallback or erased owner dispatch is permitted.
- **Container boundary parity.** The planner must apply the driver’s
  policy-specific boundary predicate after EOF/newline handling and must not
  scan beyond a stop action or boundary.
- **Delimiter fidelity.** Left-to-right equal-length successor construction,
  unmatched runs, and escaped runs must remain identical to the current
  speculative index.
- **Incremental interaction.** A fresh plan belongs only to a newly parsed
  container; one-shot, incremental, and block-reparse outputs must agree.
- **Performance evidence.** A passing isolated preflight only permits
  integration. The calibrated full-document paired gate is the sole adoption
  decision.
