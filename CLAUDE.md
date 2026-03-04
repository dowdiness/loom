# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Commands

Each module is self-contained. Run `moon` from the module's directory:

```bash
cd loom && moon check && moon test    # 88 tests (framework only)
cd seam && moon check && moon test    # 99 tests
cd incr && moon check && moon test    # 194 tests
cd examples/lambda && moon check && moon test   # 311 tests
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
| `loom/src/` (root) | Public API facade; `Grammar[T,K,Ast]`, `new_imperative_parser`, `new_reactive_parser` |
| `loom/src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable`, `ParserContext[T,K]` — shared primitives |
| `loom/src/pipeline/` | `ReactiveParser` — reactive incremental pipeline |
| `loom/src/incremental/` | `ImperativeParser`, damage tracking |
| `loom/src/viz/` | DOT graph renderer (`DotNode` trait) |

**`dowdiness/seam`** (`seam/`) — language-agnostic CST (`CstNode`, `SyntaxNode`)

**`dowdiness/incr`** (`incr/`) — reactive signals (`Signal`, `Memo`)

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

**Reactive pipeline:** `Signal[String]` → `Memo[CstStage]` → `Memo[AstNode]`
(TokenStage was removed — see ADR `docs/decisions/2026-02-27-remove-tokenStage-memo.md`)

**Two-tree model:** `CstNode` (immutable, position-independent, structurally shareable) +
`SyntaxNode` (ephemeral positioned facade). All callers use `SyntaxNode`; `.cst` is private.

**Edit protocol:** `Edit { start, old_len, new_len }` — lengths not endpoints.
`pub trait Editable { start/old_len/new_len }` implemented by `Edit`.
`TextDelta (Retain|Insert|Delete)` → `.to_edits()` → `[Edit]` (planned).

**Subtree reuse:** `ReuseCursor` 4-condition protocol (kind + leading token context +
trailing token context + no damage overlap). O(depth) per lookup via stateful frame stack.

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
   - `git mv docs/plans/<plan>.md docs/archive/completed-phases/<plan>.md`
   - Update `docs/README.md` (move entry from Active Plans → Archive)
   - `bash check-docs.sh` should show no warnings before committing
   Do this in the same commit that marks the plan complete, not later.

3. **Top-level docs stay slim.** `README.md` and `ROADMAP.md` are summaries with links,
   not detail documents. Extract any section >20 lines into a sub-doc and link to it.

## MoonBit Conventions

- Tests: `///|` doc-comment prefix + `test "name" { ... }` blocks
- Assertions: `inspect(expr, content="expected")`
- Panic tests: name starts with `"panic "` — test runner expects `abort()`
- Whitebox tests (`*_wbtest.mbt`): same package, access private fields
- Anonymous callbacks: `() => expr`, `() => { stmts }`, `x => expr`. Empty body: `() => ()` not `() => {}`
- Trait impl: one `pub impl Trait for Type with method(self) { ... }` per method
- Orphan rule (error 4061): can't impl foreign trait for foreign type — use a private newtype wrapper

## Key Design Decisions

- `Edit` stores lengths (`old_len`, `new_len`), not endpoints — matches Loro/Quill/diamond-types
- `TokenStage` memo removed — vacuous for whitespace-inclusive lexers (ADR 2026-02-27)
- `ReuseCursor` uses trailing-context check (Option B) to prevent false reuse
- `ParserContext` is generic `[T, K]` — any grammar can plug in via `LanguageSpec`
