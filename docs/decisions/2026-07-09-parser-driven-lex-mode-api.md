# ADR: Parser-Driven Lex Mode API for ParserContext

**Date:** 2026-07-09
**Status:** Accepted
**Issue:** [#532](https://github.com/dowdiness/loom/issues/532)
**Follow-up:** [#509](https://github.com/dowdiness/loom/issues/509), `SwitchLexMode` grammar IR node
**Implementation plan:** N/A — open-question resolution, API already landed.

## Context

`ParserContext[T, K]` exposes methods for grammar-author parse functions. Issue
#532 proposed adding `lex_mode()` and `set_lex_mode(...)` so that `parse_root`
can query and switch the lex mode mid-parse, unblocking `SwitchLexMode` IR nodes
in the grammar IR emitter (#509).

The API surface was partially implemented while the issue was open:
- `ParserContext.lex_mode : Int` field (private)
- `lex_mode() -> Int` and `set_lex_mode(Int) -> Unit` public accessors
- `Checkpoint` captures/restores `lex_mode`
- Constructors initialize to `0`
- Tests cover defaults, updates, and checkpoint restore

However, four open questions remained unresolved. The critical gap: the
`lex_mode` field is disconnected from the lexer pipeline. `ModeRelexState`
manages its own `modes_ref` array (inside `erase_mode_lexer` closures), and
re-lex convergence (`mode_relex_converged`) checks against that array alone.
`set_lex_mode` writes to an independent system with no consumers in the lexer
path.

## Decision

Four resolutions, one per open question:

### Q1: Type parameter `M` vs erased `Int` — Use `Int`

The existing `Int` field is correct and should not be changed.

- `ParserContext[T, K]` is already doubly generic; a third type parameter `M`
  would infect every usage site — grammar structs (`Grammar[T, K, Ast]`),
  factories, pipeline wrappers, and all downstream consumers.
- `Int` is cheap to copy, trivially comparable (`Eq` for convergence), and
  integrates cleanly with the `Checkpoint` snapshot (no heap copy of a generic
  `M` value).
- Each grammar maps `Int` → semantic mode at its own level, typically via the
  lexer's step function (closed over inside `erase_mode_lexer`).
- Parallels `erase_mode_lexer`, which already erases `M` into closures before
  the grammar sees the mode state.

### Q2: Current-token vs next-token semantics — Parser-side only; temporary non-implementation

`set_lex_mode` changes a parser-side scalar. During a fresh parse (tokenization
completed before `ParserContext` construction), it does NOT retroactively alter
already-lexed tokens — the token buffer is immutable during a single parse
pass. Mode switches activated via `set_lex_mode` only take effect on the *next*
incremental re-lex (after an edit), once #509's committed mode trace is
implemented.

This is not endorsed as final semantics for #509's `SwitchLexMode` IR node. It
is a temporary consequence of the eager-tokenization architecture. #509 must
define the actual mechanism — a committed mode-transition trace (see
Integration Constraint below) — before parser-driven mode switching works on
any parse path.

The grammar *can* read `lex_mode()` for conditional parsing decisions during
the same parse. The mode value is snapshot by `Checkpoint` and restored by
`restore` — speculative parse attempts that change `lex_mode` have their
changes discarded on rollback. Only committed parse paths should contribute
to a future mode-transition trace.

**Ruled out** — suffix re-lex on `set_lex_mode`: unsafe with speculative
parsing. `ParserContext::restore` (parser_events.mbt:188-204) rolls back
parser fields (`position`, `events`, `lex_mode`) but not the `TokenBuffer`'s
token array — token access is through fixed closures
(`get_token`/`get_start`/`get_end`). If `set_lex_mode` directly mutated
`TokenBuffer` tokens and speculative parsing then failed, the suffix tokens
would remain permanently replaced after restore.

### Q3: Incremental re-lex interaction — Convergence check needs no change; committed trace as input

The re-lex convergence algorithm (`mode_relex_converged`) checks:

```
mode == old_modes[old_idx] &&
pos == old_starts[old_idx] + edit_delta
```

This works correctly with `Int` (which is `Eq`). No algorithmic change is
needed.

The open question is *whether the re-lex starting mode should come from
`ParserContext.lex_mode` at the edit position or from the old mode array*.

The answer is **neither** — the re-lex starting mode must come from a
**persisted committed mode-transition trace** produced by the previous
successful parse. See Integration Constraint below for the full rationale.

The convergence algorithm is correct regardless of which source provides the
starting mode.

### Q4: Shared mode type — Independent contracts; `erase_mode_lexer` is the bridge

`ModeLexer[T, M]` has its own generic `M` (the lexer's native mode type, which
may be a rich enum like `MarkdownLexMode`). `ParserContext` uses `Int` (an
opaque grammar-level index). These are independent by design:

- `M` is the **lexer's** native type — can be an enum with meaningful variant
  names that the `lex_step` dispatches on.
- `Int` is the **grammar IR's** opaque mode identifier that the emitter
  generates switch/if chains around.
- `erase_mode_lexer` absorbs `M` into closure-captured state before the grammar
  layer ever sees a `ModeRelexState`. The two types never share a common bound.

**Payload constraint**: `Int` erasure is acceptable for closed, parameterless
mode identifiers (simple tag-like variants). Grammars whose mode types carry
payloads (e.g. Markdown's `CodeBlock(Int)` — fenced depth, or
`HtmlBlockUntil(String)` — raw content marker) cannot encode those parameters
in the `Int`. The grammar must either:

- Own the payload state itself (store depth in its own scope or via a side
  channel), using `lex_mode()` only for the mode discriminant; or
- Wait for #509 to define a generated mode table / payload channel that maps
  grammar-level `Int` mode values back to the lexer's parameterized `M` variants.

No type-level bridge between `ParserContext:Int` and `ModeLexer:M` is needed
at the framework level. `erase_mode_lexer` already absorbs `M` into closures.
How the committed mode-transition trace feeds parser-side `lex_mode` into the
re-lex starting mode is defined by #509 (see Integration Constraint above).

## Integration Constraint: committed mode-transition trace

For `SwitchLexMode` (#509) to produce correct incremental behavior, the
parser-driven lex mode must be preserved as a **committed mode-transition
trace** — a per-position mapping of `(token_idx, lex_mode)` pairs persisted
at the end of a successful parse. When `TokenBuffer::update` triggers
re-lex, the `Int` from the trace at the edit position must be translated to
the lexer's native `M` type before it can be passed as the starting mode to
`mode_relex_recovering` (which today reads `old_modes[start_tok_idx]` and has
no starting-mode parameter). Two options for #509:

- Change `ModeRelexState.relex_from` (or its internal `mode_relex_recovering`)
  to accept an explicit starting `M` parameter; or
- Store the trace as native `M` values (requiring the ``erase_mode_lexer``
  call site to close over the `Int → M` mapping).

This is the only integration path that satisfies all constraints:

- **Speculative parse safety**: A mode switch attempted speculatively (inside
  a `checkpoint`/`restore` bracket) has its effects discarded on `restore` —
  the mode trace is only produced from the committed (non-restored) parse path.
  Live mutation of `TokenBuffer` from within `set_lex_mode` is ruled out
  (see Q2 ruled-out section).
- **Non-interference with lexer mode tracking**: The committed trace is
  separate from `ModeRelexState.modes_ref` (the lexer's own mode array). The
  re-lex convergence check (`mode_relex_converged`) still compares against
  the lexer mode's output; the committed trace only determines the *starting*
  mode, not the convergence target.
- **Fresh-parse fallback**: On the first parse of a document (no previous
  mode trace exists), the re-lex starting mode defaults to `lexer.initial_mode`
  from the ``ModeLexer``. Parser-driven mode switching is not available on
  fresh parses — this is a temporary non-implementation, not final semantics.

The trace is not yet implemented. #509 must define:
- Storage format for the trace (e.g. a parallel ``Array[Int]`` on
  ``ParseSnapshot``, or an inlined array on ``TokenBuffer``)
- How the ``Int → M`` translation reaches ``mode_relex_recovering`` (either
  an API change to accept a starting ``M``, or trace stored as ``M`` values)
- The condition for considering a parse "committed" (not speculatively rolled
  back)
- Serialization for persistence across consecutive incremental parses

## Rationale

All four decisions favor keeping the existing architecture stable and deferring
the integration wire to #509. The existing `ModeLexer` + `erase_mode_lexer`
architecture already handles pure-lexer mode switching (the markdown example
works end-to-end with mode-aware tokenization and convergence-based re-lex).
The `ParserContext` API exists to provide an *addressable contract* that the
grammar IR emitter can target — not yet to drive the lexer in real time.

Attempting to integrate `ParserContext.lex_mode` into the mode-lexer pipeline
now, before `SwitchLexMode` IR semantics are defined, risks designing the wrong
abstraction. The convergence algorithm itself needs no change regardless of the
integration point.

## Consequences
### Positive

- All four open questions are resolved with documented rationale.
- The existing `ParserContext` API surface defines a stable grammar-author
  contract that #509's `SwitchLexMode` IR nodes can target.
- No architectural changes needed to `ModeLexer`, `TokenBuffer`, or re-lex
  convergence algorithm.
- Ruled-out approaches (suffix re-lex on `set_lex_mode`) are documented with
  rationale, preventing wasted design effort in #509.

### Negative

- `set_lex_mode` is **not a working parser-driven lex feature in this ADR**.
  It is API scaffolding only:
  - During a fresh parse: writes to a field nothing reads — zero effect on
    the token stream.
  - During incremental re-lex: no integration path exists yet. The mode
    array inside `ModeRelexState` is independent.
- The fresh-parse dead-letter is a **temporary non-implementation**, not
  acceptable final semantics. #509 must define a committed mode-transition
  trace before parser-driven mode switching works on any parse path.
- Grammars with parameterized `ModeLexer` mode types (`CodeBlock(Int)`,
  `HtmlBlockUntil(String)`) cannot capture payload through `Int` erasure.
  Must own payload state themselves or wait for #509's generated mode table.

### Deferred to #509

- **Committed mode-transition trace** — storage format, commitment boundary
  (committed vs speculatively rolled back), and re-lex input wire.
- **Payload channel** — mapping grammar-level `Int` mode values back to the
  lexer's parameterized `M` variants.
- **IR semantics** — `SwitchLexMode(String, Expr[T,K])` emission contract
  defining when and how mode switches are recorded.

### Status

The `ParserContext` API surface (field + accessors + checkpoint + tests) is
stable API scaffolding. The feature it enables — parser-driven mode switching
— is **not functional** until #509 defines the committed mode-transition
trace, payload channel, and IR semantics. #532 should be closed as
**API contract defined; integration deferred to #509**.

## Related documents

- [ADR 2026-06-13: ParserContext Method-Only Boundary](2026-06-13-parsercontext-method-only-boundary.md)
  — established the stable grammar-author API as method-only, supporting the
  addition of `lex_mode()` / `set_lex_mode()` as named accessors.
