# CLAUDE.md

Guidance for Claude Code when working in this repository.

@~/.claude/moonbit-base.md

## Commands

Each module is self-contained. Run `moon` from the module's directory:

```bash
cd loom && moon check && moon test    # 126 tests (framework only)
cd seam && moon check && moon test    # 351 tests
cd incr && moon check && moon test    # 508 tests
cd text-change && moon check && moon test    # text utility tests
cd moji && moon check && moon test           # UAX #29 conformance
cd examples/lambda && moon check && moon test   # 405 tests
cd examples/json && moon check && moon test     # JSON parser
```

Before every commit (in the module you edited):
```bash
moon info && moon fmt   # regenerate .mbti interfaces + format
```

Validate docs hierarchy from repo root:
```bash
bash check-docs.sh
```

Benchmarks (always `--release`):
```bash
cd examples/lambda && moon bench --release
```

Run a single package or file:
```bash
# From loom/
moon test -p dowdiness/loom/core
moon test -p dowdiness/loom/core -f edit_test.mbt

# From examples/lambda/
moon test -p dowdiness/lambda/lexer
moon test -p dowdiness/lambda/lexer -f lexer_test.mbt
```

## Package Map

**Monorepo** — no root `moon.mod.json`. Each directory is an independent module:

**`dowdiness/loom`** (`loom/`) — parser framework:

| Package | Purpose |
|---------|---------|
| `loom/src/` (root) | Public API facade (`loom.mbt`, pure `pub using` re-export); `Grammar[T,K,Ast]`, `new_imperative_parser`, `new_parser` |
| `loom/src/core/` | `Edit`, `Range`, `TextDelta`, `ReuseSlot`, `Editable`, `TokenBuffer`, `ReuseCursor`, `ParserContext[T,K]`, `LanguageSpec` — shared primitives |
| `loom/src/pipeline/` | `Parser[Ast]` — unified wrapper: owns `ImperativeParser` engine + publishes source/syntax/ast/diagnostics as `@incr.Signal`/`@incr.Memo` cells (post Stage 6, 2026-04-17) |
| `loom/src/incremental/` | `ImperativeParser`, damage tracking |
| `loom/src/viz/` | DOT graph renderer (`DotNode` trait) |

**`dowdiness/seam`** (`seam/`) — language-agnostic CST (`CstNode`, `SyntaxNode`)

**`dowdiness/incr`** (`incr/`) — reactive signals (`Signal`, `Memo`) [submodule]

**`dowdiness/text_change`** (`text-change/`) — pure contiguous text-change utilities; depends on `dowdiness/moji`. Migrated into loom from canopy/lib/ in 2026-05 (#147).

**`dowdiness/moji`** (`moji/`) — UAX #29 grapheme cluster + word boundary segmentation, UTF-16 indexed. Carries upstream conformance fixtures (`testdata/`) and Python generators (`scripts/`). Migrated into loom from canopy/lib/ in 2026-05 (#147).

**`dowdiness/json`** (`examples/json/`) — JSON parser example (deps: loom, seam)

**`dowdiness/lambda`** (`examples/lambda/`) — lambda calculus parser example:

| Package | Purpose |
|---------|---------|
| `src/token/` | Token kinds |
| `src/syntax/` | Syntax node kinds |
| `src/lexer/` | Tokenizer |
| `src/ast/` | Abstract syntax tree |
| `src/` (root) | Parser, grammar, CST→AST, tests |
| `src/benchmarks/` | Performance benchmarks |

## Architecture

**Unified pipeline (post Stage 6, 2026-04-17):** `Parser[Ast]` wraps `ImperativeParser` and publishes source + syntax + AST + diagnostics as `@incr.Signal` / `@incr.Memo` cells. `ReactiveParser` was removed in commit d85d5ff; prior ADRs about `TokenStage` (2026-02-27, 2026-03-15) and the two-parser design (2026-03-02) are superseded by `docs/decisions/2026-04-17-unified-parser-proposal.md`.

**CST traversal primitives (seam/cst_traverse.mbt + seam/cst_traits.mbt, ported 2026-03-30 from a feasibility sandbox now removed; see `docs/performance/2026-03-30-cst-traversal-tiers.md`):** closure methods `transform`, `fold`, `transform_fold`, `each`, `iter`, `map` + `Finder`/`Folder`/`TransformFolder` traits (statically dispatched). ROADMAP #59/#60 cover remaining extensions. **Do not claim "no CST traversal abstraction exists" — it does.**

**Two-tree model:** `CstNode` (immutable, position-independent, structurally shareable) +
`SyntaxNode` (ephemeral positioned facade). All callers use `SyntaxNode`; `.cst` is private.

**Edit protocol:** `Edit { start, old_len, new_len }` — lengths not endpoints.
`pub trait Editable { start/old_len/new_len }` implemented by `Edit`.
`TextDelta (Retain|Insert|Delete)` → `.to_edits()` → `[Edit]` (planned).

**Validated CST subtree reuse:** `ReuseCursor` protocol (kind + leading token
context + trailing token context + no damage overlap). Parser-owned edit paths
construct it with `ReuseCursor::new_with_edit`; raw-coordinate
`ReuseCursor::new` is a low-level escape hatch for tests/infrastructure. This is
structural reuse, not stable parser-owned token/subtree identity. O(depth) per
lookup via stateful frame stack.

Full architecture: `docs/architecture/` | Design decisions: `docs/decisions/`

## Docs Rules

**Where files belong:**

| Type | Location |
|------|----------|
| Active / future plan | `docs/plans/` |
| Completed plan | `docs/archive/completed-phases/` |
| Architecture explanation | `docs/architecture/` |
| API reference | `docs/api/` |
| Correctness / testing | `docs/correctness/` |
| Benchmarks / performance | `docs/performance/` |
| Stale status docs, research notes | `docs/archive/` |
| Top-level navigation | `README.md` (≤60 lines) · `ROADMAP.md` (≤450 lines) |

**Three rules:**

1. **Navigation stays current.** Any commit that adds, moves, or removes a `.md` file
   must update `docs/README.md` in the same commit. The index is the entry point for
   AI agents — an unlisted file is effectively invisible.

2. **Archive on completion.** When a plan's last task is done:
   - Add `**Status:** Complete` near the top of the plan file
   - Add a `Decision record:` note:
     - link a new/updated ADR for major plan closures
     - or write `No ADR needed:` with a short reason for mechanical archival
   - `git mv docs/plans/<plan>.md docs/archive/completed-phases/<plan>.md`
   - Update `docs/README.md` (move entry from Active Plans → Archive)
   - `bash check-docs.sh` should show no warnings before committing
   Do this in the same commit that marks the plan complete, not later.

3. **Follow the agent docs protocol.** For ADR thresholds and closure workflow,
   read `docs/development/agent-docs-protocol.md`.

4. **Top-level docs stay slim.** `README.md` and `ROADMAP.md` are summaries with links,
   not detail documents. Extract any section >20 lines into a sub-doc and link to it.

## Key Design Decisions

- `Edit` stores lengths (`old_len`, `new_len`), not endpoints — matches Loro/Quill/diamond-types
- `TokenStage` memo: removed 2026-02-27, reintroduced 2026-03-15, removed again as part of Stage 6 ReactiveParser deletion 2026-04-17 — the unified `Parser[Ast]` does not use it
- `ReuseCursor` uses trailing-context check (Option B) to prevent false reuse
- `ParserContext` is generic `[T, K]` — any grammar can plug in via `LanguageSpec`
- CST traversal lives in `seam/cst_traverse.mbt` — check there before proposing new traversal work
