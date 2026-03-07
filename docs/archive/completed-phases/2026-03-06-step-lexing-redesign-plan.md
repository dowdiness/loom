# loom Step-Based Lexing Redesign Plan

**Date:** March 6, 2026  
**Status:** Complete  
**Scope:** `loom/`, `examples/lambda/` (and follow-up example grammars)

## Goal

Replace failure-driven lexing (`tokenize(...) raise LexError`) as the primary resilience path with a step-based, progress-guaranteed lexing contract that preserves valid prefixes and supports deterministic recovery.

## Why This Change

Current resilient fallback in `TokenBuffer::new_resilient` is still heuristic and can mis-handle tokenizers that are not monotone over prefixes. A step-based contract makes recovery explicit and removes guesswork.

## Design Principles

1. Lexer recovery decisions must be data-driven, not inferred from success/failure alone.
2. Every lex step must guarantee forward progress or explicit completion.
3. Existing grammars should migrate with minimal breakage via an adapter phase.
4. Core remains language-agnostic and strongly typed.

## Constraints

- MoonBit traits cannot be generic in the needed way for a single core trait over arbitrary token type `T`.
- Therefore core API should use dictionary passing for generic typing, with optional language-side traits for ergonomics.

## Proposed Contract

### Core Types (new)

- `LexStep[T]`
  - `Produced(Array[TokenInfo[T]], next_offset : Int)`
  - `Invalid(at : Int, width : Int, message : String)`
  - `Incomplete(at : Int, expected : String)`
  - `Done`

- `PrefixLexer[T]`
  - `lex_step : (source : String, start : Int) -> LexStep[T]`

### Resolved Policy Decisions

1. `Incomplete` handling:
   - Lexer step path emits `error_token` plus diagnostic (not `incomplete_kind`).
   - Rationale: lexer produces language token type `T`; `incomplete_kind` belongs to parser/CST kind space.
   - Span policy:
     - if `at < source.length()`: emit error token `[at, source.length())`
     - if `at >= source.length()`: emit zero-width error token at EOF

2. Legacy `tokenize` lifecycle:
   - Keep as compatibility path during migration.
   - Mark as deprecated when step path lands.
   - Remove after all in-repo grammars migrate and one release cycle passes.

3. Contract helper:
   - Add reusable core test helper to validate lexer contract laws (determinism, progress, termination).

### Core Laws (must hold)

1. Deterministic: same `(source, start)` returns same `LexStep`.
2. Progress: `Produced` must have `next_offset > start` unless EOF; `Invalid` must advance by `max(width, 1)`.
3. Stability: `Invalid.at` identifies the first irrevocably invalid byte for this step.
4. Safety: no infinite loops when repeatedly stepping from `0..EOF`.

## High-Level API Evolution

### `loom/src/grammar.mbt`

- Keep legacy `tokenize` for compatibility.
- Add `prefix_lexer : @core.PrefixLexer[T]?`.
- Keep `error_token : T?` (already added) for error token emission policy.

### `loom/src/core/token_buffer.mbt`

- Add `TokenBuffer::new_from_steps(...)` as primary resilient constructor.
- Keep `new_resilient(...)` temporarily as compatibility fallback.
- Implement lex loop purely from `LexStep` (no binary-search probing).

### `loom/src/factories.mbt`

- Precedence in parser construction:
  1. `prefix_lexer` present -> step-based path (preferred)
  2. else legacy `tokenize` path (existing behavior / transitional)

## Phased Implementation

### Phase 0: Contract + Scaffolding

Files:
- `loom/src/core/token_buffer.mbt`
- `loom/src/core/pkg.generated.mbti`
- `loom/src/grammar.mbt`
- `loom/src/pkg.generated.mbti`

Tasks:
1. Add `LexStep[T]` and `PrefixLexer[T]` in core.
2. Add `prefix_lexer` optional field in `Grammar`.
3. Add doc comments specifying laws and failure semantics.

### Phase 1: Step-Based TokenBuffer Path

Files:
- `loom/src/core/token_buffer.mbt`
- `loom/src/core/token_buffer_resilient_wbtest.mbt`

Tasks:
1. Implement `new_from_steps(...)` with deterministic advancement.
2. Ensure `Invalid` always emits one error token minimum width.
3. Define `Incomplete` handling policy (emit incomplete/error placeholder token and terminate).
4. Add precise tests for:
   - preserved valid prefixes
   - multi-error input
   - incomplete-at-EOF behavior
   - progress (no infinite loop)
5. Incremental scope for this phase:
   - If `prefix_lexer` is present, `TokenBuffer::update` may initially use safe full re-lex via step API.
   - Windowed incremental step re-lex optimization is deferred until correctness is stable.

### Phase 2: Factory Integration

Files:
- `loom/src/factories.mbt`
- `loom/src/factories_wbtest.mbt`

Tasks:
1. Wire step-based path in full and incremental parse closures.
2. Keep legacy path untouched when `prefix_lexer` is `None`.
3. Add integration tests proving step path correctness and reuse behavior remains stable.

### Phase 3: Lambda Migration (Reference Implementation)

Files:
- `examples/lambda/src/lexer/*`
- `examples/lambda/src/grammar.mbt`
- `examples/lambda/src/*test*.mbt`

Tasks:
1. Implement lambda `PrefixLexer[@token.Token]`.
2. Plug into `lambda_grammar` via `prefix_lexer=Some(...)`.
3. Run differential tests: incremental == full parse under edit sequences.

### Phase 4: Broader Adoption + Deprecation

Files:
- remaining example grammars
- docs

Tasks:
1. Migrate additional grammars.
2. Mark binary-search fallback path as deprecated.
3. Decide timeline for removing `new_resilient` legacy probing behavior.

## Verification Matrix

For each phase, run:

```bash
cd seam && moon test && moon check
cd loom && moon test && moon check
cd examples/lambda && moon test && moon check
```

Add targeted property tests in `loom/src/core`:

1. Lex-step progress property.
2. Determinism property.
3. Recovery stability property (`Invalid` spans monotone in replay).

## Rollout Strategy

1. Merge phases 0-2 first with compatibility kept.
2. Migrate lambda and validate in CI.
3. Migrate other examples incrementally.
4. Remove deprecated path only after all in-repo grammars are on step-based API.

## Risks and Mitigations

1. **Risk:** Step contract implemented inconsistently by language packages.  
   **Mitigation:** Add reusable contract test suite helper in core.

2. **Risk:** Performance regressions in high-frequency edits.  
   **Mitigation:** Add benchmark comparisons old vs step path.

3. **Risk:** Interface churn for downstream users.  
   **Mitigation:** Keep legacy `tokenize` path through at least one release cycle.

## Deliverables Checklist

- [x] `LexStep[T]` and `PrefixLexer[T]` in core
- [x] `Grammar.prefix_lexer` optional field
- [x] Step-based token buffer constructor
- [x] Factories wired to prefer step-based lexing
- [x] Lambda grammar migrated
- [x] Differential/property tests for step contract
- [x] Deprecation notes for legacy fallback path

## Open Decisions
None for Phase 0-1. Any further policy changes should be tracked as explicit amendments to this document.
