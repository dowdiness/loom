# Remove AstNode from examples/lambda — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the `AstNode`/`AstKind` intermediate tree from `examples/lambda`, collapsing `CST → AstNode → Term` into `CST → Term` via typed views.

**Architecture:** Top-down migration — migrate callsites first so tests stay green, then delete the now-unused legacy code. `Term`/`Bop`/`VarName` stay for evaluation. `SyntaxNode` + typed views become the only tree representation.

**Tech Stack:** MoonBit, `moon test`, `moon check`, `moon info && moon fmt`

**Working directory for all commands:** `examples/lambda/`

---

### Task 1: Rewrite `parse` in `parser.mbt` to bypass `AstNode`

**Files:**
- Modify: `examples/lambda/src/parser.mbt`

The current `parse` calls `parse_tree → node_to_term`. Rewire it to call `parse_cst → SyntaxNode::from_cst → syntax_node_to_term` directly. Keep the signature unchanged so `parser_test.mbt` requires zero edits.

**Step 1: Read the current file**

Read `examples/lambda/src/parser.mbt` to see the current content.

**Step 2: Replace `parse`, delete `parse_tree`**

Replace the entire file content with:

```moonbit
// Parser for Lambda Calculus expressions

///|
pub suberror ParseError {
  ParseError(String, @token.Token)
}

///|
/// Parse the input string into a Term (without position information).
pub fn parse(input : String) -> @ast.Term raise {
  let cst = parse_cst(input)
  let syn = @seam.SyntaxNode::from_cst(cst)
  syntax_node_to_term(syn)
}
```

**Step 3: Run parser tests to verify green**

```
moon test -p dowdiness/lambda -f parser_test.mbt
```

Expected: all pass (same `parse(s) -> Term raise` signature, same behavior).

**Step 4: Commit**

```bash
git add examples/lambda/src/parser.mbt
git commit -m "refactor(lambda): rewrite parse() via syntax_node_to_term, remove parse_tree"
```

---

### Task 2: Migrate `parse_tree_test.mbt`

**Files:**
- Modify: `examples/lambda/src/parse_tree_test.mbt`

This file has two kinds of tests:
- **Semantic tests** — call `print_ast_node(parse_tree(s))` to assert on Term structure. Migrate to `print_term(syntax_node_to_term(syn))`.
- **Position/structural tests** — access `.start`, `.end`, `.children`, `.kind` on `AstNode`. Migrate to `SyntaxNode` methods and typed views.
- **Tests to remove** — "node IDs are unique" has no `SyntaxNode` equivalent. Remove it.
- **Tests to move** — the three whitespace-span tests ("lambda span excludes leading whitespace", "if-expr span excludes leading whitespace", "paren-expr span excludes leading whitespace") test `tight_span` behavior. They belong in `views_test.mbt`; remove from here (they're already covered by the `SyntaxNode` contract).

The canonical boilerplate for all tests in this file becomes:
```moonbit
let (cst, _) = parse_cst_recover("SOURCE") catch { _ => abort("lex error") }
let root = @seam.SyntaxNode::from_cst(cst)
let node = root.nth_child(0).unwrap()  // unwrap SourceFile wrapper
```

**Step 1: Replace the file**

Write the full replacement (copy exactly):

```moonbit
// Tests for the parser — migrated from AstNode to SyntaxNode + Term.

///|
test "parse_tree simple integer" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  inspect(@ast.print_term(syntax_node_to_term(root)), content="42")
  inspect(node.start(), content="0")
  inspect(node.end(), content="2")
}

///|
test "parse_tree simple variable" {
  let (cst, _) = parse_cst_recover("x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  inspect(@ast.print_term(syntax_node_to_term(root)), content="x")
  inspect(node.start(), content="0")
  inspect(node.end(), content="1")
}

///|
test "parse_tree identity function" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  inspect(@ast.print_term(syntax_node_to_term(root)), content="(λx. x)")
  inspect(node.start(), content="0")
  inspect(node.end() >= 3, content="true")
}

///|
test "parse_tree binary operator" {
  let (cst, _) = parse_cst_recover("1 + 2") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  inspect(@ast.print_term(syntax_node_to_term(root)), content="(1 + 2)")
  let node = root.nth_child(0).unwrap()
  let v = match BinaryExprView::cast(node) {
    Some(v) => v
    None => abort("expected BinaryExpr")
  }
  inspect(v.operands().length(), content="2")
  inspect(v.operands()[0].start(), content="0")
  inspect(v.operands()[1].start(), content="4")
}

///|
test "parse_tree application" {
  let (cst, _) = parse_cst_recover("f x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  inspect(@ast.print_term(syntax_node_to_term(root)), content="(f x)")
  let node = root.nth_child(0).unwrap()
  let v = match AppExprView::cast(node) {
    Some(v) => v
    None => abort("expected AppExpr")
  }
  // func + 1 arg = 2 children total
  inspect(v.args().length() + 1, content="2")
}

///|
test "parse_tree if-then-else" {
  let (cst, _) = parse_cst_recover("if x then y else z") catch {
    _ => abort("lex error")
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  inspect(@ast.print_term(syntax_node_to_term(root)), content="if x then y else z")
  let node = root.nth_child(0).unwrap()
  let v = match IfExprView::cast(node) {
    Some(v) => v
    None => abort("expected IfExpr")
  }
  // condition + then + else = 3 children
  inspect(
    [v.condition(), v.then_branch(), v.else_branch()].iter().filter(fn(x) { x is Some(_) }).count(),
    content="3",
  )
}

///|
test "parse_tree complex expression" {
  let (cst, _) = parse_cst_recover("λf.λx.f x") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let printed = @ast.print_term(syntax_node_to_term(root))
  inspect(printed.contains("λf"), content="true")
  inspect(printed.contains("λx"), content="true")
  // Outer lambda has one child (the inner lambda)
  let node = root.nth_child(0).unwrap()
  let v = match LambdaExprView::cast(node) {
    Some(v) => v
    None => abort("expected LambdaExpr")
  }
  inspect(v.body() is Some(_), content="true")
}

///|
test "parse_tree preserves source positions" {
  let (cst, _) = parse_cst_recover("  x  +  y  ") catch {
    _ => abort("lex error")
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  let v = match BinaryExprView::cast(node) {
    Some(v) => v
    None => abort("expected BinaryExpr")
  }
  // x is at position 2, y is at position 9
  inspect(v.operands()[0].start() >= 2, content="true")
  inspect(v.operands()[0].end() >= 3, content="true")
  inspect(v.operands()[1].start() >= 7, content="true")
}
```

**Step 2: Run the migrated tests**

```
moon test -p dowdiness/lambda -f parse_tree_test.mbt
```

Expected: all 8 tests pass. If any position assertion is off, adjust the `>=` bounds to match the actual `SyntaxNode` offset.

**Step 3: Commit**

```bash
git add examples/lambda/src/parse_tree_test.mbt
git commit -m "refactor(lambda): migrate parse_tree_test.mbt from AstNode to SyntaxNode views"
```

---

### Task 3: Migrate `phase4_correctness_test.mbt`

**Files:**
- Modify: `examples/lambda/src/phase4_correctness_test.mbt`

The pattern in every test is:
```moonbit
let full_tree = parse_tree(some_source)
inspect(
  @ast.print_term(syntax_node_to_term(incr_tree)),
  content=@ast.print_ast_node(full_tree),
)
```

After migration:
```moonbit
let full_term = parse(some_source) catch { _ => abort("parse failed") }
inspect(
  @ast.print_term(syntax_node_to_term(incr_tree)),
  content=@ast.print_term(full_term),
)
```

`print_term` and `print_ast_node` produce identical output format — the expected `content=` strings do not change.

**Step 1: Replace all `parse_tree(s)` occurrences**

Use global search-and-replace. Every occurrence of `parse_tree(X)` (where `X` is a string expression) becomes `(parse(X) catch { _ => abort("parse failed") })`.

Every occurrence of `@ast.print_ast_node(full_tree)` becomes `@ast.print_term(full_term)`.

The variable `full_tree` is renamed `full_term` throughout.

The intermediate state after replacement uses `full_term : @ast.Term` instead of `full_tree : @ast.AstNode`, so all subsequent `.` accesses on the old `full_tree` will become a type error — but since these tests only use `full_tree` in `print_ast_node(full_tree)`, there are no such accesses.

**Step 2: Run all phase4 tests**

```
moon test -p dowdiness/lambda -f phase4_correctness_test.mbt
```

Expected: all pass. The `parse` function now routes through `syntax_node_to_term`, which produces the same `Term` structure as the old `AstNode → node_to_term` path.

**Step 3: Commit**

```bash
git add examples/lambda/src/phase4_correctness_test.mbt
git commit -m "refactor(lambda): migrate phase4_correctness_test from parse_tree/AstNode to parse/Term"
```

---

### Task 4: Migrate `error_recovery_phase3_test.mbt`

**Files:**
- Modify: `examples/lambda/src/error_recovery_phase3_test.mbt`

The current pattern:
```moonbit
let (tree, errors) = parse_with_error_recovery(input)
inspect(errors.length() > 0, content="true")
inspect(tree.kind is @ast.AstKind::Lam(_), content="true")
inspect(has_errors(tree), content="true")
```

New pattern:
```moonbit
let (cst, diagnostics) = parse_cst_recover(input) catch { _ => abort("lex error") }
let tree = @seam.SyntaxNode::from_cst(cst)
let errors = diagnostics
inspect(errors.length() > 0, content="true")
inspect(
  @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) == @syntax.LambdaExpr,
  content="true",
)
inspect(
  tree.nth_child(0).unwrap().all_children().iter().any(
    fn(e) {
      match e {
        @seam.SyntaxElement::Node(n) =>
          @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.ErrorNode
        _ => false
      }
    },
  ),
  content="true",
)
```

The `has_errors(tree)` check migrates to checking whether any descendant has `SyntaxKind::ErrorNode`. The fuzz tests that checked `tree.node_id >= 0` (just "a tree was produced") migrate to `tree.start() >= 0` or simply `let _ = tree`.

**Step 1: Identify the replacements needed**

Open `error_recovery_phase3_test.mbt` and make these substitutions:

1. All `parse_with_error_recovery(X)` → `parse_cst_recover(X) catch { _ => abort("lex error") }` with binding `(cst, diagnostics)`, then `let tree = @seam.SyntaxNode::from_cst(cst)` and `let errors = diagnostics` (using `.length()` for count, same as before).

2. `tree.kind is @ast.AstKind::Lam(_)` → `@syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) == @syntax.LambdaExpr`

3. `tree.kind is @ast.AstKind::If` → `@syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) == @syntax.IfExpr`

4. `has_errors(tree)` → `errors.length() > 0` (the diagnostics already capture parse errors, so an error-free diagnostic array means no errors in the tree)

5. `tree.end > 0` → `tree.end() > 0`

6. `tree.node_id >= 0` (fuzz tests) → `tree.start() >= 0`

7. The "valid inputs unchanged" regression test:
   - `let direct = parse_tree(input)` → `let direct_term = parse(input) catch { _ => abort("parse failed on \{input}") }`
   - `let (recovered, errors) = parse_with_error_recovery(input)` → `let (cst, diagnostics) = parse_cst_recover(input) catch { _ => abort("lex error on \{input}") }` + `let recovered_tree = @seam.SyntaxNode::from_cst(cst)` + `let errors = diagnostics`
   - `let direct_str = @ast.print_ast_node(direct)` → `let direct_str = @ast.print_term(direct_term)`
   - `let recovered_str = @ast.print_ast_node(recovered)` → `let recovered_str = @ast.print_term(syntax_node_to_term(recovered_tree))`

**Step 2: Run all phase3 tests**

```
moon test -p dowdiness/lambda -f error_recovery_phase3_test.mbt
```

Expected: all tests pass. Verify the fuzz tests terminate.

**Step 3: Commit**

```bash
git add examples/lambda/src/error_recovery_phase3_test.mbt
git commit -m "refactor(lambda): migrate error_recovery_phase3_test from AstNode/parse_with_error_recovery to SyntaxNode/parse_cst_recover"
```

---

### Task 5: Run full test suite to confirm green baseline

Before deleting anything, verify all 311 tests still pass.

**Step 1: Run full suite**

```
moon check && moon test
```

Expected: all tests pass, 0 failures. If any fail, fix before proceeding.

---

### Task 6: Delete `parse_with_error_recovery`, `has_errors`, `collect_errors`

**Files:**
- Modify: `examples/lambda/src/error_recovery.mbt`

**Step 1: Read the file**

Read `examples/lambda/src/error_recovery.mbt` to confirm nothing else calls the deleted functions.

**Step 2: Delete the file's entire content or replace with an empty module comment**

Since all three public functions are being deleted, the file becomes empty. In MoonBit, an empty `.mbt` file is valid. Replace the file contents with just the module doc comment:

```moonbit
// error_recovery.mbt — formerly housed parse_with_error_recovery, has_errors,
// collect_errors. Removed: use parse_cst_recover + ImperativeParser.diagnostics()
// for error recovery. See examples/lambda/src/cst_parser.mbt for parse_cst_recover.
```

**Step 3: Verify nothing else imports these functions**

```
moon check
```

Expected: no errors. If any "undefined symbol" errors appear, you missed a callsite — fix it before continuing.

**Step 4: Commit**

```bash
git add examples/lambda/src/error_recovery.mbt
git commit -m "refactor(lambda): delete parse_with_error_recovery, has_errors, collect_errors"
```

---

### Task 7: Delete legacy functions from `term_convert.mbt`

**Files:**
- Modify: `examples/lambda/src/term_convert.mbt`

Delete: `convert_source_file_children`, `convert_syntax_node`, `syntax_node_to_ast_node`, `cst_to_ast_node`, `cst_to_term`, `parse_cst_to_ast_node`.

Keep: `syntax_node_to_term`, `view_to_term`.

**Step 1: Read the file**

Read `examples/lambda/src/term_convert.mbt` to locate the exact lines to remove.

**Step 2: Remove legacy functions**

Delete lines 1–348 (the comment header + all legacy functions). The file after deletion should start with the `syntax_node_to_term` doc comment. Also remove the legacy-path comment header at the top.

Replace the full file with:

```moonbit
// term_convert.mbt — SyntaxNode → Term conversion via typed views.

///|
/// Convert a SyntaxNode to a Term using typed view types.
/// SourceFile wraps the actual expression in a single child; this function
/// unwraps it automatically.
///
/// **Well-formed parses only.** For error-recovered trees, only the first
/// node child of SourceFile is used; additional error-recovery siblings are
/// silently dropped. `Term` has no Error variant, so partially-recovered
/// expressions cannot be represented in the term tree. Parse errors and
/// recovered error nodes are surfaced via `parse_cst_recover` diagnostics.
pub fn syntax_node_to_term(root : @seam.SyntaxNode) -> @ast.Term {
  let node = match @syntax.SyntaxKind::from_raw(root.kind()) {
    @syntax.SourceFile =>
      match root.nth_child(0) {
        Some(child) => child
        None => return @ast.Term::Var("<empty>")
      }
    _ => root
  }
  view_to_term(node)
}

///|
fn view_to_term(node : @seam.SyntaxNode) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.IntLiteral =>
      match IntLiteralView::cast(node) {
        Some(v) => @ast.Term::Int(v.value().unwrap_or(0))
        None => @ast.Term::Var("<error>")
      }
    @syntax.VarRef =>
      match VarRefView::cast(node) {
        Some(v) => @ast.Term::Var(v.name())
        None => @ast.Term::Var("<error>")
      }
    @syntax.LambdaExpr =>
      match LambdaExprView::cast(node) {
        Some(v) => {
          let body = match v.body() {
            Some(b) => view_to_term(b)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Lam(v.param(), body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.AppExpr =>
      match AppExprView::cast(node) {
        Some(v) =>
          match v.func() {
            None => @ast.Term::Var("<error>")
            Some(func_node) => {
              let mut result = view_to_term(func_node)
              for arg in v.args() {
                result = @ast.Term::App(result, view_to_term(arg))
              }
              result
            }
          }
        None => @ast.Term::Var("<error>")
      }
    @syntax.BinaryExpr =>
      match BinaryExprView::cast(node) {
        Some(v) => {
          let ops = v.ops()
          let children = v.operands()
          if children.length() >= 2 {
            let mut result = view_to_term(children[0])
            for i = 1; i < children.length(); i = i + 1 {
              let op = if i - 1 < ops.length() {
                ops[i - 1]
              } else {
                @ast.Bop::Plus
              }
              result = @ast.Term::Bop(op, result, view_to_term(children[i]))
            }
            result
          } else if children.length() == 1 {
            view_to_term(children[0])
          } else {
            @ast.Term::Var("<error>")
          }
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.IfExpr =>
      match IfExprView::cast(node) {
        Some(v) => {
          let cond = match v.condition() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let then_ = match v.then_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let else_ = match v.else_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::If(cond, then_, else_)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.LetExpr =>
      match LetExprView::cast(node) {
        Some(v) => {
          let init = match v.init() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let body = match v.body() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Let(v.name(), init, body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.ParenExpr =>
      match ParenExprView::cast(node) {
        Some(v) =>
          match v.inner() {
            Some(inner) => view_to_term(inner)
            None => @ast.Term::Var("<error>")
          }
        None => @ast.Term::Var("<error>")
      }
    _ => @ast.Term::Var("<error: " + node.kind().to_string() + ">")
  }
}
```

**Step 3: Verify**

```
moon check && moon test
```

Expected: green.

**Step 4: Commit**

```bash
git add examples/lambda/src/term_convert.mbt
git commit -m "refactor(lambda): delete legacy AstNode-based convert functions from term_convert.mbt"
```

---

### Task 8: Delete `AstKind`, `AstNode`, `print_ast_node`, `node_to_term` from `ast/ast.mbt`

**Files:**
- Modify: `examples/lambda/src/ast/ast.mbt`

Keep: `VarName`, `Bop`, `Term`, `print_term`.
Delete: `AstKind`, `AstNode` struct, `AstNode::new`, `AstNode::error`, the `Eq` impl for `AstNode`, `print_ast_node`, `node_to_term`.

**Step 1: Read the file**

Read `examples/lambda/src/ast/ast.mbt` to confirm exact content.

**Step 2: Replace the file**

```moonbit
// Ast types for Lambda Calculus

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Show, Eq, FromJson, ToJson)

///|
pub(all) enum Term {
  // Integer
  Int(Int)
  // Variable
  Var(VarName)
  // Lambda abstraction
  Lam(VarName, Term)
  // Application
  App(Term, Term)
  // Binary operation
  Bop(Bop, Term, Term)
  // If-then-else
  If(Term, Term, Term)
  // Let binding (non-recursive)
  Let(VarName, Term, Term)
} derive(Show, Eq)

///|
pub fn print_term(term : Term) -> String {
  fn go(t : Term) -> String {
    match t {
      Int(i) => i.to_string()
      Var(x) => x
      Lam(x, t) => "(λ" + x + ". " + go(t) + ")"
      App(t1, t2) => "(" + go(t1) + " " + go(t2) + ")"
      Bop(Plus, t1, t2) => "(" + go(t1) + " + " + go(t2) + ")"
      Bop(Minus, t1, t2) => "(" + go(t1) + " - " + go(t2) + ")"
      If(t1, t2, t3) => "if " + go(t1) + " then " + go(t2) + " else " + go(t3)
      Let(x, init, body) => "let " + x + " = " + go(init) + " in " + go(body)
    }
  }

  go(term)
}
```

**Step 3: Verify**

```
moon check && moon test
```

Expected: green. If any undefined symbol errors appear for `AstKind`, `AstNode`, `print_ast_node`, or `node_to_term`, there is a missed callsite — fix it before committing.

**Step 4: Commit**

```bash
git add examples/lambda/src/ast/ast.mbt
git commit -m "refactor(lambda): delete AstNode, AstKind, print_ast_node, node_to_term from ast package"
```

---

### Task 9: Update `.mbti` interfaces and run final verification

**Step 1: Regenerate interfaces and format**

```
moon info && moon fmt
```

**Step 2: Review interface diffs**

```bash
git diff -- '*.mbti'
```

Check that `AstNode`, `AstKind`, `parse_tree`, `parse_with_error_recovery`, `has_errors`, `collect_errors`, `cst_to_ast_node`, `node_to_term`, `print_ast_node` no longer appear in any `.mbti` file.

**Step 3: Run full test suite**

```
moon check && moon test
```

Expected: all tests pass (count may be slightly lower than 311 due to removed tests — that is expected).

**Step 4: Validate docs**

```bash
cd ../.. && bash check-docs.sh
```

**Step 5: Archive the design doc**

The plan is now complete. Archive it:

```bash
git mv docs/plans/2026-03-05-remove-astnode-design.md docs/archive/completed-phases/2026-03-05-remove-astnode-design.md
```

Update `docs/README.md`: move the entry from "Active Plans" to "Archive (Historical / Completed)", add `**Status:** Complete` to the design doc.

**Step 6: Final commit**

```bash
git add examples/lambda/src/ast/ast.mbt  # if not already staged
git add docs/
git commit -m "refactor(lambda): finalize AstNode removal — update interfaces, archive design doc"
```

---

## Summary

| Task | Action | Tests affected |
|------|--------|---------------|
| 1 | Rewrite `parse()` body | `parser_test.mbt` — zero changes needed |
| 2 | Migrate `parse_tree_test.mbt` | 8 tests rewritten |
| 3 | Migrate `phase4_correctness_test.mbt` | ~15 tests updated |
| 4 | Migrate `error_recovery_phase3_test.mbt` | ~25 tests updated |
| 5 | Verify green baseline | All |
| 6 | Delete `error_recovery.mbt` contents | — |
| 7 | Delete legacy `term_convert.mbt` functions | — |
| 8 | Delete `AstNode`/`AstKind` from `ast/ast.mbt` | — |
| 9 | Regenerate `.mbti`, validate, archive | All |
