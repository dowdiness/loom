# Egraph Lambda Evaluator Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `LambdaLang` with `LMinus`, `LIf`, `LBool`, `LIsZero`, `LSubst` and implement `subst_and_eval_analysis()` — an equality-saturation-based evaluator that performs beta reduction, structural substitution, and constant folding via `AnalyzedEGraph::rebuild()`.

**Architecture:** Two-file approach: (1) extend `LambdaLang` in `lambda_opt_wbtest.mbt` with 5 new variants and update all 6 `ENode`/`ENodeRepr` impls; (2) new `lambda_eval_wbtest.mbt` defines `EvalState = { fv: HashSet[String], val: ValLit? }` combining free-variable tracking and constant folding. All reduction fires through the `modify` hook during `eg.rebuild()`. No `Runner` or explicit rewrite passes needed.

**Tech Stack:** MoonBit, `egraph` package (whitebox test access to `priv struct`s), `@hashset.HashSet[String]`.

**Reference:** Design spec at `docs/plans/2026-03-28-egglog-egraph-lambda-design.md` Part 2.

---

## File Map

| File | Role |
|------|------|
| Modify: `egraph/lambda_opt_wbtest.mbt` | Add 5 new `LambdaLang` variants; update all 6 `ENode`/`ENodeRepr` impl methods |
| Create: `egraph/lambda_eval_wbtest.mbt` | `ValLit` enum, `EvalState` struct, `fv_union` helper, `apply_subst` helper, `subst_and_eval_analysis()`, tests |

---

### Task 1: Extend LambdaLang with New Variants

**Files:**
- Modify: `egraph/lambda_opt_wbtest.mbt`

- [ ] **Step 1: Write failing test for new variants**

Add this test at the end of `egraph/lambda_opt_wbtest.mbt`:

```moonbit
///|
test "lambda: new variant ENodeRepr round-trip" {
  let cases : Array[(LambdaLang, String, String?, Array[Id])] = [
    (LBool(true), "Bool", Some("true"), []),
    (LBool(false), "Bool", Some("false"), []),
    (LMinus(Id(0), Id(1)), "Minus", None, [Id(0), Id(1)]),
    (LIf(Id(0), Id(1), Id(2)), "If", None, [Id(0), Id(1), Id(2)]),
    (LIsZero(Id(0)), "IsZero", None, [Id(0)]),
    (LSubst("x", Id(0), Id(1)), "Subst", Some("x"), [Id(0), Id(1)]),
  ]
  for c in cases {
    let (expected, tag, payload, children) = c
    let result = LambdaLang::from_op(tag, payload, children)
    assert_eq(result, Some(expected))
  }
}
```

- [ ] **Step 2: Run to verify it fails (compilation error — variants don't exist yet)**

```bash
cd egraph && moon check 2>&1 | head -20
```

Expected: compilation errors about unknown constructors `LBool`, `LMinus`, `LIf`, `LIsZero`, `LSubst`.

- [ ] **Step 3: Add new variants to the enum**

Replace the existing `LambdaLang` enum declaration at the top of `egraph/lambda_opt_wbtest.mbt`:

```moonbit
///|
priv enum LambdaLang {
  LNum(Int)
  LVar(String)
  LAdd(Id, Id)
  LMul(Id, Id)
  LLam(String, Id)
  LApp(Id, Id)
  LLet(String, Id, Id)
  LMinus(Id, Id)         // subtraction
  LIf(Id, Id, Id)        // if-then-else
  LBool(Bool)            // boolean literal
  LIsZero(Id)            // Int → Bool
  LSubst(String, Id, Id) // explicit substitution: LSubst(var, value, expr)
} derive(Eq, Hash, Compare, Show, Debug)
```

- [ ] **Step 4: Update `ENode::arity`**

Replace the full `arity` impl:

```moonbit
///|
impl ENode for LambdaLang with arity(self) {
  match self {
    LNum(_) | LVar(_) | LBool(_) => 0
    LLam(_, _) | LIsZero(_) => 1
    LAdd(_, _) | LMul(_, _) | LApp(_, _) | LMinus(_, _) | LSubst(_, _, _) => 2
    LLet(_, _, _) => 2
    LIf(_, _, _) => 3
  }
}
```

- [ ] **Step 5: Update `ENode::child`**

Replace the full `child` impl:

```moonbit
///|
impl ENode for LambdaLang with child(self, i) {
  match self {
    LAdd(a, b) | LMul(a, b) | LApp(a, b) | LMinus(a, b) =>
      if i == 0 { a } else { b }
    LLam(_, body) | LIsZero(body) => body
    LLet(_, value, body) | LSubst(_, value, body) =>
      if i == 0 { value } else { body }
    LIf(c, t, fb) =>
      if i == 0 { c } else if i == 1 { t } else { fb }
    _ => abort("no children")
  }
}
```

- [ ] **Step 6: Update `ENode::map_children`**

Replace the full `map_children` impl:

```moonbit
///|
impl ENode for LambdaLang with map_children(self, f) {
  match self {
    LNum(_) | LVar(_) | LBool(_) => self
    LAdd(a, b) => LAdd(f(a), f(b))
    LMul(a, b) => LMul(f(a), f(b))
    LApp(a, b) => LApp(f(a), f(b))
    LMinus(a, b) => LMinus(f(a), f(b))
    LLam(name, body) => LLam(name, f(body))
    LIsZero(inner) => LIsZero(f(inner))
    LLet(name, value, body) => LLet(name, f(value), f(body))
    LSubst(name, value, expr) => LSubst(name, f(value), f(expr))
    LIf(c, t, fb) => LIf(f(c), f(t), f(fb))
  }
}
```

- [ ] **Step 7: Update `ENodeRepr::op_tag`**

Replace the full `op_tag` impl:

```moonbit
///|
impl ENodeRepr for LambdaLang with op_tag(self) {
  match self {
    LNum(_) => "Num"
    LVar(_) => "Var"
    LAdd(_, _) => "Add"
    LMul(_, _) => "Mul"
    LLam(_, _) => "Lam"
    LApp(_, _) => "App"
    LLet(_, _, _) => "Let"
    LMinus(_, _) => "Minus"
    LIf(_, _, _) => "If"
    LBool(_) => "Bool"
    LIsZero(_) => "IsZero"
    LSubst(_, _, _) => "Subst"
  }
}
```

- [ ] **Step 8: Update `ENodeRepr::payload`**

Replace the full `payload` impl:

```moonbit
///|
impl ENodeRepr for LambdaLang with payload(self) {
  match self {
    LNum(n) => Some(n.to_string())
    LVar(name) => Some(name)
    LLam(name, _) => Some(name)
    LLet(name, _, _) => Some(name)
    LBool(b) => Some(b.to_string())    // "true" or "false"
    LSubst(name, _, _) => Some(name)
    _ => None
  }
}
```

- [ ] **Step 9: Update `ENodeRepr::from_op`**

Replace the full `from_op` impl:

```moonbit
///|
impl ENodeRepr for LambdaLang with from_op(tag, payload, children) {
  match (tag, payload, children.length()) {
    ("Num", Some(s), 0) => Some(LNum(@strconv.parse_int(s))) catch { _ => None }
    ("Var", Some(s), 0) => Some(LVar(s))
    ("Add", None, 2) => Some(LAdd(children[0], children[1]))
    ("Mul", None, 2) => Some(LMul(children[0], children[1]))
    ("App", None, 2) => Some(LApp(children[0], children[1]))
    ("Lam", Some(name), 1) => Some(LLam(name, children[0]))
    ("Let", Some(name), 2) => Some(LLet(name, children[0], children[1]))
    ("Minus", None, 2) => Some(LMinus(children[0], children[1]))
    ("If", None, 3) => Some(LIf(children[0], children[1], children[2]))
    ("Bool", Some(s), 0) =>
      match s {
        "true" => Some(LBool(true))
        "false" => Some(LBool(false))
        _ => None
      }
    ("IsZero", None, 1) => Some(LIsZero(children[0]))
    ("Subst", Some(name), 2) => Some(LSubst(name, children[0], children[1]))
    _ => None
  }
}
```

- [ ] **Step 10: Run all tests**

```bash
cd egraph && moon test
```

Expected: all existing tests pass plus the new round-trip test (`lambda: new variant ENodeRepr round-trip`).

- [ ] **Step 11: Commit**

```bash
git add egraph/lambda_opt_wbtest.mbt
git commit -m "feat(egraph/lambda): add LMinus, LIf, LBool, LIsZero, LSubst variants"
```

---

### Task 2: Create lambda_eval_wbtest.mbt with EvalState

**Files:**
- Create: `egraph/lambda_eval_wbtest.mbt`

- [ ] **Step 1: Create the file**

```moonbit
///|
/// Values the constant-folding lattice can represent.
enum ValLit {
  VInt(Int)
  VBool(Bool)
} derive(Eq, Show)

///|
/// Combined analysis data per e-class.
///
/// `fv`: free variables (sound over-approximation — set-union on merge).
/// `val`: known constant value if this e-class reduces to a literal.
struct EvalState {
  fv : @hashset.HashSet[String]
  val : ValLit?
}

///|
/// Copy all elements of `src` into `dst`.
fn fv_union(
  dst : @hashset.HashSet[String],
  src : @hashset.HashSet[String],
) -> Unit {
  for x in src {
    dst.add(x)
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd egraph && moon check
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add egraph/lambda_eval_wbtest.mbt
git commit -m "feat(egraph/lambda): add EvalState, ValLit, fv_union helpers"
```

---

### Task 3: subst_and_eval_analysis() — make + merge

**Files:**
- Modify: `egraph/lambda_eval_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Add to `egraph/lambda_eval_wbtest.mbt`:

```moonbit
///|
test "eval: make — FV for new variants" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x_id = eg.add(LVar("x"))
  let y_id = eg.add(LVar("y"))
  let num5 = eg.add(LNum(5))
  // LBool has no FV
  let btrue = eg.add(LBool(true))
  assert_true(eg.get_data(btrue).fv.is_empty())
  // LIsZero inherits FV from inner
  let iszero_x = eg.add(LIsZero(x_id))
  assert_true(eg.get_data(iszero_x).fv.contains("x"))
  // LMinus inherits FV from both args
  let minus_xy = eg.add(LMinus(x_id, y_id))
  assert_true(eg.get_data(minus_xy).fv.contains("x"))
  assert_true(eg.get_data(minus_xy).fv.contains("y"))
  // LIf inherits FV from all three
  let if_expr = eg.add(LIf(btrue, x_id, y_id))
  assert_true(eg.get_data(if_expr).fv.contains("x"))
  assert_true(eg.get_data(if_expr).fv.contains("y"))
  // LSubst("x", num5, x_id): (FV(LVar("x")) \ {"x"}) ∪ FV(num5) = {} ∪ {} = {}
  let subst = eg.add(LSubst("x", num5, x_id))
  assert_true(eg.get_data(subst).fv.is_empty())
}

///|
test "eval: make — constant values for new literals" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let btrue = eg.add(LBool(true))
  assert_eq(eg.get_data(btrue).val, Some(VBool(true)))
  let bfalse = eg.add(LBool(false))
  assert_eq(eg.get_data(bfalse).val, Some(VBool(false)))
  // IsZero(0) → VBool(true)
  let zero = eg.add(LNum(0))
  let iszero_0 = eg.add(LIsZero(zero))
  assert_eq(eg.get_data(iszero_0).val, Some(VBool(true)))
  // IsZero(1) → VBool(false)
  let one = eg.add(LNum(1))
  let iszero_1 = eg.add(LIsZero(one))
  assert_eq(eg.get_data(iszero_1).val, Some(VBool(false)))
  // LMinus(5, 3) → VInt(2)
  let five = eg.add(LNum(5))
  let three = eg.add(LNum(3))
  let minus_53 = eg.add(LMinus(five, three))
  assert_eq(eg.get_data(minus_53).val, Some(VInt(2)))
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
cd egraph && moon test 2>&1 | grep "eval:" | head -10
```

Expected: errors about `subst_and_eval_analysis` not found.

- [ ] **Step 3: Implement subst_and_eval_analysis() with make + merge**

Add to `egraph/lambda_eval_wbtest.mbt` (place this BEFORE the tests):

```moonbit
///|
/// Combined analysis: free-variable tracking + constant folding.
///
/// `make`   — compute EvalState bottom-up from child data.
/// `merge`  — union FV sets (sound over-approx); keep first-non-None val.
/// `modify` — no-op placeholder; implemented in Task 4.
fn subst_and_eval_analysis() -> Analysis[LambdaLang, EvalState] {
  {
    make: fn(node, get_data) {
      let fv : @hashset.HashSet[String] = @hashset.new()
      let mut val : ValLit? = None
      match node {
        LNum(n) => val = Some(VInt(n))
        LBool(b) => val = Some(VBool(b))
        LVar(x) => fv.add(x)
        LAdd(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(VInt(x)), Some(VInt(y))) => val = Some(VInt(x + y))
            _ => ()
          }
        }
        LMinus(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(VInt(x)), Some(VInt(y))) => val = Some(VInt(x - y))
            _ => ()
          }
        }
        LMul(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(VInt(x)), Some(VInt(y))) => val = Some(VInt(x * y))
            _ => ()
          }
        }
        LIsZero(inner) => {
          let d = get_data(inner)
          fv_union(fv, d.fv)
          match d.val {
            Some(VInt(n)) => val = Some(VBool(n == 0))
            _ => ()
          }
        }
        LIf(c, t, fb) => {
          let dc = get_data(c)
          let dt = get_data(t)
          let df = get_data(fb)
          fv_union(fv, dc.fv)
          fv_union(fv, dt.fv)
          fv_union(fv, df.fv)
          // Propagate value when condition is statically known
          match dc.val {
            Some(VBool(true)) => val = dt.val
            Some(VBool(false)) => val = df.val
            _ => ()
          }
        }
        LApp(f, a) => {
          fv_union(fv, get_data(f).fv)
          fv_union(fv, get_data(a).fv)
        }
        LLam(x, body) => {
          fv_union(fv, get_data(body).fv)
          fv.remove(x)  // x is bound — not free in the lambda
        }
        LLet(x, v, body) => {
          // FV(LLet(x, v, body)) = FV(v) ∪ (FV(body) \ {x})
          // x may appear free in v (e.g. `let x = x + 1 in ...`),
          // so only remove x from body's contribution, not from v's.
          fv_union(fv, get_data(v).fv)
          for y in get_data(body).fv {
            if y != x {
              fv.add(y)
            }
          }
        }
        LSubst(x, v, e) => {
          // FV(LSubst(x, v, e)) = (FV(e) \ {x}) ∪ FV(v)
          fv_union(fv, get_data(e).fv)
          fv.remove(x)
          fv_union(fv, get_data(v).fv)
        }
      }
      { fv, val }
    },
    merge: fn(a, b) {
      // Union FV sets — sound over-approximation
      let fv : @hashset.HashSet[String] = @hashset.new()
      for x in a.fv {
        fv.add(x)
      }
      for x in b.fv {
        fv.add(x)
      }
      // Commutative merge: if both have a value they must agree (same e-class
      // should never hold two different constants); if only one has a value,
      // keep it; if neither, return None.
      let val = match (a.val, b.val) {
        (Some(v1), Some(v2)) => if v1 == v2 { Some(v1) } else { None }
        (Some(v), None) | (None, Some(v)) => Some(v)
        _ => None
      }
      { fv, val }
    },
    modify: fn(_eg, _id) { () },
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd egraph && moon test -f lambda_eval_wbtest.mbt
```

Expected: both new tests pass.

- [ ] **Step 5: Commit**

```bash
git add egraph/lambda_eval_wbtest.mbt
git commit -m "feat(egraph/lambda): subst_and_eval_analysis make+merge with FV and constant folding"
```

---

### Task 4: modify Hook — Constant Folding + Beta Reduction + LSubst Base Cases

**Files:**
- Modify: `egraph/lambda_eval_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Add to `egraph/lambda_eval_wbtest.mbt`:

```moonbit
///|
test "eval: constant folding — 2 + 3 = 5 after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(two, three))
  eg.rebuild()
  let five = eg.add(LNum(5))
  assert_eq(eg.find(sum), eg.find(five))
}

///|
test "eval: constant folding — 5 - 3 = 2 after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let five = eg.add(LNum(5))
  let three = eg.add(LNum(3))
  let diff = eg.add(LMinus(five, three))
  eg.rebuild()
  let two = eg.add(LNum(2))
  assert_eq(eg.find(diff), eg.find(two))
}

///|
test "eval: IsZero(0) folds to LBool(true) after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let zero = eg.add(LNum(0))
  let iszero = eg.add(LIsZero(zero))
  eg.rebuild()
  let btrue = eg.add(LBool(true))
  assert_eq(eg.find(iszero), eg.find(btrue))
}

///|
test "eval: if IsZero(0) then 1 else 2 = 1 after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let zero = eg.add(LNum(0))
  let iszero = eg.add(LIsZero(zero))
  let one = eg.add(LNum(1))
  let two = eg.add(LNum(2))
  let if_expr = eg.add(LIf(iszero, one, two))
  eg.rebuild()
  assert_eq(eg.find(if_expr), eg.find(one))
}

///|
test "eval: beta reduction — (λx. x + 1) 5 = 6" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  let one = eg.add(LNum(1))
  let body = eg.add(LAdd(x, one))
  let lam = eg.add(LLam("x", body))
  let five = eg.add(LNum(5))
  let app = eg.add(LApp(lam, five))
  eg.rebuild()
  let six = eg.add(LNum(6))
  assert_eq(eg.find(app), eg.find(six))
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
cd egraph && moon test 2>&1 | grep FAILED | head -10
```

Expected: 5 failing tests (modify is currently a no-op).

- [ ] **Step 3: Add `apply_subst` helper (base cases only)**

Add to `egraph/lambda_eval_wbtest.mbt`, BEFORE `subst_and_eval_analysis()`:

```moonbit
///|
/// Reduce `LSubst(x, v_id, e_node)` by dispatching on the structure of `e_node`.
/// Unions `subst_class` with the reduced form when a rule applies.
///
/// LLam and LLet cases with capture guard are added in Task 5.
fn apply_subst(
  eg : AnalyzedEGraph[LambdaLang, EvalState],
  subst_class : Id,
  x : String,
  v_id : Id,
  e_node : LambdaLang,
) -> Unit {
  match e_node {
    LVar(y) =>
      if x == y {
        // x[x := v] = v
        eg.union(subst_class, v_id) |> ignore
      } else {
        // y[x := v] = y  (x ≠ y)
        eg.union(subst_class, eg.add(LVar(y))) |> ignore
      }
    LNum(n) =>
      // n[x := v] = n
      eg.union(subst_class, eg.add(LNum(n))) |> ignore
    LBool(b) =>
      // b[x := v] = b
      eg.union(subst_class, eg.add(LBool(b))) |> ignore
    LAdd(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      eg.union(subst_class, eg.add(LAdd(sa, sb))) |> ignore
    }
    LMinus(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      eg.union(subst_class, eg.add(LMinus(sa, sb))) |> ignore
    }
    LMul(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      eg.union(subst_class, eg.add(LMul(sa, sb))) |> ignore
    }
    LApp(f, a) => {
      let sf = eg.add(LSubst(x, v_id, f))
      let sa = eg.add(LSubst(x, v_id, a))
      eg.union(subst_class, eg.add(LApp(sf, sa))) |> ignore
    }
    LIsZero(inner) =>
      eg.union(
        subst_class,
        eg.add(LIsZero(eg.add(LSubst(x, v_id, inner)))),
      ) |> ignore
    LIf(c, t, fb) => {
      let sc = eg.add(LSubst(x, v_id, c))
      let st = eg.add(LSubst(x, v_id, t))
      let sf = eg.add(LSubst(x, v_id, fb))
      eg.union(subst_class, eg.add(LIf(sc, st, sf))) |> ignore
    }
    // LLam and LLet with capture guard are added in Task 5
    _ => ()
  }
}
```

- [ ] **Step 4: Replace the no-op modify with the full hook**

In `subst_and_eval_analysis()`, replace `modify: fn(_eg, _id) { () },` with:

```moonbit
    modify: fn(eg, id) {
      // Phase 1: constant folding — if we know the value, add the literal and union
      match eg.get_data(id).val {
        Some(VInt(n)) => {
          let num_id = eg.add(LNum(n))
          eg.union(id, num_id) |> ignore
        }
        Some(VBool(b)) => {
          let bool_id = eg.add(LBool(b))
          eg.union(id, bool_id) |> ignore
        }
        None => ()
      }
      // Phase 2: structural rules — inspect nodes in this e-class
      let class_id = eg.find(id)
      match eg.egraph.classes.get(class_id) {
        None => ()
        Some(class) => {
          for node in class.nodes {
            match node {
              // Beta reduction: (λx. body) arg → LSubst(x, arg, body)
              LApp(lam_id, arg_id) => {
                let lam_canonical = eg.find(lam_id)
                match eg.egraph.classes.get(lam_canonical) {
                  None => ()
                  Some(lam_class) => {
                    for lam_node in lam_class.nodes {
                      match lam_node {
                        LLam(x, body_id) => {
                          let subst_id = eg.add(LSubst(x, arg_id, body_id))
                          eg.union(class_id, subst_id) |> ignore
                        }
                        _ => ()
                      }
                    }
                  }
                }
              }
              // Structural substitution — dispatch on e-node inside e_id's class
              LSubst(x, v_id, e_id) => {
                let e_canonical = eg.find(e_id)
                match eg.egraph.classes.get(e_canonical) {
                  None => ()
                  Some(e_class) => {
                    for e_node in e_class.nodes {
                      apply_subst(eg, class_id, x, v_id, e_node)
                    }
                  }
                }
              }
              // LLet inlining: let x = v in body  ≡  LSubst(x, v, body)
              LLet(x, v_id, body_id) => {
                let subst_id = eg.add(LSubst(x, v_id, body_id))
                eg.union(class_id, subst_id) |> ignore
              }
              // If-reduction: union with the live branch when condition is known.
              // This fires even when the branch itself is symbolic (not a constant),
              // so `if true then (x + 1) else 2` correctly reduces to `x + 1`.
              LIf(cond_id, then_id, else_id) => {
                match eg.get_data(eg.find(cond_id)).val {
                  Some(VBool(true)) =>
                    eg.union(class_id, then_id) |> ignore
                  Some(VBool(false)) =>
                    eg.union(class_id, else_id) |> ignore
                  _ => ()
                }
              }
              _ => ()
            }
          }
        }
      }
    },
```

- [ ] **Step 5: Run tests**

```bash
cd egraph && moon test -f lambda_eval_wbtest.mbt
```

Expected: all 7 tests in the file pass (including the 5 new ones).

Tracing `(λx. x + 1) 5` to verify:
- `LApp(lam, 5)` → beta: adds `LSubst("x", 5, LAdd(x, 1))`
- `LSubst("x", 5, LAdd(x, 1))` → apply_subst(LAdd): adds `LAdd(LSubst("x",5,x), LSubst("x",5,1))`
- `LSubst("x", 5, LVar("x"))` → apply_subst(LVar("x")): union with `5`
- `LSubst("x", 5, LNum(1))` → apply_subst(LNum(1)): union with `LNum(1)`
- `LAdd(5, 1)` → make: `VInt(6)` → modify: add `LNum(6)`, union ✓

- [ ] **Step 6: Commit**

```bash
git add egraph/lambda_eval_wbtest.mbt
git commit -m "feat(egraph/lambda): modify hook — constant fold, beta, LSubst base cases"
```

---

### Task 5: modify Hook — LLam and LLet Cases with Capture Guard

**Files:**
- Modify: `egraph/lambda_eval_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Add to `egraph/lambda_eval_wbtest.mbt`:

```moonbit
///|
test "eval: (λx. λy. x + y) 2 3 = 5 (two beta steps)" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  let y = eg.add(LVar("y"))
  let add_xy = eg.add(LAdd(x, y))
  let inner_lam = eg.add(LLam("y", add_xy))    // λy. x + y
  let outer_lam = eg.add(LLam("x", inner_lam)) // λx. λy. x + y
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let app1 = eg.add(LApp(outer_lam, two))      // (λx. λy. x + y) 2
  let app2 = eg.add(LApp(app1, three))         // ((λx. λy. x + y) 2) 3
  eg.rebuild()
  let five = eg.add(LNum(5))
  assert_eq(eg.find(app2), eg.find(five))
}

///|
test "eval: let x = 2 in x + x = 4" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let two = eg.add(LNum(2))
  let x = eg.add(LVar("x"))
  let body = eg.add(LAdd(x, x))
  let let_expr = eg.add(LLet("x", two, body))
  eg.rebuild()
  let four = eg.add(LNum(4))
  assert_eq(eg.find(let_expr), eg.find(four))
}

///|
test "eval: (λy. λx. y) x leaves unreduced LSubst in extracted term (capture)" {
  // (λy. λx. y) x  where x is free
  // Beta: LSubst("y", x_free, LLam("x", y_var))
  // Binder "x" in λx would be captured by free "x" in arg → no action
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x_free = eg.add(LVar("x"))
  let y_var = eg.add(LVar("y"))
  let inner_lam = eg.add(LLam("x", y_var))    // λx. y
  let outer_lam = eg.add(LLam("y", inner_lam)) // λy. λx. y
  let app = eg.add(LApp(outer_lam, x_free))    // (λy. λx. y) x
  eg.rebuild()
  let (_, expr) = eg.extract(app, ast_size())
  // Walk ALL nodes in the RecExpr (root alone would miss nested LSubst in a body)
  let mut has_subst = false
  for n in expr.nodes {
    match n {
      LSubst(_, _, _) => has_subst = true
      _ => ()
    }
  }
  assert_true(has_subst)
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd egraph && moon test 2>&1 | grep FAILED | head -10
```

Expected: `two beta steps` and `let x = 2` fail (need LLam/LLet cases); capture test may vary.

- [ ] **Step 3: Add LLam and LLet cases to `apply_subst`**

In `apply_subst`, replace the `// LLam and LLet with capture guard are added in Task 5` comment and the `_ => ()` at the end with:

```moonbit
    LLam(y, body_id) =>
      if x == y {
        // x is shadowed by the binder — substitution does not enter the body
        eg.union(subst_class, eg.add(LLam(y, body_id))) |> ignore
      } else if not(eg.get_data(v_id).fv.contains(y)) {
        // Safe descent: y ∉ FV(v), so substitution won't capture y
        let new_body = eg.add(LSubst(x, v_id, body_id))
        eg.union(subst_class, eg.add(LLam(y, new_body))) |> ignore
      }
      // CAPTURE LIMITATION: LSubst(x, v, LLam(y, body)) where x ≠ y and y ∈ FV(v).
      // Substitution does not fire — the LSubst node remains unreduced in the
      // extracted term. Walk all RecExpr nodes (not just root()) to detect it.
      // Resolution: use de Bruijn indices (Approach B) to eliminate capture entirely.
    LLet(y, val_id, body_id) =>
      if x == y {
        // x is shadowed in the body — substitute only in the binding value
        let new_val = eg.add(LSubst(x, v_id, val_id))
        eg.union(subst_class, eg.add(LLet(y, new_val, body_id))) |> ignore
      } else if not(eg.get_data(v_id).fv.contains(y)) {
        // Safe descent into both val and body
        let new_val = eg.add(LSubst(x, v_id, val_id))
        let new_body = eg.add(LSubst(x, v_id, body_id))
        eg.union(subst_class, eg.add(LLet(y, new_val, new_body))) |> ignore
      }
      // else: y ∈ FV(v) — capture case, same rule as LLam, no action
    _ => ()
```

- [ ] **Step 4: Run tests**

```bash
cd egraph && moon test -f lambda_eval_wbtest.mbt
```

Expected: all tests in the file pass.

- [ ] **Step 5: Run all egraph tests (regression check)**

```bash
cd egraph && moon test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add egraph/lambda_eval_wbtest.mbt
git commit -m "feat(egraph/lambda): apply_subst LLam+LLet cases with capture guard"
```

---

### Task 6: Integration Tests

**Files:**
- Modify: `egraph/lambda_eval_wbtest.mbt`

- [ ] **Step 1: Add integration tests**

Add to `egraph/lambda_eval_wbtest.mbt`:

```moonbit
///|
test "eval integration: (2 + 3) * (4 - 1) = 15" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let four = eg.add(LNum(4))
  let one = eg.add(LNum(1))
  let sum = eg.add(LAdd(two, three))    // 2 + 3
  let diff = eg.add(LMinus(four, one))  // 4 - 1
  let prod = eg.add(LMul(sum, diff))    // (2 + 3) * (4 - 1)
  eg.rebuild()
  let (cost, expr) = eg.extract(prod, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LNum(15))
}

///|
test "eval integration: if IsZero(1) then 1 else 2 = 2" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let one = eg.add(LNum(1))
  let two = eg.add(LNum(2))
  let iszero = eg.add(LIsZero(one))
  let if_expr = eg.add(LIf(iszero, one, two))
  eg.rebuild()
  assert_eq(eg.find(if_expr), eg.find(two))
}

///|
test "eval integration: (λx. x * 0) 42 = 0 (beta + constant fold)" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let body = eg.add(LMul(x, zero))    // x * 0
  let lam = eg.add(LLam("x", body))  // λx. x * 0
  let n42 = eg.add(LNum(42))
  let app = eg.add(LApp(lam, n42))   // (λx. x * 0) 42
  eg.rebuild()
  let (cost, expr) = eg.extract(app, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LNum(0))
}

///|
test "eval integration: variable has no constant value" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  assert_eq(eg.get_data(x).val, None)
  // Symbolic x + 3 also has no constant value
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(x, three))
  assert_eq(eg.get_data(sum).val, None)
}
```

- [ ] **Step 2: Run all tests**

```bash
cd egraph && moon test
```

Expected: all tests pass, including the 4 new integration tests.

- [ ] **Step 3: Format**

```bash
cd egraph && moon fmt
```

- [ ] **Step 4: Commit**

```bash
git add egraph/lambda_eval_wbtest.mbt
git commit -m "feat(egraph/lambda): integration tests for evaluator"
```

---

## Self-Review

**Spec coverage** (from `docs/plans/2026-03-28-egglog-egraph-lambda-design.md` Part 2 test table):

| Test | Task |
|------|------|
| `(2 + 3) * (4 - 1)` → `LNum(15)` | Task 6 |
| `5 - 3` → `LNum(2)` | Task 4 |
| `(λx. x + 1) 5` → `LNum(6)` | Task 4 |
| `(λx. λy. x + y) 2 3` → `LNum(5)` | Task 5 |
| `IsZero(0)` → `LBool(true)` | Tasks 3+4 |
| `if IsZero(0) then 1 else 2` → `LNum(1)` | Task 4 |
| `if IsZero(1) then 1 else 2` → `LNum(2)` | Task 6 |
| `let x = 2 in x + x` → `LNum(4)` | Task 5 |
| `(λy. λx. y) x` → RecExpr contains LSubst | Task 5 |
| `(λx. x * 0) 42` → `LNum(0)` | Task 6 |

All 10 spec tests covered. ✓

**Type consistency:**
- `ValLit` defined Task 2, used in Tasks 3–6 ✓
- `EvalState` defined Task 2, used throughout ✓
- `apply_subst` defined Task 4 Step 3, called from Task 4 Step 4 modify hook ✓
- `fv_union` defined Task 2, used in Task 3 make/merge ✓
- `LSubst(name, value_id, expr_id)` — `child(0) = value_id`, `child(1) = expr_id` consistent with `apply_subst(x, v_id, e_id)` ✓

**No placeholders:** All steps contain complete MoonBit code. ✓
