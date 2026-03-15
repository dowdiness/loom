# Flat Grammar Unification Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `lambda_grammar` and unify on `source_file_grammar` with flat `LetDef*` structure for optimal incremental parsing.

**Architecture:** Remove the right-recursive `let...in` grammar path. Switch all parser entry points to `source_file_spec` + `tokenize_layout`. Fix projection layer to compile. Rename `source_file_*` to `lambda_*` for clarity.

**Spec:** [docs/plans/2026-03-15-flat-grammar-unification.md](2026-03-15-flat-grammar-unification.md)

**Modules:** This plan spans two git repositories:
- loom submodule: `examples/lambda/`, `loom/` (all grammar, parser, test changes)
- crdt monorepo: `projection/`, `editor/` (external consumers)

---

## Preflight

Verified command shapes:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda && moon check && moon test
cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon check && moon test
```

Success criteria:
- All loom and lambda tests pass
- All crdt monorepo tests pass (`moon check && moon test` from crdt root)
- No `lambda_grammar`, `lambda_spec`, `parse_lambda_root`, `parse_let_expr`, `LetExpr`, `InKeyword`, `LetExprView`, non-layout tokenizer functions remain
- `source_file_*` names renamed to `lambda_*`
- Let-chain benchmarks use newline-delimited input

---

## Chunk 1: Core Grammar Unification

### Task 1: Remove `in`-detection from source-file grammar

**Files:**
- Modify: `examples/lambda/src/cst_parser.mbt`

The source-file grammar's `parse_source_file_let_item` (lines 516-541) currently detects `@token.In` and upgrades `LetDef` to `LetExpr`. Remove this branch so all `let` items produce `LetDef`.

- [ ] **Step 1: Remove the `In` detection branch**

In `examples/lambda/src/cst_parser.mbt`, find `parse_source_file_let_item` (lines 516-541). Remove the `@token.In` check (lines 530-537) that wraps the node as `LetExpr` when `in` is found. Keep only the `LetDef` path.

The function should always wrap as `LetDef` regardless of whether `in` follows.

- [ ] **Step 2: Remove `@token.In` from `is_sync_point`**

In the same file, find `is_sync_point` (lines 224-237). Remove the `@token.In =>` arm (line 228).

- [ ] **Step 3: Run checks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check
```

Expect warnings but no errors. Tests will fail (snapshots changed) — that's expected at this stage.

- [ ] **Step 4: Commit**

```bash
git add examples/lambda/src/cst_parser.mbt
git commit -m "refactor: remove in-detection from source-file grammar"
```

---

### Task 2: Switch parser entry points to source-file spec

**Files:**
- Modify: `examples/lambda/src/parser.mbt`
- Modify: `examples/lambda/src/cst_parser.mbt`
- Modify: `examples/lambda/src/lambda.mbt`

All parser entry points switch from `lambda_spec` + `@lexer.tokenize` to `source_file_spec` + `@lexer.tokenize_layout`.

- [ ] **Step 1: Switch `parse()` in `parser.mbt`**

`parse()` (lines 10-14) currently calls `parse_cst(input)` then `syntax_node_to_term(syn)`. Change it to call `parse_source_file_term(input)` instead (which uses `source_file_spec` and `syntax_node_to_source_file_term`). The function signature changes: it now returns `(Term, Array[Diagnostic])` and raises `LexError` instead of a generic error.

Alternatively, simplify `parse()` to wrap `parse_source_file_term` and extract just the Term, raising on lex error.

- [ ] **Step 2: Switch `parse_cst()` in `parser.mbt`**

`parse_cst()` (lines 26-33) uses `lambda_spec` and `@lexer.tokenize`. Switch to `source_file_spec` and `@lexer.tokenize_layout`.

- [ ] **Step 3: Switch `parse_cst_recover()` and related functions**

In `cst_parser.mbt`:
- `parse_cst_recover()` (around line 38-52): switch spec and tokenizer
- `parse_cst_with_cursor()` (around line 56-73): switch spec and tokenizer
- `parse_cst_recover_with_tokens()` (around line 77-94): switch spec
- `make_reuse_cursor()` (around line 6-22): switch spec and tokenizer

These functions should use `source_file_spec` and `@lexer.tokenize_layout`.

- [ ] **Step 4: Switch `new_imperative_parser` in `lambda.mbt`**

In `examples/lambda/src/lambda.mbt` (lines 25-29), change `lambda_grammar` to `source_file_grammar`.

- [ ] **Step 5: Run checks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check
```

Expect compilation to succeed. Tests will fail due to input format changes — fixed in Chunk 2.

- [ ] **Step 6: Commit**

```bash
git add examples/lambda/src/parser.mbt
git add examples/lambda/src/cst_parser.mbt
git add examples/lambda/src/lambda.mbt
git commit -m "refactor: switch all parser entry points to source-file spec"
```

---

### Task 3: Remove dead code

**Files:**
- Modify: `examples/lambda/src/grammar.mbt`
- Modify: `examples/lambda/src/lambda_spec.mbt`
- Modify: `examples/lambda/src/cst_parser.mbt`
- Modify: `examples/lambda/src/syntax/syntax_kind.mbt`
- Modify: `examples/lambda/src/views.mbt`
- Modify: `examples/lambda/src/term_convert.mbt`
- Modify: `examples/lambda/src/lexer/lexer.mbt`

- [ ] **Step 1: Remove `lambda_grammar` from `grammar.mbt`**

Remove the `lambda_grammar` definition (lines 6-22). Keep `source_file_grammar` (lines 29-45).

- [ ] **Step 2: Remove `lambda_spec` from `lambda_spec.mbt`**

Remove the `lambda_spec` definition (lines 45-52). Keep `source_file_spec` (lines 57-64).

- [ ] **Step 3: Remove `parse_lambda_root` and `parse_let_expr` from `cst_parser.mbt`**

Remove `parse_lambda_root` (lines 282-298) and `parse_let_expr` (lines 323-352).

- [ ] **Step 4: Remove `LetExpr` and `InKeyword` from syntax kinds**

In `examples/lambda/src/syntax/syntax_kind.mbt`, remove the `LetExpr` (line 29) and `InKeyword` (line 27) variants from the `SyntaxKind` enum. Update the `to_raw()` implementation to adjust raw kind numbers. Remove `InKeyword` from `syntax_kind_to_token_kind()`.

- [ ] **Step 5: Remove `LetExprView` from `views.mbt`**

Remove the `LetExprView` struct and all its methods (lines 283-340).

- [ ] **Step 6: Remove `LetExpr` handling from `term_convert.mbt`**

In `view_to_term()`, remove the `LetExpr` match arm (lines 111-122). Keep `LetDef` handling in `syntax_node_to_source_file_term()`.

- [ ] **Step 7: Remove non-layout tokenizer functions from `lexer.mbt`**

Remove:
- `tokenize()` (lines 219-223) — non-layout tokenizer
- `lambda_step_lexer()` (lines 201-206) — non-layout step lexer

Keep:
- `tokenize_layout()` (lines 252-256)
- `lambda_step_lexer_layout()` (lines 210-215)
- `@token.In` in the lexer keyword table (line 169) — kept for error messages

Also update `tokenize_range()` (lines 227-246) to call `tokenize_layout` instead of `tokenize`.

- [ ] **Step 8: Fix all compilation errors**

Run `moon check` and fix any remaining references to removed symbols. Common issues:
- Test files referencing `lambda_grammar` (fixed in Chunk 2)
- `cst_parser_wbtest.mbt` referencing `lambda_spec` (fixed in Chunk 2)
- Exhaustive match patterns on `SyntaxKind` that include `LetExpr`/`InKeyword`

- [ ] **Step 9: Commit**

```bash
git add examples/lambda/src/grammar.mbt
git add examples/lambda/src/lambda_spec.mbt
git add examples/lambda/src/cst_parser.mbt
git add examples/lambda/src/syntax/syntax_kind.mbt
git add examples/lambda/src/views.mbt
git add examples/lambda/src/term_convert.mbt
git add examples/lambda/src/lexer/lexer.mbt
git commit -m "refactor: remove lambda_grammar and all dead code"
```

---

## Chunk 2: Test Migration

### Task 4: Update test input strings and fix compilation

**Files:**
- Modify: `examples/lambda/src/imperative_parser_test.mbt`
- Modify: `examples/lambda/src/reactive_parser_test.mbt`
- Modify: `examples/lambda/src/phase4_correctness_test.mbt`
- Modify: `examples/lambda/src/error_recovery_test.mbt`
- Modify: `examples/lambda/src/cst_parser_wbtest.mbt`
- Modify: `examples/lambda/src/cst_tree_test.mbt`
- Modify: `examples/lambda/src/imperative_differential_fuzz_test.mbt`
- Modify: `examples/lambda/src/parser_test.mbt`

- [ ] **Step 1: Switch all `lambda_grammar` references to `source_file_grammar`**

Search all test files for `lambda_grammar` and replace with `source_file_grammar`:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
rg -l 'lambda_grammar' examples/lambda/src/
```

In each file, replace `lambda_grammar` with `source_file_grammar`. Also replace `@lambda.lambda_grammar` with `@lambda.source_file_grammar` in external test files.

- [ ] **Step 2: Update `let...in` input strings to newline-delimited**

Search for `in` keyword usage in test strings:

```bash
rg ' in ' examples/lambda/src/ --type mbt
```

Replace `"let x = 1 in expr"` patterns with `"let x = 1\nexpr"`. Be careful not to replace `in` that appears in other contexts (e.g., "in the middle", variable names containing "in").

- [ ] **Step 3: Switch whitebox tests from `lambda_spec` to `source_file_spec`**

In `cst_parser_wbtest.mbt`, replace `lambda_spec` with `source_file_spec` and `@lexer.tokenize` with `@lexer.tokenize_layout`.

- [ ] **Step 4: Remove LetExpr-specific tests**

- In `cst_tree_test.mbt`: remove test "source file: final let-expression is parsed as LetExpr"
- In `error_recovery_test.mbt`: remove or rewrite tests that test `missing 'in'` diagnostics
- In `cst_parser_wbtest.mbt`: remove/rewrite test for `InKeyword` trailing-context reuse

- [ ] **Step 5: Update `parser_test.mbt` parse() calls**

`parse()` now produces `SourceFile` trees via `syntax_node_to_source_file_term`. Tests calling `parse("let x = 1 in x")` need input changed to `"let x = 1\nx"`.

- [ ] **Step 6: Run checks and update snapshots**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check
moon test --update
moon test
```

Fix any remaining failures manually. Then format:

```bash
moon info && moon fmt
```

- [ ] **Step 7: Commit**

```bash
git add -u examples/lambda/src/
git add -u -- '*.mbti'
git commit -m "test: migrate all tests to source-file grammar"
```

---

### Task 5: Update benchmarks

**Files:**
- Modify: `examples/lambda/src/benchmarks/let_chain_benchmark.mbt`
- Modify: `examples/lambda/src/benchmarks/performance_benchmark.mbt`

- [ ] **Step 1: Update `make_let_chain` helper**

In `let_chain_benchmark.mbt`, change `make_let_chain` to generate newline-delimited chains:

```moonbit
fn make_let_chain(n : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < n - 1; i = i + 1 {
    segments.push("let x\{i} = 0")
  }
  segments.push("let x\{n - 1} = \{tail_literal}")
  segments.push("x\{n - 1}")
  segments.join("\n")
}
```

- [ ] **Step 2: Switch benchmark grammar references**

Replace all `lambda_grammar` with `source_file_grammar` in benchmark files.

- [ ] **Step 3: Update edit positions in benchmarks**

The let-chain benchmarks compute edit positions based on string offsets. With newline-delimited format, positions change. Recompute `edit_pos` for each benchmark that edits the tail literal.

- [ ] **Step 4: Run benchmarks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check
moon test
moon bench --release 2>&1 | grep -E "let-chain|phase"
```

Verify benchmarks compile and run. Record results for comparison.

- [ ] **Step 5: Commit**

```bash
git add examples/lambda/src/benchmarks/
git commit -m "bench: migrate let-chain benchmarks to flat grammar"
```

---

## Chunk 3: External Consumers

### Task 6: Fix projection layer

**Files:**
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/proj_node.mbt`
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/tree_lens.mbt`

These files are in the crdt monorepo, not the loom submodule. Update the loom submodule pointer first, then fix these files.

- [ ] **Step 1: Update loom submodule pointer in crdt**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
git add loom
git commit -m "chore: update loom submodule pointer"
```

- [ ] **Step 2: Fix `proj_node.mbt`**

In `projection/proj_node.mbt`:
- Replace `@parser.lambda_grammar` (line 360) with `@parser.source_file_grammar`
- Update `syntax_to_proj_node()` to handle `LetDef` instead of `LetExpr`:
  - Remove `LetExprView` matching (lines 187-202)
  - Use `source_file_to_proj_node()` (lines 235-269) pattern which already handles `LetDef`
  - Or redirect the single-expression path to go through `source_file_to_proj_node`

- [ ] **Step 3: Fix `tree_lens.mbt`**

In `projection/tree_lens.mbt`:
- Line 338: Change Let placeholder from `"let x = 0 in x"` to constructing a `LetDef` CST node directly via `@seam.CstNode::new` with appropriate children, or use `"let x = 0\nx"` as the placeholder text
- Line 360: Replace `@parser.lambda_grammar` with `@parser.source_file_grammar`

- [ ] **Step 4: Fix any remaining compilation errors**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon check
```

Fix all errors. Common issues: exhaustive matches on `SyntaxKind` that include removed variants.

- [ ] **Step 5: Run all tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon test
moon test --update  # if snapshot changes
moon test
```

- [ ] **Step 6: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
git add projection/proj_node.mbt projection/tree_lens.mbt
git commit -m "fix: update projection layer for flat grammar"
```

---

## Chunk 4: Rename and Finalize

### Task 7: Rename source_file_* to lambda_*

**Files:**
- Modify: `examples/lambda/src/grammar.mbt`
- Modify: `examples/lambda/src/lambda_spec.mbt`
- Modify: `examples/lambda/src/lexer/lexer.mbt`
- Modify: `examples/lambda/src/cst_parser.mbt`
- Modify: `examples/lambda/src/parser.mbt`
- Modify: all test files referencing `source_file_grammar`
- Modify: all crdt monorepo files referencing `source_file_grammar`

Sequencing: old names are already removed (Task 3), so renaming won't conflict.

- [ ] **Step 1: Rename grammar and spec**

In `grammar.mbt`: rename `source_file_grammar` → `lambda_grammar`
In `lambda_spec.mbt`: rename `source_file_spec` → `lambda_spec`

- [ ] **Step 2: Rename tokenizer functions**

In `lexer/lexer.mbt`:
- `tokenize_layout` → `tokenize`
- `lambda_step_lexer_layout` → `lambda_step_lexer`

- [ ] **Step 3: Rename parser functions**

In `cst_parser.mbt` and `parser.mbt`:
- `parse_source_file_root` → `parse_root` or keep
- `parse_source_file_term` → `parse_term` or keep
- `parse_source_file_let_item` → `parse_let_item` or keep
- `make_source_file_reuse_cursor` → `make_reuse_cursor`
- `parse_source_file_recover_with_tokens` → `parse_cst_recover_with_tokens`

- [ ] **Step 4: Update all references**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
rg 'source_file_grammar|source_file_spec|tokenize_layout|lambda_step_lexer_layout' examples/lambda/src/
```

Update every reference. Also update in crdt monorepo:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
rg 'source_file_grammar|source_file_spec' projection/ editor/
```

- [ ] **Step 5: Update interfaces and format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon info && moon fmt
moon check && moon test
```

- [ ] **Step 6: Final regression pass**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda && moon test
cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test
```

All tests must pass.

- [ ] **Step 7: Update README**

Update `examples/lambda/README.md` to reflect the unified grammar. Remove references to `lambda_grammar` vs `source_file_grammar` distinction.

- [ ] **Step 8: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add -u
git add -u -- '*.mbti'
git commit -m "refactor: rename source_file_* to lambda_* after unification"
```

Also commit in crdt monorepo:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
git add -u
git commit -m "refactor: follow loom grammar rename"
```

---

### Task 8: Record benchmark results

**Files:**
- Modify: `docs/performance/benchmark_history.md`

- [ ] **Step 1: Run full benchmark suite**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon bench --release
```

- [ ] **Step 2: Record results**

Add a dated entry to `docs/performance/benchmark_history.md` with before/after numbers for let-chain benchmarks. The key comparison: incremental vs full reparse on flat grammar should now show incremental as faster.

- [ ] **Step 3: Commit**

```bash
git add docs/performance/benchmark_history.md
git commit -m "docs: record flat grammar benchmark results"
```
