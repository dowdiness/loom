# Design: Remove AstNode from examples/lambda

**Date:** 2026-03-05
**Status:** Complete

---

## Goal

Collapse the three-tier pipeline `CST → AstNode → Term` into two tiers: `CST → Term`.
`AstNode` was an intermediate positioned tree allocated to carry `AstKind` + span + id.
`SyntaxNode` already carries all of that via the typed view API — `AstNode` is redundant.

---

## Architecture

After the refactor:

- `Term` / `Bop` / `VarName` stay — evaluation representation
- `SyntaxNode` + typed views (`LambdaExprView`, `AppExprView`, etc.) are the only tree type
- `syntax_node_to_term` is the single CST → Term conversion point (already exists)

---

## What Gets Deleted vs. Kept

### `ast/ast.mbt`

| Symbol | Action |
|--------|--------|
| `AstKind` enum | **Delete** |
| `AstNode` struct, `::new`, `::error` | **Delete** |
| `print_ast_node` | **Delete** |
| `node_to_term` | **Delete** (replaced by `syntax_node_to_term`) |
| `Term`, `Bop`, `VarName` | **Keep** |
| `print_term` | **Keep** |

### `term_convert.mbt`

| Symbol | Action |
|--------|--------|
| `convert_source_file_children` | **Delete** |
| `convert_syntax_node` | **Delete** |
| `syntax_node_to_ast_node` | **Delete** |
| `cst_to_ast_node` | **Delete** |
| `cst_to_term` | **Delete** |
| `parse_cst_to_ast_node` | **Delete** |
| `syntax_node_to_term` | **Keep** |
| `view_to_term` | **Keep** |

### `parser.mbt`

| Symbol | Action |
|--------|--------|
| `parse_tree` (returns `AstNode`) | **Delete** |
| `parse` (returns `Term` via `AstNode`) | **Rewrite** — keep signature, use `syntax_node_to_term(parse_cst(s))` internally |

### `error_recovery.mbt`

| Symbol | Action |
|--------|--------|
| `parse_with_error_recovery` | **Delete** |
| `has_errors` | **Delete** |
| `collect_errors` | **Delete** |

---

## Test Migration

### Migration order (top-down — stay green throughout)

1. Rewrite `parse` in `parser.mbt` to use `syntax_node_to_term`
2. Migrate `parse_tree_test.mbt` to use `parse_cst` + `syntax_node_to_term` + `inspect(term)`
3. Migrate `error_recovery_phase3_test.mbt` to use `new_imperative_parser` + `.diagnostics()`
4. Migrate `phase4_correctness_test.mbt` to use `parse_cst` + `SyntaxNode::Eq`
5. Delete `parse_tree`, `parse_with_error_recovery`, `has_errors`, `collect_errors`
6. Delete legacy functions from `term_convert.mbt`
7. Delete `AstKind`, `AstNode`, `print_ast_node`, `node_to_term` from `ast/ast.mbt`
8. Run `moon check && moon test` — verify green

### Per-file details

**`parse_tree_test.mbt`**
- Replace `parse_tree(s)` with `parse_cst(s)` + `syntax_node_to_term`
- Assert via `inspect(term, content="...")`
- Position-sensitive tests (span assertions) move to `views_test.mbt`

**`error_recovery_phase3_test.mbt`**
- Replace `parse_with_error_recovery(s)` with `new_imperative_parser(s)` + `.diagnostics()`
- Error string format changes from `"Parse error: ..."` to diagnostic message format

**`phase4_correctness_test.mbt`**
- Replace `parse_tree(s)` with `parse_cst(s)`
- Use `SyntaxNode::Eq` for structural comparisons

**`parser_test.mbt`**
- No changes needed — `parse(s) -> Term raise ParseError` signature is preserved

---

## Error Handling

`parse(s)` keeps the `ParseError` type. `parse_cst` raises `LexError`; we wrap it:

```
parse(s) -> Term raise ParseError
  = syntax_node_to_term(parse_cst(s))
    // catch LexError(msg) => raise ParseError(msg, EOF)
```

Error recovery callers use `ImperativeParser::diagnostics()` — richer than the old string array.

---

## Success Criteria

- `moon check && moon test` passes with 311 tests (or more, if tests are added)
- `AstNode`, `AstKind`, `node_to_term`, `print_ast_node` do not exist in the codebase
- `parse_tree`, `parse_with_error_recovery`, `has_errors`, `collect_errors` do not exist
- Legacy functions in `term_convert.mbt` do not exist
- `parse(s) -> Term` still works
- `new_imperative_parser` + `.diagnostics()` is the error recovery path
