# Roadmap: Stabilized Incremental Parser

**Created:** 2026-02-01
**Updated:** 2026-03-02
**Status:** Active — Phases 0-7 + NodeInterner + let bindings + Grammar abstraction (bridge factories) + loom extraction + rabbita monorepo migration complete; next: Typed SyntaxNode views, Grammar Expansion (type annotations, multi-expression files)
**Goal:** A genuinely incremental, architecturally sound parser for lambda calculus (and beyond) with confidence in every layer.

---

## Honest Assessment of Current State

Before planning forward, we need an unflinching look at where we are. The existing codebase has good bones in some areas but critical gaps in others.

### What Actually Works

1. **Recursive descent parser** (`parser.mbt:72-227`) - Correct, clean, well-tested. Produces `TermNode` with position tracking. This is solid.

2. **Lexer** (`lexer.mbt`) - Correct tokenization with position tracking (`TokenInfo`). Handles Unicode lambda, keywords, multi-digit integers.

3. **Damage tracking** (`damage.mbt`) - Wagner-Graham algorithm correctly identifies damaged ranges after edits. The algorithm is sound.

4. **Position adjustment** (`incremental_parser.mbt:144-186`) - Shifts tree node positions after edits. Handles before/after/overlapping cases. **Caveat:** When a node overlaps the edit, the code adjusts children recursively but does NOT adjust the overlapping node's own `end` by the edit delta (lines 172-184). This is harmless today because overlapping nodes are always fully reparsed, but it would be a bug if Phase 4's subtree reuse tried to use the adjusted tree for granular decisions. The green tree architecture (Phase 2) makes this moot by using widths instead of absolute positions.

5. **Data structures** - `TermNode`, `TermKind`, `Edit`, `Range` are well-designed and tested.

6. **Test suite** - 363 tests passing, including property-based tests and Phase 3 fuzz tests. Good coverage.

### What Does Not Work (Architectural Gaps)

**Phase 0 (completed 2026-02-01) removed the dead cache infrastructure.** `TokenCache`, `ParseCache`, and `RecoveringParser` have been deleted. The incremental parser now honestly does:
1. Track damage (works)
2. Check whole-tree reuse (works when damage is outside tree bounds)
3. Full reparse (fallback for all other cases)

### Error Recovery ✅ (Phase 3 Complete)

**Phase 3 (completed 2026-02-03) implemented integrated error recovery.** The parser now:
- Uses synchronization points (`RightParen`, `Then`, `Else`, `EOF`) for recovery
- Produces partial trees with `ErrorNode`/`ErrorToken` interspersed among valid nodes
- Reports multiple errors per parse (up to `max_errors = 50`)
- Continues parsing after errors, recovering at grammar boundaries
- Terminates on any input (fuzz-tested with random token sequences)

### CRDT Integration is Conceptual

`crdt_integration.mbt` provides `ast_to_crdt()` and `crdt_to_source()` conversion functions. This is a mapping layer, not a CRDT integration. There is no:
- Conflict resolution
- Concurrent edit handling
- Operation-based synchronization
- Actual CRDT data structure

### Summary

| Component | Status |
|-----------|--------|
| Recursive descent parser | **Correct** — `parse()`, `parse_tree()`, `parse_cst()` paths |
| Lexer | **Correct** — trivia-inclusive; emits `Whitespace` tokens |
| Damage tracking | **Correct** — Wagner-Graham algorithm |
| Position adjustment | **Correct** — width-based via `SyntaxNode` (no absolute-position bug) |
| ~~Token cache~~ | **Deleted** (Phase 0) |
| ~~Parse cache~~ | **Deleted** (Phase 0) |
| Incremental lexer | **Complete** (Phase 1) — `TokenBuffer` splice-based re-lex |
| Green tree / CST | **Complete** (Phase 2) — `CstNode`, `SyntaxNode`, `EventBuffer`, `seam/` package |
| Error recovery | **Complete** (Phase 3) — sync-point recovery, `ErrorNode`, diagnostics |
| Subtree reuse | **Complete** (Phase 4) — `ReuseCursor` with 4-condition protocol |
| Generic parser framework | **Complete** (Phase 5) — `ParserContext[T,K]`, `LanguageSpec`, `parse_with` |
| Generic incremental reuse | **Complete** (Phase 6) — `ReuseCursor[T,K]` in `loom/src/core/`, `node()`/`wrap_at()` |
| Reactive pipeline | **Complete** (Phase 7; TokenStage removed — see ADR 2026-02-27) — `ReactiveParser`: `Signal[String]`→`Memo[CstStage]`→`Memo[AstNode]` |
| SyntaxNode API | **Complete** — `SyntaxToken`, `SyntaxElement`, `all_children`, `find_at`, `tight_span` |
| `cst` field privacy | **Complete** — `.cst` is private; all callers use `SyntaxNode` methods |
| CRDT integration | **Conversion functions** — `ast_to_crdt`, `crdt_to_source`; no conflict logic |
| NodeInterner | **Complete** (2026-02-28) — `Interner` + `NodeInterner` wired into `ImperativeParser` and `parse_cst_recover` |
| Grammar abstraction | **Complete** (2026-03-01) — `Grammar[T,K,Ast]` + `new_imperative_parser`/`new_reactive_parser` in `loom/src/bridge/`; deleted ~240 lines of lambda vtable boilerplate |
| Infrastructure extraction (dowdiness/loom) | **Complete** (2026-03-01) — moved `core`, `bridge`, `pipeline`, `incremental`, `viz` to `loom/` sibling module; zero .mbt edits |
| Typed SyntaxNode views | **Planned** — Phase 3 of SyntaxNode-first layer design |

---

## Target Architecture

The end state is a parser where every layer earns its existence. No dead infrastructure. Every component is connected and contributes measurable value.

```
                        +-----------------------+
                        |     Edit Protocol     |
                        |  (apply, get_tree)    |
                        +-----------+-----------+
                                    |
                        +-----------v-----------+
                        |   Incremental Engine  |
                        |   - Damage tracking   |
                        |   - Reuse decisions   |
                        |   - Orchestration     |
                        +-----------+-----------+
                                    |
                  +-----------------+------------------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |  Incremental Lexer  |            |  Incremental Parser   |
       |  - Token buffer     |            |  - Subtree reuse at   |
       |  - Edit-aware       |            |    grammar boundaries |
       |  - Only re-lex      |            |  - Checkpoint-based   |
       |    damaged region   |            |    validation         |
       +----------+----------+            +-----------+-----------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |    Token Buffer     |            |   Green Tree (CST)    |
       |  - Contiguous array |            |  - Immutable nodes    |
       |  - Position-tracked |            |  - Structural sharing |
       |  - Cheaply sliceable|            |  - Lossless syntax    |
       +---------------------+            +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Red Tree (Facade)   |
                                          |  - Absolute positions |
                                          |  - Parent pointers    |
                                          |  - On-demand          |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Typed AST (Lazy)    |
                                          |  - Semantic analysis  |
                                          |  - Derived from CST   |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Error Recovery      |
                                          |  - Integrated in      |
                                          |    parser loop        |
                                          |  - Sync point based   |
                                          |  - Multiple errors    |
                                          +-----------------------+
```

### Architectural Principles

1. **No dead infrastructure.** Every cache, buffer, and data structure must be read by something during the parse pipeline. If it's not read, it doesn't exist.

2. **Immutability enables sharing.** Green tree nodes are immutable. When nothing changed, the old node IS the new node - not a copy, the same pointer. This is the foundation of incremental reuse.

3. **Separation of structure and position.** Green tree nodes store widths (relative sizes). Red tree nodes compute absolute positions on demand. This means structural identity is independent of position - moving a subtree doesn't invalidate it.

4. **Incremental lexing is the first real win.** Re-tokenizing only the damaged region, then splicing into the existing token buffer, gives the parser unchanged tokens for free.

5. **Subtree reuse at grammar boundaries.** Recursive descent can't validate arbitrary nodes like LR parsers, but it CAN check: "at this grammar boundary, does the old subtree's kind match, and are both the leading and trailing token contexts unchanged?" If all checks pass, skip parsing and reuse. The trailing context check is essential because a node's parse can depend on what follows it (see Phase 4, section 4.2.1).

6. **Error recovery is part of the parser, not around it.** The parser must be able to record an error, synchronize to a known point, and continue parsing the rest of the input.

---

## Phase 0: Architectural Reckoning ✅ COMPLETE (2026-02-01)

Removed all dead cache infrastructure (`TokenCache`, `ParseCache`, `RecoveringParser` — ~581 lines).
Parser now honestly does: damage tracking → whole-tree reuse check → full reparse.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 1: Incremental Lexer ✅ COMPLETE (2026-02-02)

Splice-based `TokenBuffer` re-lexes only the damaged region (typically ~50 bytes for a 1-char edit
in a 10KB file) and splices the result into the existing token array. Implemented in `src/lexer/token_buffer.mbt`.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 2: Green Tree (Immutable CST) ✅ COMPLETE (2026-02-19)

`CstNode` (position-independent, content-addressed, structurally shareable) + `SyntaxNode` (ephemeral
positioned facade) + `EventBuffer` (flat event stream → tree) + `seam/` package. Unchanged subtrees
are the same pointer, not copies.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 3: Integrated Error Recovery ✅ COMPLETE (2026-02-03)

Sync-point recovery (`RightParen`, `Then`, `Else`, `EOF`). Produces partial trees with
`ErrorNode`/`ErrorToken` interspersed among valid nodes. Reports up to 50 errors per parse.
Fuzz-tested for termination on any token sequence.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 4: Checkpoint-Based Subtree Reuse ✅ COMPLETE (2026-02-03)

`ReuseCursor` with 4-condition reuse protocol: kind match + leading token context + trailing
token context + no damage overlap. Trailing context check is essential — a node's parse can
depend on what follows it. O(depth) per lookup via stateful frame stack.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 5: Generic Parser Framework ✅ COMPLETE (2026-02-23)

> **Note:** The originally planned "Phase 5: Grammar Expansion" was superseded by this work.
> The original grammar expansion plan is preserved below as "Phase 5 (original plan)".

**Goal:** Extract a reusable `ParserContext[T, K]` API so any MoonBit project can define a parser against the green tree / error recovery / incremental infrastructure.

**What was built:**
- `src/core/` package: `TokenInfo[T]`, `Diagnostic[T]`, `LanguageSpec[T, K]`, `ParserContext[T, K]`
- `ParserContext::new` (array-based) and `ParserContext::new_indexed` (closure-based, zero-copy)
- Full method surface: `peek`, `at`, `at_eof`, `emit_token`, `start_node`, `finish_node`, `mark`, `start_at`, `error`, `bump_error`, `emit_zero_width`, `emit_error_placeholder`, `flush_trivia`
- `parse_with[T, K]` top-level entry point
- `Diagnostic[T]` with `got_token : T` (captures offending token at parse time)
- Lambda parser migrated to `ParserContext` as reference implementation
- Trivia-inclusive lexer integration: whitespace in token stream, `flush_trivia()` before grammar return
- 367 total tests passing; 56 benchmarks passing

---

## Phase 6: Generic Incremental Reuse ✅ COMPLETE (2026-02-24)

**Goal:** Wire `ReuseCursor[T, K]` from `loom/src/core/` into `ParserContext` via `node()`/`wrap_at()` combinators so incremental subtree reuse fires transparently for any grammar.

**What was built:**
- `ReuseCursor[T, K]` generic struct in `loom/src/core/` with `collect_old_tokens`, `try_reuse`, `seek_node_at`, `advance_past`
- `ParserContext` gains `reuse_cursor`, `reuse_count`, `set_reuse_cursor`, `set_reuse_diagnostics`
- `node(kind, body)` combinator: skips `body` closure on reuse hit (O(edit) skip)
- `wrap_at(mark, kind, body)` combinator: retroactive wrapping; inner `node()` calls still reuse
- Lambda grammar migrated: `parse_atom` uses `ctx.node()`, binary/app rules use `ctx.wrap_at()`
- `run_parse_incremental` helper wires cursor + diagnostics
- Old lambda-specific `ReuseCursor` removed from `src/parser/` (~946 lines deleted)
- `prev_diagnostics?` parameter for diagnostic replay on reused subtrees
- 372 total tests passing; 59 benchmarks passing (Phase 3 cursor benchmarks added)

---

## Phase 7: Reactive Pipeline (ReactiveParser) ✅ COMPLETE (2026-02-25)

**Goal:** Build `ReactiveParser`, a `Signal`/`Memo`-backed Salsa-style incremental pipeline using `CstNode` value equality for automatic stage backdating.

**Architecture (updated per ADR 2026-02-27):** `source_text : Signal[String]` → `cst : Memo[CstStage]` → `ast : Memo[AstNode]`

**What was built:**
- `dowdiness/incr` added as git submodule dependency
- `TokenStage` enum and `CstStage` struct, both `Eq`-derived for backdating
- `ReactiveParser::new()`, `set_source()`, `cst()`, `diagnostics()`, `term()` public API
- Option B error routing: tokenization failure → `AstNode::error(...)` (consistent with `ImperativeParser`)
- `diagnostics()` returns `.copy()` to prevent mutation of memoized backing array
- 343 total tests passing; 59 benchmarks passing

---

## SyntaxNode-First Layer ✅ COMPLETE (2026-02-25)

**Goal:** Make `SyntaxNode` the primary interface for all tree operations; eliminate direct `.cst` field access from callers.

**Phase 1 — Extend `SyntaxNode` API (complete):**
- `SyntaxToken` positioned leaf view; `SyntaxElement` union type
- `all_children()`, `tokens()`, `find_token()`, `tokens_of_kind()`, `tight_span()`, `find_at()`
- `Show` and `Debug` impls for `SyntaxNode` and `SyntaxToken`

**Phase 2 — SyntaxNode-first callers (complete):**
- `cst_convert.mbt` replaced free functions with `SyntaxNode` methods
- `ImperativeParser` stores `SyntaxNode?` instead of `CstNode?`
- `.cst` field made private — abstraction boundary enforced
- `parse_with_error_recovery_tokens` removed (no callers; was broken)

**Phase 3 — Typed views (planned):**
- `LambdaExpr(SyntaxNode)`, `AppExpr(SyntaxNode)` typed wrappers
- `AstNode` becomes JSON-serialization-only

---

## Grammar Expansion (Partial ✅)

> Formerly "Phase 5 original plan" — superseded as Phase 5 by the Generic Parser Framework.

**Completed (2026-02-28):** `let x = e in body` expression form — `LetExpr` CST node, `Let`/`In` tokens and SyntaxKinds, `parse_let_expr` in grammar. [Plan archived →](docs/archive/completed-phases/2026-02-28-grammar-expansion-let.md)

**Remaining:** Type annotations, comments, multi-expression files (top-level sequences of let bindings).
Key outcome of multi-expression files: independent top-level subtrees make incremental reuse genuinely impactful — editing one binding won't re-parse any other.
Exit criteria: type annotations parse correctly; CST round-trips to identical source text; reuse fires across top-level boundaries.

---

## Phase 6: CRDT Exploration (Research)

**Goal:** Integrate the incremental parser with CRDT-based collaborative editing.
**Status: Research phase.** `crdt_integration.mbt` provides AST↔CRDTNode conversion only; no conflict logic.

**Recommended architecture:** text-level CRDT + incremental parser on merge. Each peer maintains source text via a text CRDT (Fugue/RGA); after merging remote operations, the incremental parser re-parses the affected region. Avoids tree CRDTs entirely.

### What to Build

1. **Green tree diff utility:** Changed subtrees with positions, using pointer equality for O(1) unchanged-subtree skips.

2. **Text CRDT adapter:** Translate CRDT operations into `Edit`:
   ```
   TextDelta (Retain | Insert | Delete)   ← Loro/Quill Delta format
     ↓ .to_edits()
   Edit { start, old_len, new_len }       ← lengths, not endpoints
     ↓ implements
   pub trait Editable                     ← ImperativeParser accepts T : Editable
   ```
   `Delete(n)` → `old_len = n`, `Insert(s)` → `new_len = s.length()`, `Retain(n)` → advance cursor.

3. **Integration test harness:** Two simulated peers; verify identical text and parse trees after sync.

**Exit criteria:** Green tree diff tested; `TextDelta.to_edits()` values implement `Editable` ✅; two-peer convergence test; recommendation on tree-level vs text-level CRDT.

---

## Phase Summary and Dependencies

```
Phase 0: Reckoning                  ✅ COMPLETE (2026-02-01)
    |
    +------ Phase 1: Incremental Lexer      ✅ COMPLETE (2026-02-02)
    |
    +------ Phase 2: Green Tree / seam/     ✅ COMPLETE (2026-02-19)
                |
                +------ Phase 3: Error Recovery         ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 4: Subtree Reuse          ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 5: Generic Parser Ctx     ✅ COMPLETE (2026-02-23)
                |           |
                |           +-- Phase 6: Generic Reuse  ✅ COMPLETE (2026-02-24)
                |
                +------ SyntaxNode-First Layer          ✅ COMPLETE (2026-02-25)
                |           Phase 1: SyntaxNode API
                |           Phase 2: .cst private
                |           Phase 3: Typed views        ← PLANNED
                |
                +------ Phase 7: ReactiveParser (reactive)    ✅ COMPLETE (2026-02-25)
                |
                +------ NodeInterner                    ✅ COMPLETE (2026-02-28)
                |
                +------ Grammar Abstraction             ✅ COMPLETE (2026-03-01)
                |           (Grammar[T,K,Ast], bridge factories, ~240 lines deleted)
                |
                +------ Loom Extraction                 ✅ COMPLETE (2026-03-01)
                |           (core/bridge/pipeline/incremental/viz → dowdiness/loom)
                |
                +------ Rabbita Monorepo Migration      ✅ COMPLETE (2026-03-02)
                |           (submodules absorbed, lambda → examples/lambda/, no root moon.mod.json)
                |
                +------ Grammar Expansion               ⬤ PARTIAL (let bindings ✅; type annotations, multi-expr ← PLANNED)
                |
                +------ CRDT Exploration               ← PLANNED (original Phase 6)
```

Phases 0-7, SyntaxNode-First Layer (Phase 1+2), NodeInterner, let bindings, Grammar abstraction (bridge factories), loom extraction, and rabbita monorepo migration are complete.
Next candidates: Typed SyntaxNode views, Grammar Expansion (type annotations, multi-expression files).

---

## Cross-Cutting Concern: Incremental Correctness Testing

**Invariant:** For any edit, incremental parse must produce a tree structurally identical to full reparse.

Verified via differential oracle (random source + random edits → compare incremental vs full reparse result).
Property-based fuzzing with sequences of 10-100 random edits catches state accumulation bugs. Status: ✅ verified through Phase 4. Grammar Expansion will require extending the oracle when new constructs are added.

---

## Milestones

| Milestone | Phase | Status |
|-----------|-------|--------|
| Honest Foundation | Phase 0 | ✅ Complete (2026-02-01) |
| Incremental Lexer | Phase 1 | ✅ Complete (2026-02-02) |
| Green Tree / CST | Phase 2 | ✅ Complete (2026-02-19) |
| Error Recovery | Phase 3 | ✅ Complete (2026-02-03) |
| Subtree Reuse | Phase 4 | ✅ Complete (2026-02-03) |
| Generic Parser Framework | Phase 5 | ✅ Complete (2026-02-23) |
| Generic Incremental Reuse | Phase 6 | ✅ Complete (2026-02-24) |
| Reactive Pipeline (ReactiveParser) | Phase 7 | ✅ Complete (2026-02-25) |
| Grammar Expansion: let bindings | 2026-02-28 | ✅ Complete |
| Grammar abstraction (bridge factories) | 2026-03-01 | ✅ Complete |
| Infrastructure extraction (dowdiness/loom) | 2026-03-01 | ✅ Complete |
| Rabbita monorepo migration | 2026-03-02 | ✅ Complete |
| Grammar Expansion: type annotations, multi-expr | Future | Confidence: High |
| CRDT Exploration | Future | Confidence: Low-Medium (research) |

---

## What This Roadmap Does NOT Include

1. **Parser generation.** We are staying with hand-written recursive descent. This means we accept that we cannot match Lezer/tree-sitter's reuse granularity. We compensate with the green tree architecture and checkpoint-based reuse, which provide sufficient incrementality for our use case.

2. **GLR or Earley parsing.** The grammar is unambiguous. We don't need generalized parsing.

3. **Language server protocol.** This roadmap covers the parser, not IDE integration. An LSP layer would sit on top of Phase 5's CST.

4. **Evaluation / type checking.** This is a parser roadmap, not a language implementation roadmap.

---

## Success Criteria for "Stabilized"

The parser is stabilized when:

1. **Correctness:** Incremental parse produces identical trees to full reparse for any edit, verified by property-based testing over millions of random edits.

2. **Performance:** Single-character edits in a 1000-token file complete in under 100 microseconds (not counting initial parse).

3. **Error resilience:** Any input (including random bytes) produces a tree without panicking. Valid portions of malformed input are correctly parsed.

4. **Architecture:** Every component is connected and contributes to the pipeline. No dead infrastructure. New grammar rules can be added by modifying only the parser and syntax kind enum.

5. **Test coverage:** >95% line coverage on parser, lexer, tree builder, and incremental engine. Property-based tests for all invariants.

6. **Documentation:** Every public API has doc comments. Architecture decisions are documented with rationale. No misleading claims about capabilities.

---

## References

### Architecture Inspiration
- [Roslyn's Red-Green Trees](https://ericlippert.com/2012/06/08/red-green-trees/) - Original red-green tree design
- [rust-analyzer Architecture](https://github.com/rust-lang/rust-analyzer/blob/master/docs/dev/syntax.md) - Practical adaptation for Rust
- [swift-syntax](https://github.com/apple/swift-syntax) - Swift's green tree implementation

### Incremental Parsing
- Wagner & Graham (1998) - [Efficient and Flexible Incremental Parsing](https://harmonia.cs.berkeley.edu/papers/twagner-parsing.pdf)
- [Lezer](https://lezer.codemirror.net/) - LR-based incremental parsing (inspiration, not template)
- [Tree-sitter](https://tree-sitter.github.io/) - Generated recursive descent with incrementality

### Error Recovery
- [Error Recovery in Recursive Descent Parsers](https://www.cs.tufts.edu/~nr/cs257/archive/donn-seeley/repair.pdf)
- [Panic Mode Recovery](https://en.wikipedia.org/wiki/Panic_mode) - Classical approach we adapt

### CRDT and Collaborative Editing
- Gentle et al. (2024) - [eg-walker: Mergeable Tree Structures](https://arxiv.org/abs/2409.14252) - The algorithm this project implements; uses length-based edit representation throughout
- [diamond-types](https://github.com/josephg/diamond-types) - Rust reference implementation of eg-walker; `PositionalComponent { Ins { len }, Del(len) }` stores lengths not endpoints
- [Loro](https://loro.dev) - Production CRDT library; `TextDelta (Retain | Insert | Delete)` follows Quill Delta format with lengths as primitives; directly motivates the `Edit { start, old_len, new_len }` design
- [Quill Delta format](https://quilljs.com/docs/delta/) - Retain/Insert/Delete with lengths; the industry-standard representation for collaborative text operations

### MoonBit
- [MoonBit Language Reference](https://www.moonbitlang.com/docs/syntax)
- [MoonBit Core Libraries](https://mooncakes.io/docs/#/moonbitlang/core/)
