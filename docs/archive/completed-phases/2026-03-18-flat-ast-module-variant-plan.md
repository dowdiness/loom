# Flat AST: `Term::Module` Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace right-recursive `Term::Let(VarName, Term, Term)` with flat `Term::Module(Array[(VarName, Term)], Term)` so that the CstFold SourceFile algebra produces O(1) AST construction instead of O(n) right-fold allocations.

**Architecture:** Remove `Let` variant from the `Term` enum, add `Module(Array[(VarName, Term)], Term)`. The SourceFile fold algebra produces `Module` directly from the flat LetDef list. All match sites in loom (`examples/lambda/`) and parent crdt repo (`projection/`) are updated. Scoping semantics preserved exactly.

**Spec:** [docs/plans/2026-03-18-flat-ast-module-variant.md](2026-03-18-flat-ast-module-variant.md)

**Modules:** This plan spans two git repositories:
- loom submodule: `examples/lambda/src/` (Term enum, fold, resolve, DOT, tests)
- crdt monorepo: `projection/` (proj_node, flat_proj, reconcile, tree_editor, tree_lens)

---

## Preflight

Verify starting state:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda && moon check && moon test
cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon check && moon test
```

Success criteria:
- All loom and lambda tests pass
- All crdt monorepo tests pass
- No `Term::Let` remains anywhere in production code
- `print_term` output is identical before and after
- Scoping semantics verified by resolve tests

---

## Resolve Depth Reference

`VarStatus::Bound(depth~)` stores **relative** depth: `current_depth - bind_depth` (see `resolve.mbt` line 44). This is important for understanding test assertions.

For a single-def Module `Module([("x", Int(1))], Var("x"))` at top level (depth=0):
- Module node_id=0, cur_depth starts at 0
- Int(1) walks at cur_depth=0, node_id=1
- Binding "x" added at depth 0, cur_depth becomes 1
- Body Var("x") walks at cur_depth=1, node_id=2: looks up "x" at bind_depth=0 → `Bound(depth=1-0=1)`

**Result:** For single-def cases, both node IDs AND depth values are identical to the old Let encoding. Only multi-def cases have node ID shifts (Module counts as 1 node instead of n Let nodes), but relative depths stay the same.

---

## Chunk 1: Term Enum + Core Functions (loom submodule)

### Task 1: Replace `Let` with `Module` in enum and `print_term`

**Files:**
- Modify: `examples/lambda/src/ast/ast.mbt`

- [ ] **Step 1: Replace enum variant**

In `examples/lambda/src/ast/ast.mbt`, line 27, replace:

```moonbit
Let(VarName, Term, Term) // non-recursive
```

with:

```moonbit
Module(Array[(VarName, Term)], Term) // (definitions, body)
```

- [ ] **Step 2: Replace `print_term` Let case**

In the same file, line 47, replace:

```moonbit
      Let(x, init, body) => "let " + x + " = " + go(init) + "\n" + go(body)
```

with:

```moonbit
      Module(defs, body) => {
        let parts : Array[String] = []
        for def in defs {
          parts.push("let " + def.0 + " = " + go(def.1))
        }
        parts.push(go(body))
        parts.join("\n")
      }
```

**Note:** Body is always printed (including `Unit` → `"()"`). This keeps `print_term` output identical to the old Let encoding for all inputs including defs-only files like `"let x = 1\n()"`. **Spec divergence:** The design spec (lines 75-78) has a conditional `if body != Unit || defs.is_empty()` that would suppress `()` for defs-only files. We override this because backward compatibility matters more — `print_flat_proj` equivalence tests and `parser_test.mbt` snapshots depend on identical output.

- [ ] **Step 3: Run check (expect errors — downstream sites not yet updated)**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check 2>&1 | head -30
```

Expect: errors from `resolve.mbt`, `dot_node.mbt`, `term_convert.mbt`, test files. That's correct — we fix them in subsequent tasks.

- [ ] **Step 4: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add examples/lambda/src/ast/ast.mbt
git commit -m "refactor(ast): replace Term::Let with Term::Module"
```

---

### Task 2: Simplify SourceFile fold algebra

**Files:**
- Modify: `examples/lambda/src/term_convert.mbt`

- [ ] **Step 1: Replace right-fold with direct Module construction**

In `examples/lambda/src/term_convert.mbt`, lines 27-32, replace:

```moonbit
      let mut result = final_term
      for i = defs.length() - 1; i >= 0; i = i - 1 {
        let (name, init) = defs[i]
        result = @ast.Term::Let(name, init, result)
      }
      result
```

with:

```moonbit
      @ast.Term::Module(defs, final_term)
```

- [ ] **Step 2: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add examples/lambda/src/term_convert.mbt
git commit -m "perf(ast): O(1) Module construction replaces O(n) Let right-fold"
```

---

### Task 3: Update `resolve_walk` for Module

**Files:**
- Modify: `examples/lambda/src/resolve.mbt`

- [ ] **Step 1: Replace Let case with Module case**

In `examples/lambda/src/resolve.mbt`, lines 58-64, replace:

```moonbit
    @ast.Term::Let(x, val, body) => {
      let new_val = resolve_walk(val, env, depth, counter, res)
      let new_env = Map::from_iter(env.iter())
      new_env[x] = depth
      let new_body = resolve_walk(body, new_env, depth + 1, counter, res)
      @ast.Term::Let(x, new_val, new_body)
    }
```

with:

```moonbit
    @ast.Term::Module(defs, body) => {
      let new_defs : Array[(@ast.VarName, @ast.Term)] = []
      let cur_env = Map::from_iter(env.iter())
      let mut cur_depth = depth
      for (name, init) in defs {
        let new_init = resolve_walk(init, cur_env, cur_depth, counter, res)
        cur_env[name] = cur_depth
        cur_depth = cur_depth + 1
        new_defs.push((name, new_init))
      }
      let new_body = resolve_walk(body, cur_env, cur_depth, counter, res)
      @ast.Term::Module(new_defs, new_body)
    }
```

**Semantics preserved:** Each def's initializer sees only previous defs. Each binding increments depth. Body sees all defs. The relative depth (`current - bind`) is identical to nested Lets.

- [ ] **Step 2: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add examples/lambda/src/resolve.mbt
git commit -m "refactor(resolve): update resolve_walk for Term::Module"
```

---

### Task 4: Update DOT renderer

**Files:**
- Modify: `examples/lambda/src/dot_node.mbt`

- [ ] **Step 1: Update label**

In `examples/lambda/src/dot_node.mbt`, line 26, replace:

```moonbit
    @ast.Term::Let(s, _, _) => "Let(" + s + ")"
```

with:

```moonbit
    @ast.Term::Module(defs, _) => {
      let names = defs.map(fn(d) { d.0 })
      "Module(" + names.join(", ") + ")"
    }
```

- [ ] **Step 2: Update build_term_tree**

In the same file, lines 82-86, replace:

```moonbit
    @ast.Term::Let(_, v, body) =>
      [
        build_term_tree(v, counter, resolution~),
        build_term_tree(body, counter, resolution~),
      ]
```

with:

```moonbit
    @ast.Term::Module(defs, body) => {
      let children : Array[TermDotNode] = []
      for (_, init) in defs {
        children.push(build_term_tree(init, counter, resolution~))
      }
      children.push(build_term_tree(body, counter, resolution~))
      children
    }
```

- [ ] **Step 3: Run check**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check 2>&1 | head -20
```

Expect: only test-file errors remain (production code should compile).

- [ ] **Step 4: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add examples/lambda/src/dot_node.mbt
git commit -m "refactor(dot): update DOT renderer for Term::Module"
```

---

## Chunk 2: Test Migration (loom submodule)

### Task 5: Update all test files

**Files:**
- Modify: `examples/lambda/src/parser_properties_test.mbt`
- Modify: `examples/lambda/src/resolve_wbtest.mbt`
- Modify: `examples/lambda/src/views_test.mbt`
- Modify: `examples/lambda/src/ast/debug_wbtest.mbt`
- Modify: `examples/lambda/src/parser_test.mbt` (snapshot updates + test rename)

- [ ] **Step 1: Update `check_well_formed`**

In `examples/lambda/src/parser_properties_test.mbt`, lines 209-212, replace:

```moonbit
    @ast.Term::Let(_, init, body) => {
      check_well_formed(init)
      check_well_formed(body)
    }
```

with:

```moonbit
    @ast.Term::Module(defs, body) => {
      for (_, init) in defs {
        check_well_formed(init)
      }
      check_well_formed(body)
    }
```

- [ ] **Step 2: Update resolve_wbtest.mbt**

In `examples/lambda/src/resolve_wbtest.mbt`:

**Test "resolve: let binding" (line 44):** Replace constructor only. Assertions stay the same — node IDs and relative depths are identical for single-def Module:

```moonbit
  // Pre-order: 0=Module, 1=Int(1), 2=Var(x)  ← same IDs as old Let encoding
  let term = @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Var("x"))
```

Existing assertions `get(1) = None` and `get(2) = Some(Bound(depth=1))` remain correct.

**Test "resolve: var in let initializer is free" (line 54):** Replace constructor only:

```moonbit
  // Pre-order: 0=Module, 1=Var(x) init, 2=Var(x) body  ← same IDs
  let term = @ast.Term::Module([("x", @ast.Term::Var("x"))], @ast.Term::Var("x"))
```

Existing assertions `get(1) = Some(Free)` and `get(2) = Some(Bound(depth=1))` remain correct.

**Test "resolve: nested let shadowing" (lines 91-105):** This is the only test where node IDs change. Old nested Let had 5 nodes (0=Let, 1=Int, 2=Let, 3=Var, 4=Var). New Module has 4 nodes (0=Module, 1=Int, 2=Var, 3=Var).

Replace lines 94-98:
```moonbit
    let term = @ast.Term::Module(
      [("x", @ast.Term::Int(1)), ("x", @ast.Term::Var("x"))],
      @ast.Term::Var("x"),
    )
```

Update comment (line 93) and assertions (lines 101-102):
```moonbit
  // Pre-order: 0=Module, 1=Int(1), 2=Var(x) [2nd init], 3=Var(x) [body]
  ...
  // 2nd def init Var("x"): env has {x:0}, cur_depth=1 → Bound(depth=1-0=1)
  // body Var("x"): env has {x:1} (2nd binding), cur_depth=2 → Bound(depth=2-1=1)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Bound(depth=1))")
```

Relative depths stay `Bound(depth=1)` for both — identical to old test. Only node IDs shifted (3→2, 4→3).

The `print_term` assertion (line 104) stays the same: `"let x = 1\nlet x = x\nx"`.

- [ ] **Step 3: Update views_test.mbt**

In `examples/lambda/src/views_test.mbt`, line 159, replace:
```moonbit
  inspect(term, content="Let(\"x\", Int(1), Var(\"x\"))")
```
with:
```moonbit
  inspect(term, content="Module([(\"x\", Int(1))], Var(\"x\"))")
```

- [ ] **Step 4: Update debug_wbtest.mbt**

In `examples/lambda/src/ast/debug_wbtest.mbt`, lines 15-24, replace:
```moonbit
  let term : Term = Let(
    "f",
    Lam("x", Bop(Plus, Var("x"), Int(1))),
    App(Var("f"), Int(2)),
  )
  inspect(
    @debug.to_string(term),
    content=(
      #|Let("f", Lam("x", Bop(Plus, Var("x"), Int(1))), App(Var("f"), Int(2)))
    ),
  )
```
with:
```moonbit
  let term : Term = Module(
    [("f", Lam("x", Bop(Plus, Var("x"), Int(1))))],
    App(Var("f"), Int(2)),
  )
  inspect(
    @debug.to_string(term),
    content=(
      #|Module([("f", Lam("x", Bop(Plus, Var("x"), Int(1))))], App(Var("f"), Int(2)))
    ),
  )
```

- [ ] **Step 5: Rename test in parser_test.mbt**

In `examples/lambda/src/parser_test.mbt`, line 342, rename:
```
test "parse_term: two defs fold to nested Let with Unit"
```
to:
```
test "parse_term: two defs produce Module with Unit body"
```

`moon test --update` does NOT update test names — this must be done manually.

- [ ] **Step 6: Run tests and update snapshots**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon check
moon test --update
moon test
```

Fix any remaining failures manually. The `parser_test.mbt` `inspect()` content strings auto-update from `Let(...)` to `Module(...)`. Verify that `print_term` output strings (the human-readable format) did NOT change.

- [ ] **Step 7: Update interfaces and format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon info && moon fmt
```

- [ ] **Step 8: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
git add -u examples/lambda/
git commit -m "test: migrate all tests to Term::Module"
```

---

## Chunk 3: Parent Repo (crdt monorepo)

### Task 6: Update loom submodule pointer

- [ ] **Step 1: Update submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
git add loom
git commit -m "chore: update loom submodule (Term::Module)"
```

---

### Task 7: Update projection layer

**Files:**
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/proj_node.mbt`
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/flat_proj.mbt`
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/reconcile_ast.mbt`
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/tree_editor.mbt`
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/tree_lens.mbt`
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/proj_node_test.mbt`
- Modify: `/home/antisatori/ghq/github.com/dowdiness/crdt/projection/flat_proj_wbtest.mbt`

#### Structural change: nested binary tree → flat array

The key structural change in the projection layer: ProjNode children layout changes from a nested binary tree of `[init, Let-child]` pairs to a flat array `[init0, init1, ..., body]`.

**Before (nested Let):**
```
ProjNode(Let("x", _, Let("y", _, _)))
  children: [init_x, ProjNode(Let("y", _, _))
                        children: [init_y, body]]
```

**After (flat Module):**
```
ProjNode(Module([("x", _), ("y", _)], _))
  children: [init_x, init_y, body]
```

This affects: `to_proj_node` (both in `proj_node.mbt` and `flat_proj.mbt`), `from_proj_node`, `rebuild_kind`, `same_kind_tag`, `reconcile_ast`, and `children.length()` in tests.

- [ ] **Step 1: Update `proj_node.mbt` — to_proj_node**

Lines 238-246: Replace the right-fold loop that builds nested `Let` ProjNodes with direct Module construction.

Replace:
```moonbit
    for i = defs.length() - 1; i >= 0; i = i - 1 {
      let (name, init, def_start) = defs[i]
      result = ProjNode::new(
        Let(name, init.kind, result.kind),
        def_start,
        result.end,
        next_proj_node_id(counter),
        [init, result],
      )
    }
```

With:
```moonbit
    if defs.length() > 0 {
      // Build flat children: [init0, init1, ..., body]
      let children : Array[ProjNode] = defs.map(fn(d) { d.1 })
      children.push(result)
      // Build defs array for Module term
      let term_defs : Array[(@ast.VarName, @ast.Term)] = defs.map(fn(d) { (d.0, d.1.kind) })
      result = ProjNode::new(
        Module(term_defs, result.kind),
        defs[0].2,
        result.end,
        next_proj_node_id(counter),
        children,
      )
    }
```

**Important:** Only wrap in Module when defs is non-empty. For bare expressions and empty documents, `result` is returned as-is (e.g., `Int(42)`, `Unit`). This matches existing test expectations (`proj_node_test.mbt` lines 11, 43).

- [ ] **Step 2: Update `proj_node.mbt` — rebuild_kind**

Lines 282-287: Replace `Let(name, _, _)` with `Module(_, _)`. Module's children are `[init0, init1, ..., body]`. Rebuild by pairing original def names with new children's kinds:

```moonbit
    Module(old_defs, _) =>
      if children.length() >= 1 {
        let new_defs : Array[(@ast.VarName, @ast.Term)] = []
        for i = 0; i < children.length() - 1; i = i + 1 {
          let name = if i < old_defs.length() { old_defs[i].0 } else { "_" }
          new_defs.push((name, children[i].kind))
        }
        Module(new_defs, children[children.length() - 1].kind)
      } else {
        shape
      }
```

- [ ] **Step 3: Update `proj_node.mbt` — same_kind_tag**

Line 303: Replace `(Let(_, _, _), Let(_, _, _))` with `(Module(_, _), Module(_, _))`.

- [ ] **Step 4: Update `flat_proj.mbt` — FlatProj::to_proj_node**

Lines 119-144: This function builds a nested Let spine from FlatProj. Replace with Module construction. The function should produce a single Module ProjNode with flat children:

```moonbit
pub fn FlatProj::to_proj_node(self : FlatProj, counter : Ref[Int]) -> ProjNode {
  let body = match self.final_expr {
    Some(expr) => expr
    None => {
      let end_pos = if self.defs.length() > 0 {
        self.defs[self.defs.length() - 1].1.end
      } else {
        0
      }
      ProjNode::new(Unit, end_pos, end_pos, next_proj_node_id(counter), [])
    }
  }
  if self.defs.is_empty() {
    return body
  }
  // Build flat children and term defs
  let children : Array[ProjNode] = self.defs.map(fn(d) { d.1 })
  children.push(body)
  let term_defs : Array[(@ast.VarName, @ast.Term)] = self.defs.map(fn(d) { (d.0, d.1.kind) })
  let start = self.defs[0].2
  // Module gets a fresh ID; init children retain their stored identities
  ProjNode::new(
    Module(term_defs, body.kind),
    start,
    body.end,
    next_proj_node_id(counter),
    children,
  )
}
```

**Note:** When there are no defs, return the body directly (not wrapped in Module). When there are defs, the first def's stored NodeId is used as the Module node's ID.

- [ ] **Step 5: Update `flat_proj.mbt` — FlatProj::from_proj_node**

Lines 149-171: Replace the Let spine extraction loop with Module matching:

```moonbit
pub fn FlatProj::from_proj_node(root : ProjNode) -> FlatProj {
  match root.kind {
    Module(term_defs, _) => {
      let defs : Array[(String, ProjNode, Int, NodeId)] = []
      // Children are [init0, init1, ..., body]
      for i = 0; i < term_defs.length(); i = i + 1 {
        if i < root.children.length() - 1 {
          let init_child = root.children[i]
          // Use each init child's node_id as the def's identity.
          // In the old Let encoding, each Let node had its own ID.
          // With Module, we use the init child's ID as a stable proxy.
          defs.push((term_defs[i].0, init_child, init_child.start, NodeId(init_child.node_id)))
        }
      }
      let body_child = root.children[root.children.length() - 1]
      let final_expr = match body_child.kind {
        Unit => None
        _ => Some(body_child)
      }
      { defs, final_expr }
    }
    Unit => { defs: [], final_expr: None }
    _ => { defs: [], final_expr: Some(root) }
  }
}
```

**NodeId strategy:** Each def uses its init child's `node_id` as its identity. This is stable (assigned during `to_proj_node`) and unique per def. `reconcile_flat_proj` relies on distinct per-def NodeIds for LCS matching — using init child IDs satisfies this. The `FlatProj::to_proj_node` function must be updated correspondingly — when building the Module ProjNode from stored defs, the Module node gets a fresh ID from the counter, while each init child retains its stored identity.

- [ ] **Step 6: Update `reconcile_ast.mbt`**

Lines 92-105: Replace `(Let(_, _, _), Let(_, _, _))` with `(Module(_, _), Module(_, _))`. The reconciliation logic stays the same — match kind tags and reconcile children.

- [ ] **Step 7: Update `tree_editor.mbt`**

Line 61: Replace `Let(String)` variant in `InteractiveNodeShape` with `Module`.

Line 117: Replace `Let(name, _, _) => Let(name)` with `Module(_, _) => Module`.

Line 552: Replace `Let(name, _, _) => "let " + name` with `Module(defs, _) => "module"` (or generate a label listing def names).

- [ ] **Step 8: Update `tree_lens.mbt`**

Line 338: Replace `@ast.Term::Let(_, _, _) => "let x = 0\nx"` with `@ast.Term::Module(_, _) => "let x = 0\nx"` (placeholder text stays the same).

- [ ] **Step 9: Run check and fix compilation errors**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon check 2>&1 | head -40
```

Fix any remaining exhaustive-match or reference errors.

- [ ] **Step 10: Update tests manually**

Tests that need manual attention (not auto-fixable by `moon test --update`):

**`proj_node_test.mbt`:**
- Line 19: `inspect(proj.children.length(), content="2")` → stays "2" for single-def (1 init + 1 body)
- Lines 23-29: Multi-def test. `proj.kind` changes from nested `Let(...)` to `Module(...)`. `proj.children.length()` changes from "2" (init + nested-Let-child) to "3" (init0, init1, body) for 2 defs. Check and update these manually.

**`flat_proj_wbtest.mbt`:**
- Line 156: `print_flat_proj(flat) == @ast.print_term(nested.kind)` equivalence — should still hold since `print_term` output is identical.
- Lines 167-177: `to_proj_node` snapshot changes from nested `Let(...)` to `Module(...)`. Auto-update handles content strings.
- Line 184: `proj.node_id == def_id.0` — this test checks that the outer ProjNode's ID matches the def's stored NodeId. With Module, `from_proj_node` now stores init child IDs as def IDs, while `to_proj_node` assigns a fresh ID for the Module node. This test will need updating: either check that `proj.children[0].node_id == def_id.0` (init child ID matches), or rethink the assertion.
- Lines 188-194: `from_proj_node` test "extracts Let spine" — rename to "extracts Module defs", verify `defs.length()` assertions.
- Lines 204-218, 221-230: Roundtrip tests comparing `print_term` output — should pass if `print_term` output is identical.
- Lines 289-296: "defs-only roundtrips through tree edit" — `print_flat_proj` explicitly prints "()" for None `final_expr`; `print_term` on `Module([defs], Unit)` also prints "()" (body always printed). Equivalence holds.

- [ ] **Step 11: Run tests and update snapshots**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon test --update
moon test
```

- [ ] **Step 12: Format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon info && moon fmt
```

- [ ] **Step 13: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
git add -u projection/
git commit -m "fix(projection): update projection layer for Term::Module"
```

---

## Chunk 4: Verification

### Task 8: Full regression pass

- [ ] **Step 1: Run all loom tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda && moon check && moon test
```

All tests must pass.

- [ ] **Step 2: Run all crdt tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon check && moon test
```

All tests must pass.

- [ ] **Step 3: Verify no Let remnants**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
rg 'Term::Let|Let\(VarName' examples/lambda/src/ --type-add 'mbt:*.mbt' --type mbt

cd /home/antisatori/ghq/github.com/dowdiness/crdt
rg 'Term::Let' projection/ --type-add 'mbt:*.mbt' --type mbt
```

Expected: no matches in production code. Test names and snapshot strings should all reference Module, not Let.

- [ ] **Step 4: Verify print_term output unchanged**

The `print_term` tests in `parser_test.mbt` verify that human-readable output is identical. Confirm no test that checks `print_term` output has changed its expected string (the `#|` heredoc content should be identical before and after).

- [ ] **Step 5: Run benchmarks**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon bench --release 2>&1 | grep -E "let-chain|source"
```

Record results for comparison.

---

## Pre-order ID Reference

Pre-order ID comparison for `let x = 1\nlet y = 2\nx + y`:

```text
Before (nested Let):  0=Let(x), 1=Int(1), 2=Let(y), 3=Int(2), 4=Bop, 5=Var(x), 6=Var(y)
After  (Module):      0=Module, 1=Int(1), 2=Int(2), 3=Bop, 4=Var(x), 5=Var(y)
```

Module counts as 1 node instead of n Let nodes. For n defs, the total node count decreases by n-1. All IDs after the first def shift left. Relative depths in `Bound(depth~)` are unchanged because the depth arithmetic is preserved.
