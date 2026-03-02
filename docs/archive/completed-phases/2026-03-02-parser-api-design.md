# Parser API Simplification and Reconciliation Design

**Date:** 2026-03-02
**Status:** Complete

## Problem

`loom` exposes two parsers — `IncrementalParser` and `ParserDb` — with four distinct problems:

1. **Confusing names.** `IncrementalParser` implies `ParserDb` is not incremental. Both are. The names reflect implementation details (algorithm name, Salsa "db" metaphor) rather than what matters to callers: how to update the parser.
2. **Asymmetric feature sets.** `IncrementalParser` is missing `diagnostics()` and `reset()`. `ParserDb` is missing `get_source()` and persistent interning. Neither has CST equality backdating in both places it belongs.
3. **Leaked internals.** `IncrementalParser` has publicly mutable fields (`source`, `tree`, `syntax_tree`, `last_reuse_count`) that callers can corrupt, plus implementation-detail methods (`interner_size`, `interner_clear`, `stats`).
4. **No decision guide.** No documentation explains when to choose each parser or why both exist.

## Investigation Findings

### Both parsers are incremental — at different granularities

| | `IncrementalParser` | `ParserDb` |
|---|---|---|
| **Incremental at** | CST node level — individual nodes reused within a parse | Pipeline stage level — stages skipped when output is equal |
| **How** | `ReuseCursor` + damage tracking | `Memo[CstStage]::Eq` + `Memo[Ast]::Eq` |
| **Update model** | Caller provides `Edit { start, old_len, new_len }` | Caller provides new source string |
| **Reactive composition** | Impossible — stateful between calls | Natural — `Signal[String]` → `Memo` chain |

The word "incremental" in `IncrementalParser` is misleading. Both are incremental. The real distinction is **how change is communicated** and **whether state is caller-owned or system-owned**.

### Statefulness analysis

`IncrementalParser` holds two kinds of state:

- **Old syntax tree** — needed for `ReuseCursor`. Can be externalized (passed as parameter, stored by caller). This is what blocks reactive composition.
- **Interners** — token/node deduplication. Affect memory identity, not structural equality (`CstNode::Eq` is unaffected). Safe to make global.

Rust-analyzer's interner (`crates/intern`) is **global and static** — process-wide, never cleared, GC'd when Arc count drops. This eliminates "who owns the interner?" entirely and improves deduplication across all parsers and sessions.

### Feature gaps are oversights, not trade-offs

- `IncrementalParser` missing CST equality skip: no principled reason, just not added.
- `ParserDb` missing persistent interning: no principled reason, just `parse_tokens_indexed` called without interners.
- Both gaps are fixable without API changes.

## Design

### Phase 1 — Global interners

Move `Interner` and `NodeInterner` from `IncrementalParser` struct to module-level globals in `seam`:

```moonbit
// seam — initialized once, used by all parse calls
let global_interner : Interner = Interner::new()
let global_node_interner : NodeInterner = NodeInterner::new()
```

`parse_tokens_indexed` uses them automatically. Both parsers get persistent interning for free with no API change.

**Consequences:**
- Remove `interner`, `node_interner` fields from `IncrementalParser`
- Remove `Interner`/`NodeInterner` params from `IncrementalLanguage` vtable
- Drop `interner_size()`, `node_interner_size()`, `interner_clear()` from public API
- `ParserDb` factory gains persistent interning automatically (gap closed)

### Phase 2 — Stateless core function

Extract the incremental parse algorithm as a function that takes the old tree as a parameter:

```moonbit
pub fn parse_with_reuse(
  source  : String,
  edit    : Edit,
  old_cst : CstNode?,  // None → full parse; Some → node-level reuse
  grammar : Grammar[T, K, Ast],
) -> (CstNode, Array[Diagnostic], Int)  // (new_cst, diags, reuse_count)
```

`IncrementalParser` becomes a thin **session wrapper** that stores `old_cst` between calls:

```moonbit
pub struct IncrementalParser[Ast] {
  priv lang             : IncrementalLanguage[Ast]
  priv source           : String
  priv old_cst          : CstNode?   // wrapper owns session state
  priv prev_cst_hash    : Int?       // for CST equality skip
  priv last_diags       : Array[String]
  priv last_reuse_count : Int
}
```

The stateless core can be tested independently and reused without `IncrementalParser`'s session overhead.

### Phase 3 — API surface fixes

**`IncrementalParser` additions:**
- `diagnostics() -> Array[String]` — surfaces `last_diags`; add `get_diagnostics` closure to `IncrementalLanguage` vtable
- `reset(source: String) -> Ast` — clears `old_cst` and `prev_cst_hash`, runs full parse; needed for mode-switching in hybrid editors
- CST equality check before `to_ast`: compare `new_cst.hash` against `prev_cst_hash`; if equal, return cached tree

**`IncrementalParser` removals:**
- `stats() -> String` — returns only source length; not useful
- `interner_size()`, `node_interner_size()`, `interner_clear()` — implementation details, removed by Phase 1

**`IncrementalParser` visibility fix:**
- Add `priv` to `source`, `tree`, `syntax_tree`, `last_reuse_count` — currently public mutable, bypasses all invariants

**`ParserDb` addition:**
- `get_source() -> String` — one-liner: `self.source_text.get()`

### Phase 4 — Renaming

The names should reflect **how change is communicated**, not the algorithm name:

| Old | New | Rationale |
|---|---|---|
| `IncrementalParser[Ast]` | `ImperativeParser[Ast]` | You drive it step-by-step with explicit commands |
| `ParserDb[Ast]` | `ReactiveParser[Ast]` | Source is a signal; memos react to changes |
| `IncrementalLanguage[Ast]` | `ImperativeLanguage[Ast]` | Internal vtable — matches type name |
| `new_incremental_parser` | `new_imperative_parser` | Consistent with type name |
| `new_parser_db` | `new_reactive_parser` | Consistent with type name |
| `incremental_parser.mbt` | `imperative_parser.mbt` | File matches type |
| `incremental_language.mbt` | `imperative_language.mbt` | File matches type |
| `parser_db.mbt` | `reactive_parser.mbt` | File matches type |

`Imperative` / `Reactive` is a well-established CS duality. Both names correctly imply incremental behavior — they just describe *how* change flows.

### Phase 5 — Documentation

Three new files:

| File | Content |
|---|---|
| `docs/decisions/2026-03-02-two-parser-design.md` | ADR: why two parsers, four distinguishing axes, design rationale |
| `docs/api/choosing-a-parser.md` | Decision guide: when to use each, comparison table, examples |
| `docs/api/imperative-api-contract.md` | Mirrors `pipeline-api-contract.md` for `ImperativeParser` |

Updates: `docs/api/reference.md` section 6, `docs/README.md`.

## Reconciled feature table

After all phases:

| Capability | `ImperativeParser` | `ReactiveParser` |
|---|---|---|
| Node-level CST reuse | ✓ (requires Edit) | ✗ — no edit location |
| CST equality skip | ✓ (Phase 3) | ✓ |
| Persistent interning | ✓ (Phase 1) | ✓ (Phase 1) |
| `diagnostics()` | ✓ (Phase 3) | ✓ |
| `get_source()` | ✓ | ✓ (Phase 3) |
| `reset()` | ✓ (Phase 3) | via `set_source()` |
| Reactive `@incr` composition | ✗ — stateful | ✓ |
| Caller must track edit positions | ✓ | ✗ |

The only reason to choose `ImperativeParser` over `ReactiveParser` is node-level reuse — and its only cost is that the caller must track edit positions.

## Usage by context

| Context | Parser | Reason |
|---|---|---|
| Text editor / CRDT text ops | `ImperativeParser` | CRDT op → `Edit` → node reuse |
| Language server / build tool | `ReactiveParser` | Source string → reactive graph |
| Projectional editor import | `ReactiveParser` | One-shot text → AST bootstrap |
| Projectional editing loop | Neither — `@incr` directly | AST is primary artifact |
| Hybrid editor text input path | `ImperativeParser` | Token-level edits → structural ops |
| Hybrid editor mode switch | `ImperativeParser::reset()` | Resync after structural edit changes text |

## Future direction: toward typed holes

The current design produces **untyped error nodes** in the CST when input is invalid. The Hazel project's research trajectory (Hazelnut 2017 → tylr 2022 → teen tylr 2023) shows that the correct long-term answer is **typed holes**: first-class AST constructs that:

- Carry type context from bidirectional type checking
- Allow evaluation and type checking to proceed through incomplete expressions
- Serve as the merge point for CRDT conflicts (Grove, POPL 2025)
- Enable "no meaningless editor states" — every editor state has a well-defined type

Hazel's own research found pure structure editing has fundamental UX problems (selection rigidity, term multiplicity, viscosity). Their solution — "gradual structure editing with obligations" (teen tylr) — is closely analogous to what `ImperativeParser` already does at the token level. The key upgrade is enriching error recovery output from untyped error nodes to typed holes.

**Architectural trajectory:**

```
Today:
  text → ImperativeParser → CST (untyped error nodes) → AST → type check separately

Near term:
  text → ImperativeParser → CST (typed holes) → AST
                                 ↓ @incr
                            live type check + evaluation through holes

Long term (teen tylr-inspired):
  token-level tiles → obligations → typed AST with holes
                                       ↓ @incr
                                  live type check + evaluation + multiple projections
```

`ImperativeParser` remains relevant throughout — it is the text editing input path that produces the raw token stream from which structure is derived. The evolution enriches what it produces, not whether it exists.

The `@incr` reactive layer (foundation of `ReactiveParser`) becomes increasingly central as more of the pipeline — type checking, evaluation, view projection — moves into reactive memos.

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252) — CRDT algorithm used in this project
- [rust-analyzer interner](https://github.com/rust-lang/rust-analyzer/tree/master/crates/intern) — global static interner design
- [Total Type Error Localization and Recovery with Holes (POPL 2024)](https://dl.acm.org/doi/10.1145/3632910) — marked lambda calculus, Hazel
- [tylr: A Tiny Tile-Based Structure Editor (TyDe 2022)](https://dl.acm.org/doi/10.1145/3546196.3550164)
- [Gradual Structure Editing with Obligations (VL/HCC 2023)](https://hazel.org/papers/teen-tylr-vlhcc2023.pdf)
- [Grove: Collaborative Structure Editor (POPL 2025)](https://hazel.org/papers/grove-popl25.pdf)
