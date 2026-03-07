# Term::Error Variant Implementation Plan

**Status:** Complete (2026-03-05)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the 18 `Term::Var("<error>")` string sentinels in `view_to_term` with a proper `Term::Error(String)` variant, making error terms type-safe and distinguishable from real variables.

**Architecture:** Add `Error(String)` to the `Term` enum, update `print_term` to render it as `"<error: msg>"`, then replace all sentinel sites in `view_to_term`/`syntax_node_to_term`. Fix any exhaustive match sites broken by the new variant. No evaluator exists yet so downstream impact is minimal.

**Tech Stack:** MoonBit, `moon check`, `moon test`, `moon info && moon fmt`

---

### Task 1: Add Term::Error and update print_term

**Files:**
- Modify: `examples/lambda/src/ast/ast.mbt`

**Step 1: Write a failing test**

Add to the bottom of `examples/lambda/src/ast/ast.mbt`:

```moonbit
///|
test "print_term - error variant" {
  inspect(@ast.print_term(Term::Error("missing body")), content="<error: missing body>")
  inspect(@ast.print_term(Term::Error("")), content="<error: >")
}
```

**Step 2: Run to verify it fails**

Run (from `examples/lambda/`):
```bash
moon test -p dowdiness/lambda/ast
```
Expected: compile error — `Term::Error` does not exist yet.

**Step 3: Add the variant and update print_term**

In `examples/lambda/src/ast/ast.mbt`, add `Error(String)` to the `Term` enum:

```moonbit
pub(all) enum Term {
  Int(Int)
  Var(VarName)
  Lam(VarName, Term)
  App(Term, Term)
  Bop(Bop, Term, Term)
  If(Term, Term, Term)
  Let(VarName, Term, Term)
  Error(String)
} derive(Show, Eq)
```

Add the `Error` arm to `print_term` (inside the `go` function):

```moonbit
Error(msg) => "<error: " + msg + ">"
```

**Step 4: Run to verify it passes**

```bash
moon test -p dowdiness/lambda/ast
```
Expected: PASS

**Step 5: Commit**

```bash
git add examples/lambda/src/ast/ast.mbt
git commit -m "feat(ast): add Term::Error(String) variant and update print_term"
```

---

### Task 2: Fix exhaustive matches broken by the new variant

Adding `Error(String)` to `Term` will break any `match` that does not have a catch-all `_` arm. Run `moon check` to find them.

**Files:**
- Modify: `examples/lambda/src/parser_properties_test.mbt` (has `check_well_formed` that walks Term)
- Possibly others — let `moon check` be the guide

**Step 1: Run moon check to find exhaustive match errors**

```bash
moon check 2>&1 | grep -A5 "non-exhaustive\|missing case\|Error"
```

**Step 2: Fix each broken match**

The most likely site is `check_well_formed` in `parser_properties_test.mbt`. Add an `Error` arm that asserts the string is non-empty (errors always carry a message):

```moonbit
Term::Error(_) => () // error terms from recovery are valid Term values
```

For any match in production code, add:
```moonbit
Term::Error(_) => abort("unreachable: parse() raises before producing Error terms")
```

**Step 3: Run moon check and moon test**

```bash
moon check && moon test
```
Expected: all 290 tests pass.

**Step 4: Commit**

```bash
git add examples/lambda/src/
git commit -m "fix(lambda): handle Term::Error in exhaustive match sites"
```

---

### Task 3: Replace sentinels in view_to_term and syntax_node_to_term

**Files:**
- Modify: `examples/lambda/src/term_convert.mbt`

**Step 1: Write a test that distinguishes Term::Error from Term::Var**

Add to `examples/lambda/src/parse_tree_test.mbt` (or `error_recovery_phase3_test.mbt`):

```moonbit
///|
test "syntax_node_to_term: missing lambda body produces Term::Error" {
  let (cst, _) = parse_cst_recover("λx.") catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(root)
  // Body of the lambda should be Term::Error, not Term::Var("<error>")
  let printed = @ast.print_term(term)
  inspect(printed.contains("<error:"), content="true")
  // Must NOT be a Var sentinel
  inspect(term is @ast.Term::Var(_), content="false")
}
```

**Step 2: Run to verify it fails**

```bash
moon test -p dowdiness/lambda -- "missing lambda body produces Term::Error"
```
Expected: FAIL — currently returns `Term::Var("<error>")` so `term is @ast.Term::Var(_)` is true.

**Step 3: Replace all sentinels in term_convert.mbt**

In `examples/lambda/src/term_convert.mbt`, replace every `@ast.Term::Var("<error>")` and `@ast.Term::Var("<empty>")` with `@ast.Term::Error(...)` carrying a specific message.

Complete replacement table for `view_to_term`:

| Old sentinel | New term | Location |
|---|---|---|
| `Term::Var("<empty>")` | `Term::Error("empty SourceFile")` | `syntax_node_to_term`, SourceFile has no child |
| `Term::Var("<error>")` (IntLiteral cast None) | `Term::Error("IntLiteral: cast failed")` | dead code — outer match guarantees kind |
| `Term::Var("<error>")` (VarRef cast None) | `Term::Error("VarRef: cast failed")` | dead code |
| `Term::Var("<error>")` (LambdaExpr body None) | `Term::Error("missing lambda body")` | **live** — recovery produces bodyless lambda |
| `Term::Var("<error>")` (LambdaExpr cast None) | `Term::Error("LambdaExpr: cast failed")` | dead code |
| `Term::Var("<error>")` (AppExpr func None) | `Term::Error("missing function in application")` | **live** |
| `Term::Var("<error>")` (AppExpr cast None) | `Term::Error("AppExpr: cast failed")` | dead code |
| `Term::Var("<error>")` (BinaryExpr empty) | `Term::Error("empty BinaryExpr")` | **live** |
| `Term::Var("<error>")` (BinaryExpr cast None) | `Term::Error("BinaryExpr: cast failed")` | dead code |
| `Term::Var("<error>")` (IfExpr condition None) | `Term::Error("missing if condition")` | **live** |
| `Term::Var("<error>")` (IfExpr then None) | `Term::Error("missing then branch")` | **live** |
| `Term::Var("<error>")` (IfExpr else None) | `Term::Error("missing else branch")` | **live** |
| `Term::Var("<error>")` (IfExpr cast None) | `Term::Error("IfExpr: cast failed")` | dead code |
| `Term::Var("<error>")` (LetExpr init None) | `Term::Error("missing let binding value")` | **live** |
| `Term::Var("<error>")` (LetExpr body None) | `Term::Error("missing let body")` | **live** |
| `Term::Var("<error>")` (LetExpr cast None) | `Term::Error("LetExpr: cast failed")` | dead code |
| `Term::Var("<error>")` (ParenExpr inner None) | `Term::Error("empty parentheses")` | **live** |
| `Term::Var("<error>")` (ParenExpr cast None) | `Term::Error("ParenExpr: cast failed")` | dead code |
| `@syntax.ErrorNode => Term::Var("<error>")` | `@syntax.ErrorNode => Term::Error("error node")` | **live** |

**Step 4: Run to verify the test passes**

```bash
moon test
```
Expected: 290 tests pass (snapshot tests will update automatically via `moon test --update` if any `content=` strings change).

If snapshot tests fail due to `print_term` output changing, check whether any test was previously matching `Term::Var("<error>")` via `print_term` (it would have printed as `"<error>"` before, now prints as `"<error: msg>"`). Update those snapshots with `moon test --update` and verify the new content is correct.

**Step 5: Commit**

```bash
git add examples/lambda/src/term_convert.mbt examples/lambda/src/parse_tree_test.mbt
git commit -m "refactor(lambda): replace Term::Var sentinels with Term::Error in view_to_term"
```

---

### Task 4: Finalize — interfaces, docs, full suite

**Files:**
- Modify: `examples/lambda/src/ast/pkg.generated.mbti` (auto-generated)
- Modify: `docs/README.md`

**Step 1: Regenerate .mbti interfaces and format**

```bash
cd examples/lambda && moon info && moon fmt
```

**Step 2: Verify the .mbti diff shows Error added correctly**

```bash
git diff -- examples/lambda/src/ast/pkg.generated.mbti
```

Expected additions:
```diff
+pub(all) enum Term {
+  ...
+  Error(String)
+}
```

**Step 3: Run full test suite**

```bash
moon test
```
Expected: all tests pass (same count as before — no tests removed).

**Step 4: Update docs/README.md**

Add the new plan file to the Active Plans section (or if this is being archived on completion, to the Archive section). Run `bash check-docs.sh` to verify.

**Step 5: Final commit**

```bash
git add examples/lambda/src/ast/pkg.generated.mbti docs/README.md
git commit -m "chore(lambda): regenerate .mbti after Term::Error addition"
```
