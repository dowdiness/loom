# Core collection ownership migration plan

**Status:** Proposed

**Decision record:**

- [ADR: Core collection ownership boundary](../decisions/2026-08-05-core-collection-ownership-boundary.md)

**Issue:** [#783](https://github.com/dowdiness/loom/issues/783)

**Goal:** Make invariant-bearing CST and lexer values alias-safe while
preserving internal no-copy construction and measured incremental performance.

**Release boundary:** Clean pre-1.0 source migration after the linked ADR is
accepted. Do not implement the breaking API while the ADR remains Proposed.

## Global constraints

- Do not expose an `Array` reachable from `CstNode`, `LexResult`,
  `ModeRelexResult`, `LanguageSpec`, or `DamageTracker` through a field or
  non-copying public accessor.
- Do not add a public constructor whose safety depends on callers surrendering
  an array alias.
- Keep no-copy constructors package-private and document the exclusive-owner
  producer at every call site.
- Preserve lossless CST text, diagnostics, subtree reuse, collision checks, and
  incremental/full-parse equivalence.
- Preserve the equal-cardinality mode-relex optimization unless benchmarks or
  correctness force a separately approved change.
- A mode-aware `TokenBuffer` must retain a factory-derived reset capability.
  Do not expose a public constructor that accepts only a standalone
  `ModeRelexState`.
- A mode-aware `TokenBuffer` must have one lexing authority. Keep
  `new_from_lex` plain-only, use a distinct `new_from_mode_relex` constructor,
  and derive detached/full/reset tokenization from the same factory.
- Preserve `incremental_relex_enabled=false` as the facade-level mode-path
  opt-out: construct a plain buffer from the ordinary lexer and do not invoke
  an optional mode factory. Cover the existing HTML and JSX configurations.
- Public raw lexer-result constructors must return a valid opaque value or
  raise `LexResultError`; they must never return malformed arrays plus a
  diagnostic. User-text recovery remains a complete result plus diagnostics.
- Use tests at public observation seams. White-box tests may exercise
  package-private ownership transfer only to prove the public invariant.
- Do not hand-edit generated `.mbti` files; regenerate them with `moon info`.

## Audited public surfaces and call-site classes

| Surface | Current risk | Migration disposition |
| --- | --- | --- |
| `CstNode` | `pub(all)` fields and retained `children` input invalidate cached metadata | Opaque fields, stored policy, public copy, package-private owned construction |
| `CstNode::with_replaced_child` | Optional classifiers can silently drop metadata | Reuse receiver policy; reject mismatched child policy |
| `build_tree*` and `EventBuffer::build_tree*` | Optional classifiers allow classified event streams and reused nodes to be rebuilt under another policy | Require one policy; use explicit canonical unclassified policy for language-agnostic trees |
| `CstElement::map` | Recursive reconstruction can omit classifiers or accept a mismatched returned subtree | Preserve each receiver policy automatically and reject mismatched substitutions |
| `LexResult` | Validated parallel arrays remain public and constructor inputs are retained | Opaque fields, public copy constructors, indexed/read-only observation, internal owned constructor |
| `ModeRelexState` | Receives buffer-owned `Array[Int]` through callback and can be left mutated after an invalid partial result | Replace offsets with `OldTokenStarts`; make `TokenBuffer` own factory-backed fresh-session recovery |
| `ModeRelexResult` | Public replacement arrays can alias callback inputs | Opaque result with copying public and owned private construction |
| `LanguageSpec` | Retains and exposes mutable trivia-kind array | Opaque fields, copied input, owns one CST metadata policy |
| `DamageTracker` | Mutable range representation is public | Keep mutable façade; privatize array and expose queries |

The local semantic audit on 2026-08-05 found 284 uses of `CstNode::new` and 25
uses of `LanguageSpec::new`. Production code in `seam`, `loom/core`, and the
profiling benchmarks also reads public fields directly.

Direct `DamageTracker.damaged_ranges` use appears only in its package tests.
These counts measure local migration size. External usage requires separate
evidence.

### Generated interface inventory

The following checked-in generated interfaces are expected to change. Review
their diffs after `moon info`; do not hand-edit them.

- `seam/pkg.generated.mbti`
- `loom/core/pkg.generated.mbti`
- `loom/incremental/pkg.generated.mbti`
- `loom/pkg.generated.mbti`

Any other first-party `.mbti` change must be added to this inventory with an
explanation or reverted before release.

### First-party source inventory

The initial 2026-08-05 audit records the implementation and production seams
below. Phase 0 must refresh the list at the implementation-base revision and
append any new hit before code changes begin.

The CST policy and opaque-node slice owns these implementation and production
files:

- `seam/cst_node.mbt`, `seam/cst_traverse.mbt`, `seam/event.mbt`,
  `seam/errors.mbt`, `seam/node_interner.mbt`, and `seam/syntax_node.mbt`
- `loom/core/block_reparse.mbt`, `loom/core/cst_fold.mbt`,
  `loom/core/diff.mbt`, `loom/core/interners.mbt`,
  `loom/core/parser_combinators.mbt`, `loom/core/parser_entrypoints.mbt`,
  `loom/core/parser_events.mbt`, `loom/core/parser_reuse.mbt`, and
  `loom/core/reuse_cursor.mbt`
- `loom/incremental/perf_instrumentation.mbt`, `loom/loom.mbt`, and
  `loom/viz/dot_tree_node.mbt`

The lexer-result and mode-relex slice owns these implementation and production
files:

- `loom/core/diagnostics.mbt`, `loom/core/mode_lexer.mbt`,
  `loom/core/token_buffer.mbt`, and `loom/core/parser_context_access.mbt`
- `loom/factories.mbt`, `loom/grammar.mbt`, and `loom/loom.mbt`
- `examples/graph-dsl/lexer.mbt`, `examples/html/grammar.mbt`,
  `examples/html/lexer.mbt`,
  `examples/json/lexer.mbt`, `examples/jsx/grammar.mbt`,
  `examples/jsx/lexer.mbt`, `examples/lambda/callers/callers.mbt`,
  `examples/lambda/lexer/lexer.mbt`, `examples/markdown/grammar.mbt`,
  `examples/moonbit/fold.mbt`, and `examples/moonbit/lexer_adapter.mbt`

The language-specification slice owns these implementation and production
files:

- `loom/core/parser.mbt`, `loom/core/block_reparse.mbt`,
  `loom/core/parser_context_access.mbt`,
  `loom/core/parser_diagnostics_recovery.mbt`,
  `loom/core/parser_entrypoints.mbt`, `loom/core/parser_reuse.mbt`,
  `loom/core/recovery.mbt`, and `loom/core/reuse_cursor.mbt`
- `loom/factories.mbt` and `loom/grammar.mbt`
- `examples/css/spec.g.mbt`, `examples/graph-dsl/parser.mbt`,
  `examples/html/spec.g.mbt`, `examples/json/spec.g.mbt`,
  `examples/jsx/spec.g.mbt`, `examples/lambda/spec.g.mbt`,
  `examples/markdown/markdown_spec.mbt`, and `examples/moonbit/grammar.mbt`

The damage-tracking slice owns `loom/incremental/damage.mbt`.

Test and benchmark migration is part of the owning slice, not follow-up
cleanup. The exact initial CST files are:

- `seam/cst_node_wbtest.mbt`, `seam/cst_traits_wbtest.mbt`,
  `seam/cst_traverse_wbtest.mbt`, `seam/event_bench_wbtest.mbt`,
  `seam/event_wbtest.mbt`, `seam/metadata_trust_wbtest.mbt`,
  `seam/node_interner_wbtest.mbt`, `seam/projection_group_wbtest.mbt`,
  `seam/seam_properties_wbtest.mbt`, `seam/syntax_node_bench_wbtest.mbt`,
  `seam/syntax_node_wbtest.mbt`, and `seam/syntax_visitor_wbtest.mbt`
- `loom/core/cst_fold_wbtest.mbt`, `loom/core/diff_test.mbt`,
  `loom/core/parser_context_wbtest.mbt`,
  `loom/core/parser_parse_wbtest.mbt`,
  `loom/core/parser_reuse_boundaries_wbtest.mbt`,
  `loom/core/parser_reuse_cursor_wbtest.mbt`,
  `loom/core/parser_separated_list_wbtest.mbt`, and
  `loom/core/parser_zero_width_boundary_properties_wbtest.mbt`, and
  `loom/core/recovery_wbtest.mbt`
- `loom/pipeline/parser_test.mbt`, `loom/pipeline/syntax_parser_test.mbt`,
  `examples/html/parser_test.mbt`, `examples/jsx/parser_test.mbt`,
  `examples/lambda/benchmarks/cst_benchmark.mbt`,
  `examples/lambda/benchmarks/profiling_benchmark.mbt`,
  `examples/lambda/error_recovery_test.mbt`,
  `examples/lambda/imperative_parser_test.mbt`, and
  `examples/markdown/code_block_value_performance_wbtest.mbt`

The exact initial lexer and mode-relex test/benchmark files are:

- `loom/core/diagnostics_wbtest.mbt`,
  `loom/core/goal_token_source_wbtest.mbt`,
  `loom/core/mode_lexer_wbtest.mbt`, `loom/core/mode_relex_wbtest.mbt`,
  `loom/core/parser_robustness_wbtest.mbt`,
  `loom/core/token_buffer_wbtest.mbt`, `loom/factories_wbtest.mbt`, and
  `loom/grammar/reuse_test.mbt`
- `examples/graph-dsl/graph_dsl_test.mbt`,
  `examples/html/lexer_test.mbt`, `examples/jsx/lexer_test.mbt`,
  `examples/lambda/cst_tree_test.mbt`,
  `examples/json/benchmark_test.mbt`,
  `examples/markdown/incremental_test.mbt`,
  `examples/markdown/mode_relex_storage_benchmark_wbtest.mbt`,
  `examples/markdown/performance_envelope_benchmark_wbtest.mbt`,
  `examples/moonbit/parser_test.mbt`, and
  `examples/moonbit/top_level_differential_test.mbt`

The exact initial language-specification test/benchmark files are:

- `loom/core/parser_context_source_id_test.mbt`,
  `loom/core/parser_test_fixtures_wbtest.mbt`,
  `loom/core/parser_reuse_boundaries_wbtest.mbt`,
  `loom/core/parser_reuse_cursor_wbtest.mbt`,
  `loom/core/parser_robustness_wbtest.mbt`,
  `loom/core/parser_separated_list_wbtest.mbt`,
  `loom/core/parser_zero_width_boundary_bench_wbtest.mbt`, and
  `loom/core/parser_zero_width_boundary_properties_wbtest.mbt`
- `loom/factories_wbtest.mbt`,
  `loom/grammar/grammar_ir_properties_wbtest.mbt`,
  `loom/grammar/interpreter_test.mbt`, and `loom/grammar/reuse_test.mbt`
- `examples/lambda/benchmarks/grammar_incremental_benchmark.mbt`,
  `examples/lambda/spike/e3_oracle_wbtest.mbt`, and
  `examples/lambda/spike/lambda_ir.mbt`

The damage-tracking test/benchmark files are
`loom/incremental/damage_test.mbt` and
`examples/lambda/benchmarks/benchmark.mbt`.

### Prototype exploration

The remote throwaway branch `prototype/mode-relex-constructor-split` records
the simplified executable model at
[d35c5e1429a3a04b213a31cee6048ce0ad6e2a05](https://github.com/dowdiness/loom/commit/d35c5e1429a3a04b213a31cee6048ce0ad6e2a05).
It is neither an implementation dependency nor a conformance test for the
target public API. It provides limited feasibility evidence for these design
directions:

- a simplified result constructor can report a concrete `LexResultError`
  instead of returning malformed parallel arrays;
- separate plain and mode-aware `TokenBuffer` constructors can make the mode
  factory responsible for initial and detached tokenization;
- a session that mutates before partial failure is discarded;
- fresh state can publish committed source, tokens, starts,
  diagnostics, version, and replacement session together;
- failed fresh validation retains every committed field and leaves
  `ResetRequired`; the next update bypasses partial re-lex.

After checking out the prototype branch, run it with
`moon run loom/core_constructor_prototype --target native`. Commands `v`, `d`,
`s`, `x`, and `r` exercise the recoverable paths; separate runs with `a` and
`m` exercise the two intentional initial-construction aborts.

The prototype deliberately does not prove the target package opacity,
`SourceId`/`DiagnosticSet` types, `OldTokenStarts` boundary, full seven-argument
`relex_from` signature, convergence and damage validation, partial splicing, or
integration with the production `TokenBuffer`. Phase 1 must establish those
properties in the real implementation with compiler-checked public interfaces
and automated black-box and white-box tests.

Phase 0 stores the exact audit commands and their output in the implementing
issue. A path category or count without the matching path list does not satisfy
the audit gate.

## Phase 0: acceptance and repeat audit

- [ ] Accept the linked ADR and record maintainer approval date.
- [ ] Repeat `moon ide find-references` for the existing symbols
  `CstNode::new`,
  `CstNode::with_replaced_child`, all `build_tree*` methods,
  `CstElement::map`, `LexResult::LexResult`, `LexResult::with_starts`,
  `LexResult::from_located_tokens`,
  `ModeRelexFactory::new_session_with_initial`, `erase_mode_lexer`,
  `erase_mode_lexer_factory`, `TokenBuffer::new_from_lex`,
  `TokenBuffer::new_with_mode_relex`, `LanguageSpec::new`, and
  `DamageTracker::new`. The proposed `ModeRelexResult::new`,
  `ModeRelexState::new`, and `ModeRelexFactory::new` have no pre-migration
  symbols; audit their current struct literals and direct field access through
  the type searches instead of recording a misleading zero-reference result.
- [ ] Search direct field access for every affected type in Loom, Canopy,
  js_engine, indexed public GitHub code, and published module metadata where
  reverse-dependency evidence exists.
- [ ] Record the exact revisions and classify each hit as production, test,
  benchmark, generated code, or documentation.
- [ ] Create the measurement-preparation issue and bounded implementation
  issues for Phases 1-5. Do not combine the entire migration into one review
  unit.
- [ ] Before any ownership implementation commit, land one measurement-only
  preparation commit that adds the `core-ownership` profile, its policy file,
  parser/comparator self-tests, `BENCHMARKS.md` workflow, and every required
  benchmark row using the current interfaces. The commit must contain no
  ownership implementation change.
- [ ] Run the prepared profile for five samples on that clean commit, store its
  raw outputs, and record the commit as `CORE_OWNERSHIP_BASELINE_SHA` in the
  implementing issues and benchmark history. Base every Phase 1-4 branch on
  that exact revision.

Record at least these local audit outputs in the implementing issues:

```bash
rg -l 'CstNode::new|with_replaced_child|build_tree|CstElement::map' \
  seam loom examples fixtures --glob '*.mbt'
rg -l 'ModeRelex(State|Result|Factory)|LexResult::|erase_mode_lexer|TokenBuffer::new_(from_lex|from_mode_relex|with_mode_relex)' \
  loom examples fixtures --glob '*.mbt'
rg -l 'LanguageSpec::new|spec\.(eof_token|reuse_size_threshold|trivia_kinds_raw)' \
  loom examples fixtures --glob '*.mbt'
rg -l 'DamageTracker|damaged_ranges' loom examples fixtures --glob '*.mbt'
```

### Follow-up issue split after acceptance

The 2026-08-05 open-issue audit found no existing implementation issue that
owns these boundaries. Create the following issues only after ADR acceptance.
The measurement-preparation issue must merge first; Phases 1-4 must branch from
its recorded baseline commit.

1. `test(perf): establish the core-ownership benchmark baseline`
   owns the Phase 0 measurement-only commit and recorded baseline artifacts.
2. `fix(core): replace the mutable mode-relex offset handoff`
   owns Phase 1 and its correctness tests.
3. `refactor(seam): store CST metadata policy and seal CstNode`
   owns Phase 2, including EventBuffer migration and seam benchmarks.
4. `refactor(core): seal LexResult and LanguageSpec collection inputs`
   owns Phase 3 and external lexer construction measurements.
5. `refactor(incremental): hide DamageTracker range storage`
   owns Phase 4 as a small independent API migration.
6. `chore(release): verify and document core ownership migration`
   owns Phase 5 after the implementation issues merge.

## Phase 1: close the live mode-relex alias

**Public seam:** `TokenBuffer::update` must produce the same tokens, starts,
diagnostics, and version as a full lex even when a custom mode relexer retains
everything it receives or mutates its private session before returning an
invalid partial result.

- [ ] Add a regression fixture whose custom mode relexer attempts to retain the
  old-offset input and reuse result arrays. Confirm the current API can expose
  the alias before changing the type boundary.
- [ ] Add opaque `OldTokenStarts` with `length()` and `start_at(Int)`. Document
  that an out-of-range index aborts as a programmer error and expose no array or
  backing iterator.
- [ ] Change `ModeRelexState.relex_from` to receive `OldTokenStarts`, never
  `Array[Int]` or an accessor that returns one.
- [ ] Change public mode-aware `TokenBuffer` construction to accept a
  `ModeRelexFactory`, not a standalone state. Add the dedicated
  `TokenBuffer::new_from_mode_relex`, keep `new_from_lex` plain-only, and remove
  public `TokenBuffer::new_with_mode_relex`. Migrate mode-aware callers to the
  dedicated constructor. Keep any initialized state/result fast path
  package-private and pair it with the same factory-derived reset capability.
- [ ] Preserve the facade selection rule: when
  `incremental_relex_enabled=false`, call plain `new_from_lex` and never create
  or invoke the optional mode factory; otherwise select
  `new_from_mode_relex` when a factory is present. Retain the existing opt-out
  test and cover both `examples/html/grammar.mbt` and
  `examples/jsx/grammar.mbt`.
- [ ] Change public `ModeRelexFactory::new` to accept only a fresh-session
  constructor. Implement `ModeRelexFactory::tokenize` through a fresh session;
  keep the combined session/result initializer package-private for built-in
  adapters. Migrate `ModeRelexFactory::new_session_with_initial`,
  `erase_mode_lexer`, and `erase_mode_lexer_factory` and their callers. Have
  public `TokenBuffer::new_from_mode_relex` absorb the package-private combined
  initializer so the cross-package facade does not need private access. Do not
  retain a caller-supplied detached tokenizer as a second authority.
- [ ] Store the current session as a private `Ready(ModeRelexState[T])` or
  `ResetRequired` state. Permit partial re-lex only from `Ready`.
- [ ] Put session-state and commit-eligibility decisions in a deterministic
  transition function. Keep factory/session invocation and atomic buffer
  mutation in the `TokenBuffer` shell; test the transition table independently
  from closure wiring.
- [ ] Group all publicly observable lex state and the private session slot in a
  private committed-state value where practical. Perform one assignment after
  validation and all callbacks so no raised error can expose a partial commit.
- [ ] Make `ModeRelexState`, `ModeRelexFactory`, and `ModeRelexResult` fields
  private. Add the exact public constructors and named factory/session
  operations in the ADR; do not expose their stored closures or result arrays.
- [ ] Make public `ModeRelexResult` construction copy arrays before validating
  the owned copies and copy diagnostics. Raise `LexResultError` for intrinsic
  shape failure, and change the installed `relex_from` callback type to declare
  that exact error. Add a package-private owned constructor for the built-in
  mode lexer.
- [ ] Catch `LexResultError` from `relex_from` as an invalid partial attempt;
  do not catch or translate unrelated defects. Discard the possibly mutated
  session before asking the factory for a replacement.
- [ ] Validate the complete partial result before mutating any committed buffer
  state. Fall back to fresh arrays on a valid shape that is not patchable.
- [ ] On an invalid partial result, discard it and never call `tokenize` on that
  session. Use the retained factory to create and initialize a fresh session for
  `new_source`; use the package-private combined initializer when available,
  otherwise call `tokenize` on the newly created session. Never consult the
  grammar's plain lexer or compare results from independent authorities.
  Atomically commit the replacement session and only a result satisfying the
  normal full-lex token/start/source-bound/EOF invariants.
- [ ] Add `T : Eq` to both public `TokenBuffer` full-result constructors and
  validate their complete initial results before exposing a buffer. Abort with
  distinct invariant messages on malformed plain or mode-aware initial output;
  do not cross-fallback between authorities. Cover both programmer-defect
  paths.
- [ ] Keep an invalid-partial counter in internal instrumentation; do not add an
  incremental-only public diagnostic when full fallback succeeds.
- [ ] If fallback full tokenization remains invalid, raise `LexError`, prove that
  tokens, starts, diagnostics, source, and version retain their pre-update
  values, and mark the mode session as reset-required. Prove that no later
  partial re-lex occurs; the next update must create another fresh session and
  perform a full reset.
- [ ] Add a custom factory fixture whose `relex_from` mutates captured lexer
  state before returning an invalid result. Prove that fallback increments the
  factory's session-creation count, uses a different lexer shell, matches a
  detached full lex produced through another fresh factory session, and
  replaces the session only on successful validation.
- [ ] Run core mode-relex tests and incremental/full-lex parity tests.

## Phase 2: make CST policy enforceable

**Public seam:** a constructed node remains stable after mutation of the input
child array, and reconstruction preserves or rejects metadata policy rather
than silently changing it.

- [ ] Add black-box tests proving public construction copies children and
  exposes only read-only observation.
- [ ] Add tests for equivalent policy acceptance, mismatched child policy
  rejection, `new_unclassified`, and policy-preserving child replacement.
- [ ] Add opaque normalized `CstMetadataPolicy` with semantic equality and hash.
- [ ] Store policy on every `CstNode`; include it in node equality/hash and
  validate node children during construction.
- [ ] Make all `CstNode` fields private and add the minimum scalar/read-only
  accessors fixed by the ADR: kind, text length, structural hash, token count,
  cached error presence, and children.
- [ ] Change `CstNode::new` to require a policy and add
  `CstNode::new_unclassified` for explicit language-agnostic trees.
- [ ] Remove classifier parameters from `with_replaced_child`; reconstruct with
  the receiver policy.
- [ ] Remove classifier parameters from `CstElement::map`; preserve each
  receiver node's policy and reject a mismatched replacement subtree.
- [ ] Require a policy in `build_tree`, `build_tree_interned`,
  `build_tree_fully_interned`, and all three `EventBuffer` methods. Migrate
  language-agnostic callers to an explicit
  `CstMetadataPolicy::unclassified()` value.
- [ ] Keep the stored policy private. Do not add a public policy accessor solely
  to let callers extract and re-inject reconstruction state.
- [ ] Add a package-private owned-child constructor and migrate `EventBuffer`,
  rebase, traversal, and interner hot paths before migrating tests/examples.
- [ ] Migrate all first-party direct field accesses and constructor calls.

## Phase 3: seal lexer and language specifications

**Public seam:** mutating arrays passed to `LexResult` or `LanguageSpec`
constructors after return cannot alter the validated value or parser behavior.

- [ ] Add black-box retained-input mutation tests for `LexResult::with_starts`
  and `LanguageSpec::new`.
- [ ] Make `LexResult` fields private; copy public constructor inputs before
  validating the owned copies; raise the exact `LexResultError` variants fixed
  by the ADR and retain copy-returning compatibility getters. Prove each failure
  returns no opaque result.
- [ ] Audit every `LexResult::LexResult` and `LexResult::with_starts` caller.
  Built-in total lexers must use validated internal construction or handle the
  typed error before installing their callbacks; external migration examples
  must distinguish adapter-contract failure from user-text diagnostics.
- [ ] Keep grammar lexer callbacks total. Add an adapter fixture and migration
  example that catches `LexResultError` inside the installed closure and either
  returns a structurally valid language-specific recovery result plus
  diagnostics or explicitly aborts for the adapter defect. Do not add a generic
  fallback token to Loom core.
- [ ] Preserve `LexResult::from_located_tokens` as a total repair adapter: copy
  its positioned input, diagnose and clamp invalid spans, and finish through
  validated package-private owned construction. Retain black-box tests proving
  that repaired spans produce valid arrays and that no `LexResultError` escapes.
- [ ] Add `length`, `token_at`, `start_at`, and paired read-only iteration.
- [ ] Add package-private owned construction and migrate arrays produced wholly
  inside `loom/core`.
- [ ] Make `LanguageSpec` fields private, copy trivia kinds, construct one
  `CstMetadataPolicy`, and add `K : ToRawKind` to its constructor. Expose only
  `eof_token`, `reuse_size_threshold`, and the copying
  `trivia_kinds_raw`; keep parser-only fields and policy private.
- [ ] Migrate generated specs, grammar interpreter code, examples, and fixtures.
- [ ] Measure public lexer construction. Propose `LexResultBuilder` only if the
  representative end-to-end benchmark crosses the 5% release gate because of
  copying.

## Phase 4: close the mutable-shell representation

**Public seam:** callers can query and update damage through `DamageTracker`
methods but cannot mutate its sorted, non-overlapping range representation.

- [ ] Make `damaged_ranges` private.
- [ ] Add `range_count`, checked `range_at`, and/or iterator observation; do not
  promise immutable snapshot semantics for the mutable tracker itself.
- [ ] Migrate tests away from direct fields and add a black-box ordering/merge
  assertion through the new queries.
- [ ] Confirm no production caller depended on array identity.

## Phase 5: release verification and communication

- [ ] Run `moon info` and review the four generated interfaces in the inventory.
  Add and explain any other changed first-party `.mbti` before release.
- [ ] Run `moon check --deny-warn` and the full release test suite.
- [ ] Run `moon bench -p dowdiness/seam --release`, the existing CST interner and
  construction benchmarks, mode-relex benchmarks, and representative JSON,
  Lambda, and Markdown full/incremental benchmarks.
- [ ] Run the pre-landed `core-ownership` profile against the recorded
  `CORE_OWNERSHIP_BASELINE_SHA`. Keep the default scheduled profile unchanged.
- [ ] Confirm `scripts/bench-check-selftest.sh` still covers the profile parser,
  comparator, missing-row, malformed-output, environment-mismatch, and
  incomplete-sample failures documented in `BENCHMARKS.md`.
- [ ] Compare allocation/time against the recorded
  `CORE_OWNERSHIP_BASELINE_SHA` using the release gates below. Do not use an
  undefined "material regression" judgment.
- [ ] Add changelog migration examples for classified and unclassified CST
  construction, child replacement, custom mode relexing, and lexer results.
- [ ] Update `CHANGELOG.md`, `docs/api/api-contract.md`,
  `BENCHMARKS.md`,
  `docs/architecture/seam-model.md`, `docs/architecture/pipeline.md`,
  `docs/architecture/generic-parser.md`,
  `docs/architecture/lexer-guidelines.md`,
  `docs/correctness/CORRECTNESS.md`, and
  `docs/performance/benchmark_history.md`.
- [ ] Close #783 and its bounded implementation issues only after all acceptance
  gates pass.

### Release benchmark gates

These are migration-specific pre-release gates. They do not replace the
accepted repository-wide detector policy: plain `bench-check.sh` continues to
use the checked-in 15% threshold and scheduled persistence filter. The new
profile reuses the same benchmark-output parser and fail-closed validation so a
second ad-hoc comparison implementation does not drift from it.

- The Phase 0 measurement-only commit adds
  `docs/performance/core-ownership-bench-policy.tsv` with one row per required
  benchmark and columns for relative threshold, absolute threshold, and whether
  the row is required. It also adds the opt-in command
  `bash bench-check.sh --profile core-ownership --baseline-ref <sha> --runs 5`.
- Every required row must run successfully on the measurement-only commit
  before it is recorded as `CORE_OWNERSHIP_BASELINE_SHA`. Rows for the future
  owned CST path use the current internal no-copy construction path with the
  same tree shape and iteration count; implementation commits may change only
  the call needed to reach the new path.
- Benchmark names, input corpora, edit sequences, iteration counts, and output
  units are frozen at the recorded baseline. A candidate-side change to any of
  them invalidates the comparison and requires a new measurement-only baseline,
  not an exception to the release gate.
- Profile row keys are module-qualified as `<module>::<benchmark-name>`. The
  runner prefixes parsed names before combining module outputs, and the policy,
  raw samples, and comparator all use the same qualified key. Duplicate
  qualified keys fail closed.
- The profile captures baseline and candidate samples from clean worktrees at
  the requested revisions, verifies the same MoonBit version, target, machine,
  and power profile, and emits the five raw samples plus a median comparison
  report. A missing required row, malformed output, environment mismatch, or
  incomplete sample set fails closed.
- Store the raw sample and comparison reports as PR or release artifacts and
  record the revisions, environment, and final comparison in
  `docs/performance/benchmark_history.md`.

- Use the recorded `CORE_OWNERSHIP_BASELINE_SHA` as `--baseline-ref`. The
  profile runs each baseline and candidate suite five times and compares the
  median of like-for-like rows. All ownership implementation commits must be
  descendants of that revision.
- Fail full-parse or incremental-parse release rows when the candidate is more
  than 5% slower.
- For sub-microsecond construction rows, fail only when the median regression
  exceeds both 5% and 0.05 microseconds, avoiding a percentage-only noise gate.
- Fail if CST construction through the package-private owned path is more than
  5% slower.
- Verify allocation structurally rather than pretending the timing harness
  measures heap layout: add package-white-box tests showing one
  `CstMetadataPolicy` is created per `LanguageSpec`, every node in one built tree
  retains that same policy value, and node construction creates no new policy.
  Review the final `CstNode` representation to confirm it adds exactly one
  policy field and no per-node wrapper allocation.
- Require identical diagnostics, lossless text, subtree-reuse counts, and
  incremental/full-parse results for every correctness fixture.
- Measure public `LexResult::with_starts` construction with 10,000 tokens. Its
  copy cost is informational unless it makes representative end-to-end lex or
  parse rows more than 5% slower; crossing that threshold blocks release until
  the regression is removed or a separate `LexResultBuilder` decision is
  accepted.
- The Phase 0 preparation commit must include an equal-cardinality mode-relex
  row and JSON, Lambda, and Markdown rows that replay fixed edit sequences. Do
  not substitute one-shot parsing for the incremental session measurement.

## Validation commands

```bash
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon check --deny-warn
NEW_MOON_MOD=0 moon test -p dowdiness/seam
NEW_MOON_MOD=0 moon test -p dowdiness/loom
NEW_MOON_MOD=0 moon bench -p dowdiness/seam --release
NEW_MOON_MOD=0 moon bench -p dowdiness/loom/core --release
NEW_MOON_MOD=0 moon bench -p dowdiness/json --release
NEW_MOON_MOD=0 moon bench -p dowdiness/lambda/benchmarks --release
NEW_MOON_MOD=0 moon bench -p dowdiness/markdown --release
bash bench-check.sh --validate
bash bench-check.sh --profile core-ownership \
  --baseline-ref <CORE_OWNERSHIP_BASELINE_SHA> --runs 5
```

Run repository CI-equivalent checks in addition to these issue-specific gates.
Reject the release comparison if the recorded baseline is not an ancestor of
every ownership implementation commit or if the frozen benchmark workload was
changed after baseline capture.

## Stop conditions

- A public read-only type can be converted back to a mutable alias of internal
  storage.
- Policy compatibility requires a global mutable identity allocator.
- The stored policy exceeds the footprint or throughput gates above without an
  accepted mitigation.
- A newly discovered production consumer requires a compatibility window not
  covered by the clean pre-1.0 migration.
- An external zero-copy lexer API depends on an unenforceable ownership promise.
