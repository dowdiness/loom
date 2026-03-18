# Flat Grammar Unification

**Date:** 2026-03-15
**Status:** Complete

## Problem

The lambda parser has two grammars:
- `lambda_grammar` — right-recursive `LetExpr` nesting, `in`-delimited
- `source_file_grammar` — flat `LetDef*` siblings, newline-delimited

Right-recursive `LetExpr` is worst-case for incremental parsing: every spine node spans to the end of input, so a tail edit damages all nodes. Maintaining two grammars doubles the surface area (two specs, two tokenizers, two parse entry points) for the same language.

## Solution

Remove `lambda_grammar`. Unify on `source_file_grammar` with flat `LetDef*` structure and layout-aware lexing. Remove `let...in` expression support entirely — the `in` keyword is no longer part of the grammar.

## Design decisions

### `let...in` expressions: removed

The source-file grammar's `parse_source_file_let_item` currently detects `in` and upgrades `LetDef` to `LetExpr`. Remove this branch — `let` definitions are always flat `LetDef` siblings. `let...in` as an inline expression is dropped.

### `@token.In`: kept in lexer, removed from grammar

The lexer continues to recognize `in` as a keyword token for better error messages (e.g., "unexpected 'in'"). But `In` is removed from `is_sync_point()` since it no longer serves as a recovery boundary.

## What changes

### Public API (`lambda.mbt`)

`new_imperative_parser(source)` switches from `lambda_grammar` to `source_file_grammar`.

### Parser functions (`parser.mbt`, `cst_parser.mbt`)

All parser entry points switch from `lambda_spec` + `tokenize` to `source_file_spec` + `tokenize_layout`:
- `parse()`, `parse_cst()` in `parser.mbt`
- `parse_cst_recover()`, `parse_cst_with_cursor()`, `parse_cst_recover_with_tokens()` in `cst_parser.mbt`
- `make_reuse_cursor()` in `cst_parser.mbt`

### AST conversion (`parser.mbt`)

`parse()` currently routes through `syntax_node_to_term` which rejects `LetDef` trees. Switch to `syntax_node_to_source_file_term` (or equivalent right-fold) so that flat `LetDef*` trees produce the correct `Term::Let` chain.

### `parse_source_file_let_item` (`cst_parser.mbt`)

Remove the `@token.In` detection branch that creates `LetExpr` nodes. All `let` items produce `LetDef`.

### `is_sync_point` (`cst_parser.mbt`)

Remove `@token.In` from sync points.

### `tokenize_range` (`lexer.mbt`)

Currently calls non-layout `tokenize`. Switch to `tokenize_layout`.

### External consumers (parent monorepo)

- `projection/proj_node.mbt` — uses `lambda_grammar` explicitly. Switch to unified grammar.
- `editor/sync_editor.mbt` — already uses `source_file_grammar`. No change needed.
- `editor/performance_benchmark.mbt` — already uses `source_file_grammar`. No change needed.
- `examples/lambda/README.md` — update API documentation.

### Test input strings

All tests using `let x = 1 in expr` syntax update to `let x = 1\nexpr`.

Example:
```
// Before
"let x = 1 in let y = 2 in x + y"

// After
"let x = 1\nlet y = 2\nx + y"
```

### Whitebox tests (`cst_parser_wbtest.mbt`)

8 tests reference `lambda_spec` and `@lexer.tokenize` directly. Migrate to `source_file_spec` and `tokenize_layout`.

### Benchmark helpers (`let_chain_benchmark.mbt`)

`make_let_chain(n, tail)` generates newline-delimited chains:
```
// Before: "let x0 = 0 in let x1 = 0 in x1"
// After:  "let x0 = 0\nlet x1 = 0\nx1"
```

### Error recovery tests

- Tests for `missing 'in'` no longer apply. Remove or replace with flat-grammar error cases.
- `cst_tree_test.mbt` test "source file: final let-expression is parsed as LetExpr" — remove (no more `LetExpr`).
- `cst_parser_wbtest.mbt` test for `InKeyword` trailing-context reuse — replace with equivalent flat-grammar reuse test.

### Snapshot updates

Run `moon test --update` after all code changes.

## What gets removed

| Item | Location |
|------|----------|
| `lambda_grammar` | `grammar.mbt` |
| `lambda_spec` | `lambda_spec.mbt` |
| `parse_lambda_root` | `cst_parser.mbt` |
| `parse_let_expr` (recursive) | `cst_parser.mbt` |
| `in`-detection branch in `parse_source_file_let_item` | `cst_parser.mbt` |
| `@token.In` in `is_sync_point` | `cst_parser.mbt` |
| `tokenize` (non-layout) | `lexer.mbt` |
| `lambda_step_lexer` (non-layout) | `lexer.mbt` |
| `LetExpr` syntax kind | `syntax_kind.mbt` |
| `InKeyword` syntax kind | `syntax_kind.mbt` |
| `LetExpr` CST→AST handling | `term_convert.mbt` |
| `LetExprView` | `views.mbt` |

## What stays

| Item | Location |
|------|----------|
| `source_file_grammar` | `grammar.mbt` |
| `source_file_spec` | `lambda_spec.mbt` |
| `parse_source_file_root` | `cst_parser.mbt` |
| `tokenize_layout` | `lexer.mbt` |
| `lambda_step_lexer_layout` | `lexer.mbt` |
| `@token.In` (lexer keyword) | `lexer.mbt` |
| `LetDef`, `SourceFile` syntax kinds | `syntax_kind.mbt` |
| `NewlineToken` syntax kind | `syntax_kind.mbt` |
| CST→AST right-fold for `LetDef*` | `term_convert.mbt` |
| All expression/binary/application parsers | `cst_parser.mbt` |

## Renaming

After removal, rename for clarity. Sequencing: remove old functions first, then rename to avoid naming conflicts.

- `source_file_grammar` → `lambda_grammar`
- `source_file_spec` → `lambda_spec`
- `tokenize_layout` → `tokenize`
- `lambda_step_lexer_layout` → `lambda_step_lexer`
- `parse_source_file_root` → `parse_root` or keep as-is
- `parse_source_file_term` → `parse_term` or keep as-is

## Expected outcome

- Let-chain benchmarks: incremental parsing faster than full reparse (each `LetDef` is an independent sibling, O(1) damage per edit)
- Single codebase path: one grammar, one tokenizer, one spec
- Simpler maintenance: ~170 lines of production code removed

## Projection layer fix (bundled, not deferred)

The projection layer must compile after this change. These fixes are part of the implementation, not a follow-up.

### What breaks and how to fix

**`proj_node.mbt` reparsing:** Uses `lambda_grammar` to reparse single expressions. Switch to unified grammar. For editing a LetDef's init value, reparse just the init expression — no `let...in` needed. For a single expression like `λx.x`, the unified grammar handles it unchanged (zero LetDefs, one Expr).

**`tree_lens.mbt` Let placeholders:** Generates `let x = 0 in x` as placeholder text. Instead, construct a `LetDef` CST node directly via `CstNode::new` with a default init value, inserted as a sibling in the flat list. This skips the reparse step entirely.

**LetDef editing model:** The projection layer stops treating Let as a single editable expression and treats LetDef as a structural sibling — inserted, deleted, or init-edited independently. Each operation damages only one sibling node.

## API surface

### Removed
- `lambda_grammar` (public in `grammar.mbt`)
- `lambda_spec`, `parse_lambda_root`
- `tokenize` (non-layout), `lambda_step_lexer` (non-layout)

### Renamed (after removal)
- `source_file_grammar` → `lambda_grammar`
- `source_file_spec` → `lambda_spec`
- `tokenize_layout` → `tokenize`
- `lambda_step_lexer_layout` → `lambda_step_lexer`

### Kept unchanged
- `parse_source_file_root` (becomes the only parse root)
- Source-file wrappers: `parse_source_file()`, `parse_source_file_recover_with_tokens()`, `make_source_file_reuse_cursor()` in `cst_parser.mbt`
- `parse_source_file_term()` in `parser.mbt`
- `new_imperative_parser(source)` in `lambda.mbt` — switches to unified grammar internally

### Callers using `lambda_grammar` directly
- `reactive_parser_test.mbt` — switch to unified grammar
- `imperative_parser_test.mbt` — switch to unified grammar
- `let_chain_benchmark.mbt` — switch to unified grammar + newline-delimited input
- `projection/proj_node.mbt` — switch to unified grammar (bundled fix)

## Risks

- **Test migration volume:** ~94 direct `lambda_grammar` uses + ~90 indirect `parse()` calls + 8 whitebox tests. Mechanical but tedious.
- **Error recovery regression:** `in` currently serves as a sync point. Removing it changes recovery behavior for malformed input like `let x = (1 in x`. New recovery patterns need coverage.
- **Snapshot churn:** All CST snapshots change from `LetExpr` to `LetDef`/`SourceFile` structure.
- **Projection/tree lens migration:** Must be fixed in the same change to keep the repo compiling.

## Performance caveat

CST damage model improves from O(n) to O(1) per edit. However, the editor still rebuilds whole-file semantic structures by right-folding every LetDef on each update (`term_convert.mbt`, `projection_memo.mbt`, `sync_editor_parser.mbt`). That remaining O(n) fold is a separate optimization target, not addressed by this change.

## Non-goals

- Changing the AST (`Term::Let` stays the same)
- Changing the loom framework
- Adding new language features
- Incremental projection updates (projection fix is compile-fix only, not incremental)
- Optimizing the O(n) right-fold in term_convert
