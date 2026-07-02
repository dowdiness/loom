# Handoff: loomgen Phase 2 — Term Enum Parsing

## Status: Complete

All Phase 2 deliverables are working:

### Phase 1 (complete)
- [x] Token enum code generation (PR #492)
- [x] `--seed` / `--skip-syntax` flags
- [x] Split output dirs
- [x] Tombstone persistence
- [x] Annotation validation
- [x] **437/437 tests pass**

### Phase 2 (done)

- [x] **`SyntaxRole` enum** — renamed `TokenRole` → `SyntaxRole`, added `Leaf`, `Node`, `ErrorNode`, `Root` term variants
- [x] **Term annotation parsing** — `#loom.leaf`, `#loom.node`, `#loom.errornode`, `#loom.root` classify variants in `#loom.term` enums
- [x] **Term completeness check** — `#loom.term` enums also require per-variant `#loom.*` annotations
- [x] **`derive_kind_name` for term roles** — term roles use variant name as-is (no suffix), producing `LambdaExpr`, `IntLiteral`, `ErrorNode`, `SourceFile`, etc.
- [x] **`term_enum` wiring** — `main.mbt` calls `build_kind_entries` on `annotated.term_enum` when present, tracks `error_node_name` for `from_raw` fallback
- [x] **`from_raw` fallback** — prefers `error_node_name` (e.g., `ErrorNode`) when a term `#loom.errornode` is present; falls back to `ErrorToken`, then `abort`
- [x] **`emit_syntax_kind` signature** — takes `error_node_name: String?` for fallback control
- [x] **Fixture** — `loomgen/fixtures/term_kind.mbt` contained combined `#loom.token` + `#loom.term` enums for regeneration; since 2026-07-02 (#563) the lambda metadata is split into `examples/lambda/token/token.mbt` + `--term examples/lambda/term_kind.mbt`
- [x] **Lambda example swapped** — `examples/lambda/syntax/syntax_kind.mbt` is now generated output (not hand-written). Generated includes both token kinds (26) and term kinds (17). **437/437 tests pass**

### Raw Kind Verification

Seeded from the old hand-written `syntax_kind.mbt`, all 43 raw numbers match exactly:

| Kind | Raw | Kind | Raw | Kind | Raw |
|------|-----|------|-----|------|-----|
| LambdaToken | 0 | IfKeyword | 6 | IdentToken | 9 |
| DotToken | 1 | ThenKeyword | 7 | IntToken | 10 |
| LeftParenToken | 2 | ElseKeyword | 8 | WhitespaceToken | 11 |
| RightParenToken | 3 | FnKeyword | 43 | ErrorToken | 12 |
| PlusToken | 4 | LetKeyword | 23 | EofToken | 13 |
| MinusToken | 5 | EqToken | 25 | LambdaExpr | 14 |

Full table in `examples/lambda/syntax/syntax_kind.mbt`.

## Build & Run

```bash
cd <repo-root>/loom
# Split-input generation (token source + --term):
moon run loomgen --target native -- --seed <existing_syntax_kind.mbt> --term <term_kind.mbt> <token.mbt> <token_out> <syntax_out>

# Example with lambda sources:
moon run loomgen --target native -- \
  --seed examples/lambda/syntax/syntax_kind.mbt \
  examples/lambda/token/token.mbt \
  --term examples/lambda/term_kind.mbt \
  examples/lambda/token examples/lambda/syntax

# Token-only (backward compatible):
moon run loomgen --target native -- --seed examples/lambda/syntax/syntax_kind.mbt --skip-syntax \
  examples/lambda/token/token.mbt examples/lambda/token
```

## Annotation Reference
| Annotation | Syntax | Role |
|---|---|---|
| `#loom.token` | on enum | Marks token enum |
| `#loom.term` | on enum | Marks term (CST node) enum |
| `#loom.punct(".")` | on variant | Punctuation token, args=display string |
| `#loom.keyword("fn")` | on variant | Keyword token, args=keyword text |
| `#loom.ident` | on variant | Identifier token |
| `#loom.literal` | on variant | Literal token (generic name) |
| `#loom.literal("IntToken")` | on variant | Literal with explicit SyntaxKind name override |
| `#loom.trivia` | on variant | Trivia token |
| `#loom.delimiter` | on variant | Delimiter token |
| `#loom.error` | on variant | Error token |
| `#loom.eof` | on variant | EOF token |
| `#loom.leaf` | on variant | CST leaf node (wraps a token) |
| `#loom.node` | on variant | CST interior node |
| `#loom.errornode` | on variant | CST error node |
| `#loom.root` | on variant | CST root node |

## File Listing (`loomgen/`)

```text
emit_syntax_kind.mbt   5616 bytes  — WORKING (error_node_name fallback, term kinds)
emit_token_impls.mbt   5711 bytes  — WORKING (term arms added)
emit_spec.mbt           232 bytes  — STUB (see Design Decisions)
main.mbt               8418 bytes  — WORKING (term_enum wiring)
parse_annotations.mbt  6782 bytes  — WORKING (SyntaxRole, term annotations)
rawkind_registry.mbt   2965 bytes  — WORKING (clean)
moon.mod                380 bytes  — parser@0.3.3, x@0.4.38
moon.pkg                294 bytes  — x/fs, x/sys, hashset, parser
```

## Design Decisions

- **`SyntaxRole` over separate `TokenRole`/`TermRole`**: A single enum handles both, since `derive_kind_name` and `build_kind_entries` operate uniformly on both. Term roles use variant name as-is (no suffix suffix like `Token`).

- **Separate token and term metadata sources** (since #563, 2026-07-02): `parse_annotations`
  reads from the positional source (token enum, `examples/lambda/token/token.mbt`) and the
  `--term` file (term enum, `examples/lambda/term_kind.mbt`). loomgen validates that the
  term file does NOT contain a `#loom.token` enum, enforcing clean separation.

- **Lambda example uses generated `syntax_kind.mbt`**: The hand-written file is replaced by generated output. Tests pass at 437/437 with identical raw numbering.

## Remaining Work

1. **`LanguageSpec` constants** — Wire `whitespace_kind`, `error_kind`, `root_kind`, `eof_token` as generated constants from annotation metadata.
2. **`#loom.view`** — View role for projection identity (more complex, deferred from Phase 2).
3. **`emit_spec.mbt`** — Still a stub. The originally-planned `syntax_kind_to_token_kind` and `cst_token_matches` functions were removed from the framework. Generate only when a consumer appears.

## Post-Phase-2 Changes (issue #563)

- **Lambda metadata split**: the combined `loomgen/fixtures/term_kind.mbt` fixture has
  been replaced with split inputs: `examples/lambda/token/token.mbt` (token source, positional)
  and `examples/lambda/term_kind.mbt` (term kind metadata, loaded via `--term`).
  The regression test (`regression_wbtest.mbt`) now reads both files separately.
  CI steps use the split form: `--seed <syntax> --term <term_kind> <token.mbt> <out>`.
