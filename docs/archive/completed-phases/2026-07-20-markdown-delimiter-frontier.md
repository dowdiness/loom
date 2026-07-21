# Markdown Delimiter Frontier Optimization Investigation Implementation Plan
**Status:** Complete
**Decision:** The standalone frontier probe is retained, and production integration is deferred because the pure continuation-boundary, invalidation, and benchmark gates remain unproven. When no `goal_source` is configured, `ParserContext::token_at(offset, goal=0)` is documented as a viable candidate facts transport; configured goal sources require separate isolation evidence. See [ADR 2026-07-20](../../decisions/2026-07-20-markdown-delimiter-frontier.md).
**Related issue:** #719

> **For agentic workers:** This archived plan records the completed investigation and its evidence; checklist items use checkbox (`- [x]`) syntax.

**Goal:** Determine whether the #719 Markdown code-span delimiter regression can be reduced with a cmark-style container-local monotonic frontier without changing CommonMark semantics, and only then select a bounded read-only cursor, facts transport, or fused-commit implementation.

**Architecture:** Preserve the approved container-local delimiter semantics and CST ownership from the #484 code-span design. First measure a standalone monotonic frontier over token facts; then pass a design gate for an event-free, position-isolated cursor and a pure continuation-boundary predicate. If that gate and the linear-visit bound pass, integrate the smallest Markdown-local optimization. If they do not, do not add speculative emission or an opener-specific cache; produce a separate design for bounded facts transport or fused delayed commit.

**Tech Stack:** MoonBit 0.10.0+84519ca0a; `examples/markdown`; `@core.ParserContext`; `@bench`; existing Markdown CST benchmarks; `rtk` command proxy.

## Global Constraints

- Preserve the approved CommonMark code-span contract in `docs/superpowers/specs/2026-07-14-markdown-code-span-authoring-contract-design.md`.
- Preserve left-to-right CST ownership: `R1 R2 R3` becomes `R1-R2` plus an unconsumed `R3`; `R1 R2 R3 R4` becomes `R1-R2` plus `R3-R4`.
- Do not replace the current benchmark baseline with a slower result and do not alter the #735 regression classification while investigating its cause.
- Do not use an opener-specific cache keyed by `(container, revision, run_length, opener)`; the scan state must be container-local, revision-local, and frontier-based.
- The delimiter scan visit count must be bounded by `container token count * constant`; the frontier must never move backward.
- Do not call the consuming `continue_line()` from a read-only delimiter scan.
- Do not add a generic `ParserContext` API until the read-only cursor and boundary design has passed independent review.
- Every edited MoonBit file receives `rtk moon check` before the next MoonBit edit; use one file per edit call and `rtk`-prefixed commands.
- Do not add compatibility shims, alternate delimiter semantics, or a second Markdown delimiter-index convention.
- The completed investigation records a deferred production path; any implementation remains a separate design-reviewed change.

---

## Existing Contracts and Evidence

The approved code-span design already specifies:

- maximal `Backtick` tokens and source-derived run lengths;
- a container-local successor index with `O(T + R)` delimiter work;
- soft-line continuation ownership by the block parser;
- literal fallback for unmatched runs without consuming the rest of the container;
- lossless CST delimiters and raw interior tokens.

Current implementation points:

- `examples/markdown/inline_parser.mbt:34-159` — `CodeSpanDelimiterIndex`, indexed container prepass, code-span ownership, and continuation consumption;
- `examples/markdown/delimiter_index_wbtest.mbt:1-48` — existing adversarial successor-index benchmark;
- `examples/markdown/cst_parser.mbt:277-300` — root paragraph continuation and consuming boundary logic;
- `loom/core/parser_context_access.mbt:6-65` — token accessors are stored inside `ParserContext`; no read-only cursor is exposed;
- `loom/core/parser_context_access.mbt:69-135` — current token access API;
- `docs/decisions/2026-07-14-lookahead-rollback-boundary.md` — `lookahead` rollback contract;
- `docs/superpowers/specs/2026-07-14-markdown-code-span-authoring-contract-design.md:82-113` — delimiter index and inline-container boundary contract.

The regression investigation must distinguish:

```text
analysis event overhead
from
actual token rereads
from
normal CST/AST parsing cost
```

The cmark and Lezer precedents use opener-time forward scanning; they are comparison points, not proof that a lossless incremental CST can remove all token rereads.

## Task 1: Reproduce and freeze the current regression evidence

**Files:**
- Read: `examples/markdown/benchmark_test.mbt`
- Read: `examples/markdown/inline_parser.mbt`
- Read: `examples/markdown/delimiter_index_wbtest.mbt`
- Evidence: external benchmark evidence file used by the active regression review; do not commit generated timing output as a baseline replacement.

**Interfaces:**
- Consumes: current #719 worktree and the existing realistic Markdown benchmark names.
- Produces: a reproducible baseline table separating CST, CST+AST, tokenize-only, and delimiter-index measurements.

### Steps

- [x] **1. Run the existing focused benchmark without changing code.**

  Run from the Markdown package directory:

  ```bash
  rtk moon bench --release --package dowdiness/markdown --file benchmark_test.mbt --index 9
  rtk moon bench --release --quiet --package dowdiness/markdown --file delimiter_index_wbtest.mbt --index 0
  ```

  Record the command, revision, benchmark names, and raw mean/range values. Do not pipe the runner output into another command when deciding pass/fail.

- [x] **2. Verify that the benchmark detector still exercises the intended rows.**

  Run the repository detector in its normal invocation and confirm that the realistic Markdown CST and CST+AST rows are present. Treat a missing row as a detector failure, not as evidence of an improvement.

- [x] **3. Freeze semantic output before performance work.**

  Run the existing Markdown parser and code-span tests, including delimiter-index, inline, source-fidelity, and incremental tests. Capture the expected CST ownership for:

  ```text
  `a` `b`
  ``a ` b``
  `foo *bar*
  ```
  R1 R2 R3
  R1 R2 R3 R4
  ```

  No timing change is accepted if these outputs change.

## Task 2: Build a standalone monotonic-frontier probe

**Files:**
- Create: `examples/markdown/delimiter_frontier_probe_wbtest.mbt`
- Read: `examples/markdown/benchmark_test.mbt`
- Read: `examples/markdown/delimiter_index_wbtest.mbt`
- Read: `examples/markdown/lexer.mbt`
- Read: `examples/markdown/token.mbt`

**Interfaces:**
- Consumes: the actual lexed token facts for one inline container, including non-backtick tokens, newline/prefix tokens, token start/end positions, and an explicit container end.
- Produces: a probe-only `DelimiterScanFrontier` with monotonic scan accounting over the full container token stream. It must not be wired into `ParserContext` or production parsing.

### Steps

- [x] **1. Add probe data types and a failing full-stream linearity test.**

  Define probe-local types with these fields and meanings:

  ```moonbit
  enum ProbeTokenKind {
    Text
    Backtick
    Newline
    Prefix
    BlockBoundary
    Other
  }

  struct ProbeToken {
    kind : ProbeTokenKind
    start : Int
    end : Int
  }

  struct ProbeContainer {
    tokens : Array[ProbeToken]
    end : Int
  }

  struct ProbeRun {
    token_index : Int
    start : Int
    length : Int
  }

  struct DelimiterScanFrontier {
    frontier_token : Int
    runs_by_length : Map[Int, Array[ProbeRun]]
    cursor_by_length : Map[Int, Int]
    exhausted : Bool
    visits : Int
  }
  ```

  `ProbeContainer.tokens` is the complete lexed token stream for one inline container, not only its backtick runs. `ProbeContainer.end` is the exclusive source boundary supplied by the block/container owner. `visits` counts every newly inspected token index, including `Text`, `Newline`, and `Prefix` tokens.

  Add a deterministic test that initially feeds a complete adversarial token stream with filler text, alternating unmatched backtick lengths, newline/prefix tokens, and an explicit container end. Define `in_container_token_count` from token facts whose end is `<= container.end`, and assert that measured `visits` is no greater than `in_container_token_count * 3`. Run:

  ```bash
  rtk moon test --target native examples/markdown/delimiter_frontier_probe_wbtest.mbt
  ```

  Expected: FAIL because the full-stream frontier scanner and visit counter do not exist.

- [x] **2. Extract probe facts from the real Markdown lexer output.**

  Add a probe-local adapter with these signatures:

  ```moonbit
  fn probe_kind(token : Token) -> ProbeTokenKind
  fn probe_container_from_source(
    source : String,
    container_end : Int,
  ) -> ProbeContainer raise @core.LexError
  ```

  `probe_container_from_source` must call the existing `tokenize(source)` from `examples/markdown/lexer.mbt:907-915`, validate `0 <= container_end && container_end <= source.length()`, walk the returned `Array[@core.TokenInfo[Token]]`, and compute each token's absolute `start`/`end` by the same cumulative-length rule used by `ParserContext::new`. It must map the real `Token` variants from `examples/markdown/token.mbt:281-304` into `ProbeTokenKind`; it must not reconstruct token kinds from source characters.

  The adapter must retain all real lexer facts from `source`, including tokens after `container_end`, while storing the supplied exclusive `container_end` in `ProbeContainer.end`. Add adapter assertions for a real source containing text, backticks, newline, indentation or block-quote prefix, and a same-length backtick run after the supplied boundary. Assert expected token kinds, cumulative ranges, and `container.end` before exercising the frontier. The boundary test must call `probe_container_from_source(source, container_end)` and must not replace post-boundary facts with hand-built tokens.

- [x] **3. Implement monotonic frontier advancement over the full token stream.**

  Add probe-local functions with these signatures:

  ```moonbit
  fn frontier_new() -> DelimiterScanFrontier
  fn frontier_observe_until(
    frontier : DelimiterScanFrontier,
    container : ProbeContainer,
    stop_after_token : Int,
  ) -> Unit
  fn frontier_next_closer(
    frontier : DelimiterScanFrontier,
    opener : ProbeRun,
    container : ProbeContainer,
  ) -> ProbeRun?
  ```

  `frontier_observe_until` must advance only from the current frontier, inspect every token in `container.tokens` up to the requested boundary, append each observed backtick run exactly once to `runs_by_length`, and increment `visits` once per newly observed token index. It must stop at `container.end` and must not inspect a token after the explicit container boundary. `frontier_next_closer` must return the first observed run of the same length strictly after the opener. It must never store an opener-specific suffix result.

- [x] **4. Add ownership, full-stream accounting, and boundary fixtures.**

  Add tests for:

  ```text
  real lexer output with non-backtick filler -> visits counts filler
  R1 R2 R3       -> R1-R2 and unconsumed R3
  R1 R2 R3 R4    -> R1-R2 and R3-R4
  no same-length closer before container_end -> None
  same-length run after container_end -> None
  newline/prefix tokens before container_end -> included in visits
  frontier repeated at the same token -> no additional visits
  ```

  Define `in_container_token_count` as the number of real lexer facts whose token end is `<= container.end`; require the explicit boundary to fall on a token boundary. Assert the selected closer and the visit bound against `in_container_token_count`, not against all retained facts in `container.tokens`. Add a real-lexer fixture with a large post-boundary tail and assert that visits do not increase when the tail is extended or when the scan is asked to advance beyond `container.end`.

- [x] **5. Run the probe tests and the existing delimiter benchmark.**

  Run:

  ```bash
  rtk moon check examples/markdown
  rtk moon test --target native examples/markdown/delimiter_frontier_probe_wbtest.mbt
  rtk moon bench --release --quiet --package dowdiness/markdown --file delimiter_index_wbtest.mbt --index 0
  ```

  Expected: the probe passes the real-lexer adapter, semantic, boundary, and in-container full-stream linear-visit tests. This does not yet establish that integration with `ParserContext` is possible or beneficial.
## Task 3: Pass the read-only cursor and continuation-boundary design gate

**Files:**
- Create: `docs/superpowers/specs/2026-07-20-markdown-delimiter-frontier-design.md`
- Read: `loom/core/parser_context_access.mbt`
- Read: `loom/core/parser_events.mbt`
- Read: `examples/markdown/cst_parser.mbt`
- Read: `examples/markdown/inline_parser.mbt`
- Read: `examples/markdown/parser.mbt`
- Read: `examples/markdown/grammar.mbt`

**Interfaces:**
- Consumes: the full-token-stream frontier contract from Task 2 and current `ParserContext` ownership rules.
- Produces: one concrete event-free token-facts transport and a pure continuation-boundary query, or an explicit decision to defer the cached-scan path.

### Steps

- [x] **1. Specify the cursor boundary without changing `ParserContext`.**

  The design spec must define a cursor equivalent to:

  ```moonbit
  struct ReadOnlyTokenCursor[T] {
    token_count : Int
    get_token : (Int) -> T
    get_start : (Int) -> Int
    get_end : (Int) -> Int
    source : String
    position : Int
  }
  ```

  It must state that the cursor can inspect and locally snapshot/restore `position`, but cannot emit events, mutate diagnostics, open/finish nodes, or touch reuse state.

- [x] **2. Compare the two concrete cursor transports and select the existing baseline token-facts path as the candidate.**

  The design must compare exactly two concrete transports:

  1. **Parser-session transport through the actual Loom path:** `loom/core/parser_entrypoints.mbt:101-114` creates `ParserContext` and invokes `LanguageSpec.parse_root`; `loom/core/parser.mbt:68-80` defines the current callback as `(ParserContext[T, K]) -> Unit`; `loom/grammar.mbt:37-61` and `loom/factories.mbt:66-202` supply the indexed token accessors for one-shot, incremental, and block-reparse calls. A second callback cursor would require a public contract migration, so this option is not selected.
  2. **Existing `ParserContext` capability with no `goal_source`:** when no goal source is configured, `ParserContext::token_at(offset, goal=0)` returns the token and end offset without moving parser position. The probe test carries each returned end as the next offset and proves token-facts scanning without parser-state mutation. This is the candidate transport for any future Markdown-local integration; configured goal sources require separate isolation evidence, and the candidate does not yet prove the production container or performance contract.

  The design must not treat `current_token_text()` or `current_token_range()` as arbitrary transport, and must record that goal-source configuration requires separate isolation evidence.

- [x] **3. Specify pure boundary observation separately from consumption.**

  The design must define:

  ```text
  can_continue_line(...) -> Bool
  consume_continuation(ctx) -> Unit
  ```

  `can_continue_line` may inspect token/source facts but must not advance or emit. `consume_continuation` remains the only function that consumes continuation tokens during normal CST construction. The design must cover paragraphs, list-item paragraphs, block quotes, lazy continuation, setext headings, blank lines, and true block boundaries. The pure query must receive the same explicit container end represented by `ProbeContainer.end`.

- [x] **4. Define invalidation and linearity invariants.**

  The design must require:

  ```text
  frontier is container-local and revision-local
  frontier never decreases
  each scanned token is visited once per container/revision
  delimiter scan visits <= in-container token count * constant
  cache is discarded when source revision or container range changes
  ```

  It must explicitly reject `(container, revision, length, opener)` result tables.

- [x] **5. Run design-only validation; keep production integration deferred pending the boundary and performance gates.**

  The design-only validation names the selected candidate transport and traces:

  ```text
  lex result/token accessors
    -> one-shot or incremental Markdown parse entrypoint
    -> ParserContext::token_at(offset, goal=0) with no configured goal_source
    -> full-token-stream frontier scan
  ```

  The probe proves that no-goal-source `token_at` obtains token kind and end from caller-owned offsets without changing `ParserContext.position`; the next token starts at the returned end. It does not prove pure continuation ownership, incremental invalidation, or production performance, so no production integration is selected and no speculative-emission fallback is added.

## Task 4: Independently review the algorithm and boundary design

**Files:**
- Review: `docs/superpowers/specs/2026-07-20-markdown-delimiter-frontier-design.md`
- Review: `examples/markdown/delimiter_frontier_probe_wbtest.mbt`
- Review: `examples/markdown/lexer.mbt`
- Review: `examples/markdown/parser.mbt`

**Interfaces:**
- Consumes: Tasks 2–3 artifacts and the current code contracts.
- Produces: a tool-backed pass/fail decision with file and line citations.

### Steps

- [x] **1. Obtain independent review before production integration.**

  The reviewer must inspect the real-lexer adapter and design, verify the full-token visit bound, and challenge:

  - repeated suffix scanning through multiple delimiter lengths;
  - frontier state crossing a container or revision boundary;
  - real lexer token kinds, cumulative ranges, and explicit container end;
  - `R1 R2 R3` and `R1 R2 R3 R4` ownership;
  - unmatched opener fallback and following emphasis/link parsing;
  - continuation boundary behavior;
  - interaction with `ParserContext::lookahead` rollback;
  - concrete token-accessor transport for one-shot and incremental parsing.

- [x] **2. Resolve every finding by rejecting the path.**

  No production implementation begins with an unresolved correctness, representativeness, API, or complexity finding.

## Task 5: Integrate only the selected minimal path

**Files if the cached frontier gate passes:**
- Modify: `examples/markdown/inline_parser.mbt`
- Modify: `examples/markdown/cst_parser.mbt`
- Modify if Task 3 selects parser-session transport: `loom/core/parser.mbt`, `loom/core/parser_entrypoints.mbt`, `loom/grammar.mbt`, `loom/factories.mbt`, `loomgen/emit_spec.mbt`
- Migrate/regenerate if Task 3 selects parser-session transport: `loom/factories_wbtest.mbt`, `loom/core/parser_robustness_wbtest.mbt`, `loom/core/parser_zero_width_boundary_properties_wbtest.mbt`, `loom/grammar/grammar_ir_properties_wbtest.mbt`, `loom/grammar/interpreter_test.mbt`, `loom/grammar/reuse_test.mbt`, `examples/css/spec.g.mbt`, `examples/graph-dsl/parser.mbt`, `examples/html/spec.g.mbt`, `examples/json/spec.g.mbt`, `examples/jsx/spec.g.mbt`, `examples/lambda/spec.g.mbt`, `examples/lambda/spike/e3_oracle_wbtest.mbt`, `examples/lambda/spike/lambda_ir.mbt`, `examples/markdown/markdown_spec.mbt`, `loomgen/fixtures/multi_trivia_spec.g.mbt`; refresh generated interfaces, including `loom/core/pkg.generated.mbti`, through the normal MoonBit generation step
- Modify if Task 3 selects generic core capability: `loom/core/parser_context_access.mbt`
- Test: `examples/markdown/inline_test.mbt`
- Test: `examples/markdown/incremental_test.mbt`
- Test: `examples/markdown/source_fidelity_test.mbt`
- Test: `examples/markdown/delimiter_frontier_probe_wbtest.mbt`

**Files if the cached frontier gate fails:**
- Modify only: `docs/superpowers/specs/2026-07-20-markdown-delimiter-frontier-design.md`

**Interfaces:**
- Consumes: the accepted Task 3 cursor/boundary contract and Task 2 frontier invariants.
- Produces: either a measured Markdown-local cached frontier implementation or a documented rejection with the next architecture comparison; never a partial compatibility path.

### Steps when the cached frontier path passes

- [x] **1. Add failing integration tests before changing parser code.** (N/A: cached path rejected.)

  Cover the existing code-span contract, continuation boundaries, source-fidelity origins, incremental edits, and the two ownership fixtures. Also assert that the scanner does not emit CST events during delimiter analysis through probe counters or an equivalent observable instrumentation boundary.

- [x] **2. Replace only the event-producing delimiter analysis path.** (N/A: cached path rejected.)

  Preserve `parse_indexed_inline_code` ownership and raw token emission. Replace the `ctx.lookahead` delimiter-analysis body only with the accepted read-only cursor/frontier transport. Keep normal parsing responsible for continuation consumption and CST events.

- [x] **3. Regenerate the spec factory from its generator source when the parser-session option is selected.** (N/A: cached path rejected.)

  Modify `loomgen/emit_spec.mbt`, then rebuild and run the same generation/check path used by CI:

  ```bash
  rtk moon build loomgen --target native
  rtk moon run loomgen --target native -- \
    --seed examples/lambda/syntax/syntax_kind.mbt --skip-syntax \
    --spec examples/lambda/spec.g.mbt --language lambda \
    --syntax-type SyntaxKind examples/lambda/token/token.mbt \
    --term examples/lambda/meta/term_kind.mbt /tmp/spec-token /tmp/spec-syntax
  rtk moon run loomgen --target native -- \
    --seed examples/json/syntax_kind.mbt --skip-syntax \
    --spec examples/json/spec.g.mbt --language json \
    --syntax-type SyntaxKind --token-qual "" --syntax-qual "" \
    examples/json/token.mbt --term examples/json/meta/term_kind.mbt \
    /tmp/json-spec-token /tmp/json-spec-syntax
  ```

  Regenerate every listed `spec.g.mbt` output with its package's existing generator invocation, refresh generated interfaces, and verify no generated output is hand-edited independently of `loomgen/emit_spec.mbt`.

- [x] **4. Run `moon check` immediately after each MoonBit edit.**

  Run:

  ```bash
  rtk moon check examples/markdown
  ```

  before editing the next MoonBit file. If the selected transport changes core or generator files, run the corresponding package check after each such edit as well.

- [x] **5. Run focused semantic and incremental tests.**

  Run:

  ```bash
  rtk moon test --target native examples/markdown/inline_test.mbt
  rtk moon test --target native examples/markdown/incremental_test.mbt
  rtk moon test --target native examples/markdown/source_fidelity_test.mbt
  rtk moon test --target native examples/markdown/delimiter_frontier_probe_wbtest.mbt
  ```

- [x] **6. Run the realistic regression benchmarks without changing baseline rows.**

  Run:

  ```bash
  rtk moon bench --release --package dowdiness/markdown --file benchmark_test.mbt --index 9
  rtk moon bench --release --quiet --package dowdiness/markdown --file delimiter_frontier_probe_wbtest.mbt --index 0
  rtk moon bench --release --quiet --package dowdiness/markdown --file delimiter_index_wbtest.mbt --index 0
  ```

  Compare balanced paired medians against the frozen pre-change evidence. A semantic pass with no measurable improvement is not an optimization success.

### Steps when the cached frontier path fails

- [x] **7. Write the next design comparison instead of adding a fallback.** (N/A: production integration deferred pending pure boundary, invalidation, and performance evidence.)

  Compare:

  ```text
  bounded container range + facts transport
  fused delayed commit with pending code-span state
  ```

  For each, specify source of container boundaries, ownership of raw token facts, unmatched-opener recovery, interaction with bold/italic/link checkpoint restore, incremental invalidation, and expected event/token visits. Do not call either option implemented until a separate design review accepts it.
## Task 6: Close the investigation with evidence and records

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-markdown-delimiter-frontier.md`
- Create or modify: `docs/decisions/YYYY-MM-DD-markdown-delimiter-frontier.md` if the investigation establishes a reusable policy or records a deferred architecture
- Modify: `docs/README.md` only when the plan is completed or moved

**Interfaces:**
- Consumes: benchmark evidence, semantic test results, design review, and the selected implementation outcome.
- Produces: a plan closure that is auditable without reconstructing this session.

### Steps

- [x] **1. Record measured results and the final decision.**

  Include exact commands, revision, benchmark rows, in-container token-visit bound, focused test results, adapter kind/range assertions, design review result, and whether the result reduced event overhead, token visits, total parse time, or none of these.

- [x] **2. Decide baseline handling explicitly.**

  Keep the existing baseline if the implementation is not proven faster and record the reason. Update the baseline only when the benchmark detector and balanced comparison show a stable intentional change.

- [x] **3. Apply the documentation closure protocol.**

  The acceptance criteria are evidenced below. The implementation tree is fixed by commit `64840ba`; this closure metadata is a subsequent documentation-only commit. The related issue is [#719](https://github.com/dowdiness/loom/issues/719); no PR was created for this investigation. The ADR decision is recorded, and the plan is archived here with the README index updated.

## Closure evidence

- Tested implementation revision: `64840ba` (`test(markdown): classify delimiter frontier regression`); closure metadata is applied in a subsequent documentation-only commit on branch `fix/732-benchmark-classification`.
- `rtk moon check examples/markdown`: 57 warnings, 0 errors.
- `rtk moon test --target native examples/markdown/inline_test.mbt`: 19 passed, 0 failed.
- `rtk moon test --target native examples/markdown/incremental_test.mbt`: 26 passed, 0 failed.
- `rtk moon test --target native examples/markdown/source_fidelity_test.mbt`: 6 passed, 0 failed.
- `rtk moon test --target native examples/markdown/delimiter_frontier_probe_wbtest.mbt`: 8 passed, 0 failed, including no-goal-source `token_at` scanning, non-boundary, out-of-range, same-length post-boundary, and extended post-boundary-tail rejection.
- `rtk moon bench --release --package dowdiness/markdown --file benchmark_test.mbt --index 9`: CST mean 209.65 us.
- `rtk moon bench --release --package dowdiness/markdown --file benchmark_test.mbt --index 10`: CST+AST mean 309.98 us.
- `rtk moon bench --release --quiet --package dowdiness/markdown --file delimiter_index_wbtest.mbt --index 0`: R=512 mean 28.02 us.
- Frozen baseline means were CST 175.52 us, CST+AST 273.60 us, and delimiter index 25.23 us. The latest single-run measurements are slower and do not establish a stable optimization, so the baseline is unchanged.
- The frontier probe retains real lexer facts, validates exact token-end boundaries and post-boundary token ranges, bounds visits by the in-container token count, and proves that an after-boundary same-length run is ignored and that extending the post-boundary tail or scanning past the boundary adds no visits. It is not wired into `ParserContext`.
- Independent review found that no-goal-source `ParserContext::token_at(offset, goal=0)` is sufficient for the probe's token-facts transport; configured `goal_source` delegates regardless of `goal`. The pure continuation-boundary split, invalidation contract, and production performance gate remain unresolved; no production parser or generic core API was changed.

## Final Acceptance Criteria

- [x] Current #719 regression evidence is reproduced with the intended benchmark rows.
- [x] Existing CommonMark code-span semantics and CST ownership remain unchanged.
- [x] The probe extracts facts from the real Markdown lexer output and asserts token kinds and cumulative ranges.
- [x] The standalone frontier probe passes all ownership, explicit-boundary, in-container full-stream accounting, and adversarial linearity tests.
- [x] The pure continuation-boundary and production performance gates remain explicit blockers; no selected cursor is integrated.
- [x] The conditional no-goal-source token-facts transport is documented and its no-position-mutation probe test passes.
- [x] Frontier state is container-local and revision-local; no opener-specific suffix-result cache exists.
- [x] Delimiter scan visits are bounded by `container token count * constant`.
- [x] Independent review identifies the pure boundary, invalidation, and performance blockers; the path is deferred rather than integrated.
- [x] Focused MoonBit checks and semantic/incremental tests pass after the probe-only implementation.
- [x] Realistic CST and CST+AST benchmarks are compared against the frozen baseline.
- [x] The final decision distinguishes event-overhead reduction from complete token reread elimination.
- [x] The plan is closed with the required ADR decision record.
