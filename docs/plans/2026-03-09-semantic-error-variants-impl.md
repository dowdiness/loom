# Semantic Error Variants: `Term::Unbound` — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `Term::Unbound(VarName)` so free variables are errors within the Term tree, and change `resolve()` to return `(Term, Resolution)`.

**Architecture:** Add variant to Term enum, update `resolve_walk` to rebuild the tree with `Unbound` replacements, update all consumers (`print_term`, DOT renderer, `sync_editor`). The Resolution map remains for binding-depth info.

**Tech Stack:** MoonBit, lambda example (`examples/lambda/`), editor module (`editor/`)

---

### Task 1: Add `Unbound` variant to Term and update `print_term`

**Files:**
- Modify: `examples/lambda/src/ast/ast.mbt`

**Step 1: Write failing test**

Add to `examples/lambda/src/ast/ast.mbt` after the existing `print_term` tests:

```moonbit
///|
test "print_term - unbound variant" {
  inspect(
    print_term(Term::Unbound("x")),
    content="<unbound: x>",
  )
}
```

**Step 2: Run test to verify it fails**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/ast -f ast.mbt`
Expected: FAIL — `Unbound` variant does not exist

**Step 3: Add the variant and print case**

In `examples/lambda/src/ast/ast.mbt`, add `Unbound(VarName)` to the Term enum between `Unit` and `Error`:

```moonbit
  // Unit — terminal for definition-only source files
  Unit
  // Unbound variable — semantic error from name resolution
  Unbound(VarName)
  // Error term for malformed/missing nodes
  Error(String)
```

Add the `Unbound` case in `print_term`'s `go` function, before the `Error` case:

```moonbit
      Unbound(x) => "<unbound: " + x + ">"
```

**Step 4: Run test to verify it passes**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/ast -f ast.mbt`
Expected: PASS

**Step 5: Check for exhaustiveness warnings**

Run: `cd loom/examples/lambda && moon check`
Expected: warnings or errors in files that match on Term without handling `Unbound`. Note them — they tell you what to fix in later tasks.

**Step 6: Commit**

```bash
git add examples/lambda/src/ast/ast.mbt
git commit -m "feat(ast): add Term::Unbound(VarName) variant for free variables"
```

---

### Task 2: Update `resolve` to return `(Term, Resolution)`

**Files:**
- Modify: `examples/lambda/src/resolve.mbt`

**Step 1: Write failing test**

Add to `examples/lambda/src/resolve_wbtest.mbt`:

```moonbit
///|
test "resolve: returns rewritten term with Unbound for free vars" {
  // y is free
  let term = @ast.Term::Var("y")
  let (resolved_term, res) = resolve(term)
  inspect(resolved_term, content="Unbound(\"y\")")
  inspect(res.vars.get(0), content="Some(Free)")
}

///|
test "resolve: bound vars remain as Var in rewritten term" {
  // λx. x — x is bound, stays Var
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let (resolved_term, _) = resolve(term)
  inspect(@ast.print_term(resolved_term), content="(λx. x)")
}

///|
test "resolve: mixed bound and free in rewritten term" {
  // λx. (x + y) — x bound stays Var, y free becomes Unbound
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (resolved_term, res) = resolve(term)
  inspect(
    @ast.print_term(resolved_term),
    content="(λx. (x + <unbound: y>))",
  )
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Free)")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda -f resolve_wbtest.mbt`
Expected: FAIL — resolve returns `Resolution`, not tuple

**Step 3: Update `resolve` and `resolve_walk`**

Change `resolve` signature and `resolve_walk` to rebuild the tree:

In `examples/lambda/src/resolve.mbt`:

```moonbit
///|
pub fn resolve(term : @ast.Term) -> (@ast.Term, Resolution) {
  let res : Map[Int, VarStatus] = {}
  let env : Map[String, Int] = {}
  let counter = Ref::new(0)
  let new_term = resolve_walk(term, env, 0, counter, res)
  (new_term, { vars: res })
}

///|
fn resolve_walk(
  term : @ast.Term,
  env : Map[String, Int],
  depth : Int,
  counter : Ref[Int],
  res : Map[Int, VarStatus],
) -> @ast.Term {
  let node_id = counter.val
  counter.val = counter.val + 1
  match term {
    @ast.Term::Var(x) =>
      match env.get(x) {
        Some(bind_depth) => {
          res[node_id] = Bound(depth=depth - bind_depth)
          term // bound — keep as Var
        }
        None => {
          res[node_id] = Free
          @ast.Term::Unbound(x) // free — rewrite to Unbound
        }
      }
    @ast.Term::Lam(x, body) => {
      let new_env = Map::from_iter(env.iter())
      new_env[x] = depth
      let new_body = resolve_walk(body, new_env, depth + 1, counter, res)
      @ast.Term::Lam(x, new_body)
    }
    @ast.Term::Let(x, val, body) => {
      let new_val = resolve_walk(val, env, depth, counter, res)
      let new_env = Map::from_iter(env.iter())
      new_env[x] = depth
      let new_body = resolve_walk(body, new_env, depth + 1, counter, res)
      @ast.Term::Let(x, new_val, new_body)
    }
    @ast.Term::App(f, a) => {
      let new_f = resolve_walk(f, env, depth, counter, res)
      let new_a = resolve_walk(a, env, depth, counter, res)
      @ast.Term::App(new_f, new_a)
    }
    @ast.Term::Bop(op, l, r) => {
      let new_l = resolve_walk(l, env, depth, counter, res)
      let new_r = resolve_walk(r, env, depth, counter, res)
      @ast.Term::Bop(op, new_l, new_r)
    }
    @ast.Term::If(c, t, e) => {
      let new_c = resolve_walk(c, env, depth, counter, res)
      let new_t = resolve_walk(t, env, depth, counter, res)
      let new_e = resolve_walk(e, env, depth, counter, res)
      @ast.Term::If(new_c, new_t, new_e)
    }
    _ => term // Int, Unit, Error, Unbound — return unchanged
  }
}
```

**Step 4: Run tests**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda -f resolve_wbtest.mbt`
Expected: PASS (new tests pass)

**Step 5: Commit**

```bash
git add examples/lambda/src/resolve.mbt examples/lambda/src/resolve_wbtest.mbt
git commit -m "feat(resolve): return (Term, Resolution) with Unbound rewriting"
```

---

### Task 3: Fix existing resolve tests for new return type

**Files:**
- Modify: `examples/lambda/src/resolve_wbtest.mbt`

**Step 1: Update existing tests to destructure tuple**

Every existing test has `let res = resolve(term)`. Change to `let (_, res) = resolve(term)`:

- `"resolve: free variable"` — `let (_, res) = resolve(term)`
- `"resolve: bound variable in lambda"` — `let (_, res) = resolve(term)`
- `"resolve: free and bound in lambda"` — `let (_, res) = resolve(term)`
- `"resolve: nested lambda shadows outer binding"` — `let (_, res) = resolve(term)`
- `"resolve: let binding"` — `let (_, res) = resolve(term)`
- `"resolve: var in let initializer is free"` — `let (_, res) = resolve(term)`
- `"term_to_dot_resolved: colors bound green, free red"` — `let (_, res) = resolve(term)`

**Step 2: Run all resolve tests**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda -f resolve_wbtest.mbt`
Expected: all tests PASS

**Step 3: Commit**

```bash
git add examples/lambda/src/resolve_wbtest.mbt
git commit -m "fix(tests): update resolve tests for (Term, Resolution) return type"
```

---

### Task 4: Update DOT renderer for `Unbound` variant

**Files:**
- Modify: `examples/lambda/src/dot_node.mbt`

**Step 1: Add `Unbound` cases**

In `label` impl, add before the `Error` case:

```moonbit
    @ast.Term::Unbound(x) => "Unbound(" + x + ")"
```

In `build_term_tree`, `Unbound` is a leaf (no children) — it falls through to `_ => []` already, so no change needed.

In `node_attrs`, `Unbound` nodes should be red. The current coloring uses the Resolution map (keyed by pre-order index). Since `Unbound` replaces `Var` for free variables, `res.vars.get(self.id)` returns `Some(Free)` which already colors red. No change needed — the existing logic handles it.

**Step 2: Run resolve DOT test**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda -f resolve_wbtest.mbt`
Expected: all tests PASS (including the DOT color test)

**Step 3: Verify with moon check**

Run: `cd loom/examples/lambda && moon check`
Expected: no exhaustiveness warnings for Term match in dot_node.mbt

**Step 4: Commit**

```bash
git add examples/lambda/src/dot_node.mbt
git commit -m "feat(dot): add Unbound variant to DOT label renderer"
```

---

### Task 5: Update editor consumers

**Files:**
- Modify: `editor/sync_editor.mbt` (in the crdt root, NOT in loom/)

**Step 1: Update `get_resolution` and `get_dot_resolved`**

In `editor/sync_editor.mbt`:

`get_resolution` currently returns `Resolution`. Change to destructure:

```moonbit
pub fn SyncEditor::get_resolution(self : SyncEditor) -> @parser.Resolution {
  let (_, res) = @parser.resolve(self.get_ast())
  res
}
```

`get_dot_resolved` needs the resolved term for DOT rendering. Update:

```moonbit
pub fn SyncEditor::get_dot_resolved(self : SyncEditor) -> String {
  let ast = self.get_ast()
  let (resolved_ast, res) = @parser.resolve(ast)
  @parser.term_to_dot_resolved(resolved_ast, res)
}
```

**Step 2: Check it compiles**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon check`
Expected: PASS

**Step 3: Commit**

```bash
git add editor/sync_editor.mbt
git commit -m "fix(editor): update resolve() call sites for (Term, Resolution) return"
```

---

### Task 6: Handle remaining exhaustiveness — term_convert and any other match sites

**Files:**
- Modify: any files flagged by `moon check` with exhaustiveness warnings

**Step 1: Find all Term match sites**

Run: `cd loom/examples/lambda && moon check` and note any warnings about non-exhaustive match on `Term`.

Common locations:
- `examples/lambda/src/term_convert.mbt` — `view_to_term` doesn't construct `Unbound` (no change needed since it only creates terms, doesn't match all variants)
- `examples/lambda/src/dot_node.mbt` — `build_term_tree` match on term children

For `build_term_tree` in `dot_node.mbt`, add `Unbound` to the leaf case:

```moonbit
    @ast.Term::Unbound(_) => []   // leaf, no children
```

This may already be covered by `_ => []`. Verify with `moon check`.

**Step 2: Run full test suite**

Run: `cd loom/examples/lambda && moon test`
Expected: all tests PASS

**Step 3: Commit if changes were needed**

```bash
git add examples/lambda/src/
git commit -m "fix(lambda): handle Unbound in all Term match sites"
```

---

### Task 7: Update interfaces, format, and final verification

**Step 1: Regenerate interfaces and format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
cd examples/lambda && moon info && moon fmt
```

**Step 2: Review API changes**

Run: `git diff *.mbti` — verify:
- `Term` enum now includes `Unbound(VarName)`
- `resolve` returns `(@ast.Term, Resolution)` not `Resolution`

**Step 3: Run all tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
cd examples/lambda && moon test    # lambda (311+ tests)
moon test                          # loom framework
cd ../seam && moon test            # seam
cd ../incr && moon test            # incr
```

Also test the crdt root module:
```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon check
```

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: update mbti interfaces and format for Term::Unbound"
```
