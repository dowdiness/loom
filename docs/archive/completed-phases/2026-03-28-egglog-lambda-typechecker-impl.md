# Egglog Lambda Type Checker Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone egglog type checker for the full lambda calculus grammar (Num, Bool, If, Let, Lam, App, IsZero) with `BoolTy`, `UnitTy`, and scoped environments.

**Architecture:** New `egglog/examples/lambda/` package mirroring the STLC example. Environments are resolved by a MoonBit fact-builder (not Datalog rules) to avoid `IdVal` union conflicts. Typing propagates top-down via `Typing(env, expr)` trigger facts; types synthesize bottom-up.

**Tech Stack:** MoonBit, `dowdiness/egglog/src` package, `db.register`/`db.call`/`db.set`/`db.run_schedule`.

**Reference:** Design spec at `docs/plans/2026-03-28-egglog-egraph-lambda-design.md` Part 1.

---

## File Map

| File | Role |
|------|------|
| `egglog/examples/lambda/moon.pkg` | Package manifest — imports `dowdiness/egglog/src @egglog` |
| `egglog/examples/lambda/lambda.mbt` | `lambda_db()`, `all_rules()`, `LambdaEnv` fact-builder |
| `egglog/examples/lambda/lambda_test.mbt` | Blackbox tests: atoms, arithmetic, If, App, Let, shadowing, type errors |

---

### Task 1: Scaffold moon.pkg and lambda_db()

**Files:**
- Create: `egglog/examples/lambda/moon.pkg`
- Create: `egglog/examples/lambda/lambda.mbt`

- [ ] **Step 1: Create moon.pkg**

```json
import {
  "dowdiness/egglog/src" @egglog,
}
```

- [ ] **Step 2: Write lambda_db() in lambda.mbt**

```moonbit
///|
/// Create a database with all lambda calculus constructors and relations.
///
/// Tables:
///   Expressions: Num, BoolLit, Var, Add, Minus, IsZero, If,
///                Lam, App, Let, Unit, Unbound, Error
///   Types:       IntTy, BoolTy, UnitTy, Arrow
///   Envs:        EmptyEnv, ExtendEnv
///   Relations:   HasType(env, expr)->type, InEnv(env, name)->type,
///                Typing(env, expr)->IntVal(1)
pub fn lambda_db() -> @egglog.Database {
  let db = @egglog.Database::new()
  db.register("Num")       // Num(IntVal n) -> expr_id
  db.register("BoolLit")   // BoolLit(IntVal b) -> expr_id  (1=true, 0=false)
  db.register("Var")       // Var(StrVal name) -> expr_id
  db.register("Add")       // Add(left, right) -> expr_id
  db.register("Minus")     // Minus(left, right) -> expr_id
  db.register("IsZero")    // IsZero(expr) -> expr_id
  db.register("If")        // If(cond, then, else_) -> expr_id
  db.register("Lam")       // Lam(StrVal name, body) -> expr_id
  db.register("App")       // App(func, arg) -> expr_id
  db.register("Let")       // Let(StrVal name, val, body) -> expr_id
  db.register("Unit")      // Unit() -> expr_id
  db.register("Unbound")   // Unbound(StrVal name) -> expr_id  (never typed)
  db.register("Error")     // Error(StrVal msg) -> expr_id     (never typed)
  db.register("IntTy")     // IntTy() -> type_id
  db.register("BoolTy")    // BoolTy() -> type_id
  db.register("UnitTy")    // UnitTy() -> type_id
  db.register("Arrow")     // Arrow(domain, codomain) -> type_id
  db.register("EmptyEnv")  // EmptyEnv() -> env_id
  db.register("ExtendEnv") // ExtendEnv(parent, StrVal name, type) -> env_id
  db.register("HasType")   // HasType(env_id, expr_id) -> type_id
  db.register("InEnv")     // InEnv(env_id, StrVal name) -> type_id
  db.register("Typing")    // Typing(env_id, expr_id) -> IntVal(1)  (trigger)
  db
}
```

- [ ] **Step 3: Add LambdaEnv helper to lambda.mbt**

`LambdaEnv` wraps an env ID plus a snapshot of all currently-visible bindings. When extending the scope, it re-seeds **every** visible binding (not just the direct one) into the new env via `InEnv`. This prevents type errors in nested scopes — without transitive seeding, outer variables are invisible to inner `type-var` lookups.

```moonbit
///|
/// Host-language environment tracker.
///
/// Calling `extend` creates a new `ExtendEnv` e-class and pre-seeds
/// `InEnv(new_env, name) = ty` for **all** currently visible bindings —
/// including those inherited from outer scopes. Inner bindings shadow outer
/// ones because `Map` overwrite happens in MoonBit before seeding.
pub struct LambdaEnv {
  id : @egglog.Value
  bindings : Map[String, @egglog.Value]
}

///|
pub fn LambdaEnv::make(db : @egglog.Database) -> LambdaEnv {
  { id: db.call("EmptyEnv", []), bindings: {} }
}

///|
pub fn LambdaEnv::extend(
  self : LambdaEnv,
  db : @egglog.Database,
  name : String,
  ty : @egglog.Value,
) -> LambdaEnv {
  let new_id = db.call("ExtendEnv", [self.id, @egglog.StrVal(name), ty])
  let new_bindings : Map[String, @egglog.Value] = {}
  for k, v in self.bindings {
    new_bindings[k] = v
  }
  new_bindings[name] = ty  // shadow: innermost binding wins
  // Seed InEnv for every visible binding (transitive closure)
  for bname, btype in new_bindings {
    let _ = db.set("InEnv", [new_id, @egglog.StrVal(bname)], btype)
  }
  { id: new_id, bindings: new_bindings }
}
```

- [ ] **Step 4: Verify it compiles**

```bash
cd egglog && moon check
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add egglog/examples/lambda/
git commit -m "feat(egglog/lambda): scaffold moon.pkg, lambda_db, LambdaEnv helper"
```

---

### Task 2: Propagation Rules

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`

Propagation seeds `Typing(env, child)` from a typed parent so that bottom-up synthesis rules have an `env` to work with.

- [ ] **Step 1: Add propagation_rules() to lambda.mbt**

```moonbit
///|
/// Propagation rules: seed Typing(env, child) from a typed parent.
/// These run before synthesis rules so env is always known when typing fires.
pub fn propagation_rules() -> Array[@egglog.Rule] {
  [
    // propagate-add: Typing(env, e), Add(a, b, e) → Typing(env, a), Typing(env, b)
    {
      name: "propagate-add",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Add", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("a")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("b")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-minus
    {
      name: "propagate-minus",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Minus", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("a")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("b")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-iszero
    {
      name: "propagate-iszero",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("IsZero", [@egglog.Var("inner"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("inner")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-if
    {
      name: "propagate-if",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("If", [@egglog.Var("c"), @egglog.Var("t"), @egglog.Var("f"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("c")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("t")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("f")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-app
    {
      name: "propagate-app",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("App", [@egglog.Var("f"), @egglog.Var("a"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("f")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("a")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-let-val: seed Typing for val so type-num/etc fire before type-let-body
    {
      name: "propagate-let-val",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Let", [@egglog.Var("x"), @egglog.Var("v"), @egglog.Var("body"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("v")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
  ]
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd egglog && moon check
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add egglog/examples/lambda/lambda.mbt
git commit -m "feat(egglog/lambda): add propagation rules"
```

---

### Task 3: Atom Typing Rules + First Tests

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`
- Create: `egglog/examples/lambda/lambda_test.mbt`

- [ ] **Step 1: Write failing tests for Num, BoolLit, Unit, Var**

Create `egglog/examples/lambda/lambda_test.mbt`:

```moonbit
///|
fn run(db : @egglog.Database, rules : Array[@egglog.Rule]) -> Unit {
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(rules), 20))

}

///|
/// Extract the Id out of an @egglog.IdVal. Aborts on other variants.
/// Used throughout tests because db.lookup/db.call return @egglog.Value.
fn unwrap_id(v : @egglog.Value) -> @egglog.Id {
  match v {
    @egglog.IdVal(id) => id
    _ => abort("expected IdVal")
  }
}

///|
test "num synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let num_e = db.call("Num", [@egglog.IntVal(42)])
  let _ = db.set("Typing", [env, num_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, num_e])
  inspect(result is Some(_), content="true")
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "boollit synthesizes BoolTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let b_e = db.call("BoolLit", [@egglog.IntVal(1)])
  let _ = db.set("Typing", [env, b_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let bool_ty = db.call("BoolTy", [])
  let result = db.lookup("HasType", [env, b_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(bool_ty)), content="true")
}

///|
test "unit synthesizes UnitTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let unit_e = db.call("Unit", [])
  let _ = db.set("Typing", [env, unit_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let unit_ty = db.call("UnitTy", [])
  let result = db.lookup("HasType", [env, unit_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(unit_ty)), content="true")
}

///|
test "var with InEnv synthesizes type" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let _ = db.set("InEnv", [env, @egglog.StrVal("x")], int_ty)
  let var_e = db.call("Var", [@egglog.StrVal("x")])
  let _ = db.set("Typing", [env, var_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let result = db.lookup("HasType", [env, var_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "unbound var produces no HasType" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let unbound_e = db.call("Unbound", [@egglog.StrVal("x")])
  let _ = db.set("Typing", [env, unbound_e], @egglog.IntVal(1))
  run(db, atom_rules())
  inspect(db.lookup("HasType", [env, unbound_e]) is None, content="true")
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda 2>&1 | head -20
```

Expected: compile error or test failure (atom_rules not defined yet).

- [ ] **Step 3: Add atom_rules() to lambda.mbt**

```moonbit
///|
/// Atom typing rules: Num, BoolLit, Unit, Var.
pub fn atom_rules() -> Array[@egglog.Rule] {
  [
    // type-num
    {
      name: "type-num",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Num", [@egglog.Var("n"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-bool
    {
      name: "type-bool",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("BoolLit", [@egglog.Var("b"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("BoolTy", [])),
      ],
    },
    // type-unit
    {
      name: "type-unit",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Unit", [@egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("UnitTy", [])),
      ],
    },
    // type-var
    {
      name: "type-var",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Var", [@egglog.Var("x"), @egglog.Var("e")]),
        @egglog.Fact("InEnv", [@egglog.Var("env"), @egglog.Var("x"), @egglog.Var("t")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Var("t")),
      ],
    },
  ]
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add egglog/examples/lambda/
git commit -m "feat(egglog/lambda): atom typing rules (Num, BoolLit, Unit, Var)"
```

---

### Task 4: Arithmetic and IsZero Rules

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`
- Modify: `egglog/examples/lambda/lambda_test.mbt`

- [ ] **Step 1: Write failing tests**

Add to `lambda_test.mbt`:

```moonbit
///|
fn run_all(db : @egglog.Database) -> Unit {
  run(db, [..propagation_rules(), ..atom_rules(), ..arith_rules()])
}

///|
test "add synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let add_e = db.call("Add", [n1, n2])
  let _ = db.set("Typing", [env, add_e], @egglog.IntVal(1))
  run_all(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, add_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "minus synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(5)])
  let n2 = db.call("Num", [@egglog.IntVal(3)])
  let sub_e = db.call("Minus", [n1, n2])
  let _ = db.set("Typing", [env, sub_e], @egglog.IntVal(1))
  run_all(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, sub_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "iszero synthesizes BoolTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n = db.call("Num", [@egglog.IntVal(0)])
  let iz_e = db.call("IsZero", [n])
  let _ = db.set("Typing", [env, iz_e], @egglog.IntVal(1))
  run_all(db)
  let bool_ty = db.call("BoolTy", [])
  let result = db.lookup("HasType", [env, iz_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(bool_ty)), content="true")
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda 2>&1 | grep "arith_rules\|FAIL"
```

Expected: compile error (arith_rules not defined).

- [ ] **Step 3: Add arith_rules() to lambda.mbt**

```moonbit
///|
/// Arithmetic and IsZero typing rules.
pub fn arith_rules() -> Array[@egglog.Rule] {
  [
    // type-add: Add(a, b, e), HasType(env, a)=IntTy, HasType(env, b)=IntTy → HasType(env, e)=IntTy
    {
      name: "type-add",
      query: [
        @egglog.Fact("Add", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("a"), @egglog.Var("ta")]),
        @egglog.Fact("IntTy", [@egglog.Var("ta")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("b"), @egglog.Var("tb")]),
        @egglog.Fact("IntTy", [@egglog.Var("tb")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-minus: identical structure to type-add
    {
      name: "type-minus",
      query: [
        @egglog.Fact("Minus", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("a"), @egglog.Var("ta")]),
        @egglog.Fact("IntTy", [@egglog.Var("ta")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("b"), @egglog.Var("tb")]),
        @egglog.Fact("IntTy", [@egglog.Var("tb")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-iszero: IsZero(inner, e), HasType(env, inner)=IntTy → HasType(env, e)=BoolTy
    {
      name: "type-iszero",
      query: [
        @egglog.Fact("IsZero", [@egglog.Var("inner"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("inner"), @egglog.Var("ti")]),
        @egglog.Fact("IntTy", [@egglog.Var("ti")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("BoolTy", [])),
      ],
    },
  ]
}
```

- [ ] **Step 4: Run — expect pass**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add egglog/examples/lambda/
git commit -m "feat(egglog/lambda): arithmetic and IsZero typing rules"
```

---

### Task 5: If Rule

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`
- Modify: `egglog/examples/lambda/lambda_test.mbt`

- [ ] **Step 1: Write failing test**

Add to `lambda_test.mbt`:

```moonbit
///|
fn run_full(db : @egglog.Database) -> Unit {
  run(db, [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..if_rules()])
}

///|
test "if with matching branch types synthesizes branch type" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("BoolLit", [@egglog.IntVal(1)])
  let t = db.call("Num", [@egglog.IntVal(1)])
  let f = db.call("Num", [@egglog.IntVal(2)])
  let if_e = db.call("If", [cond, t, f])
  let _ = db.set("Typing", [env, if_e], @egglog.IntVal(1))
  run_full(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, if_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "if with mismatched branch types unions the type classes" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("BoolLit", [@egglog.IntVal(1)])
  let t = db.call("Num", [@egglog.IntVal(1)])      // IntTy
  let f = db.call("BoolLit", [@egglog.IntVal(0)])  // BoolTy
  let if_e = db.call("If", [cond, t, f])
  let _ = db.set("Typing", [env, if_e], @egglog.IntVal(1))
  run_full(db)
  let int_ty = db.call("IntTy", [])
  let bool_ty = db.call("BoolTy", [])
  // Both branches typed, but no shared type → HasType is not set
  // (type-if requires both branches to have the SAME type class)
  inspect(db.lookup("HasType", [env, if_e]) is None, content="true")
  // int_ty and bool_ty are NOT merged (no union happened)
  inspect(db.find(unwrap_id(int_ty)) != db.find(unwrap_id(bool_ty)), content="true")
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda 2>&1 | grep "if_rules\|FAIL"
```

- [ ] **Step 3: Add if_rules() to lambda.mbt**

```moonbit
///|
/// If typing rule: condition must be BoolTy, both branches must share type.
pub fn if_rules() -> Array[@egglog.Rule] {
  [
    {
      name: "type-if",
      query: [
        @egglog.Fact("If", [@egglog.Var("c"), @egglog.Var("t"), @egglog.Var("f"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("c"), @egglog.Var("tc")]),
        @egglog.Fact("BoolTy", [@egglog.Var("tc")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("t"), @egglog.Var("ty")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("f"), @egglog.Var("ty")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Var("ty")),
      ],
    },
  ]
}
```

- [ ] **Step 4: Run — expect pass**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda
```

- [ ] **Step 5: Commit**

```bash
git add egglog/examples/lambda/
git commit -m "feat(egglog/lambda): If typing rule with BoolTy condition"
```

---

### Task 6: App Rule

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`
- Modify: `egglog/examples/lambda/lambda_test.mbt`

- [ ] **Step 1: Write failing test**

Add to `lambda_test.mbt`:

```moonbit
///|
test "app synthesizes return type from Arrow" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Build: f applied to 42, where f : Int -> Int
  let f_e = db.call("Var", [@egglog.StrVal("f")])
  let _ = db.set("InEnv", [env, @egglog.StrVal("f")], arr_ty)
  let arg_e = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [f_e, arg_e])
  let _ = db.set("Typing", [env, app_e], @egglog.IntVal(1))
  run(db, [..propagation_rules(), ..atom_rules(), ..app_rules()])
  let result = db.lookup("HasType", [env, app_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda 2>&1 | grep "app_rules\|FAIL"
```

- [ ] **Step 3: Add app_rules() to lambda.mbt**

```moonbit
///|
/// App typing rule: f : (ta -> tb), a : ta → App(f, a) : tb
pub fn app_rules() -> Array[@egglog.Rule] {
  [
    {
      name: "type-app",
      query: [
        @egglog.Fact("App", [@egglog.Var("f"), @egglog.Var("a"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("f"), @egglog.Var("arr")]),
        @egglog.Fact("Arrow", [@egglog.Var("ta"), @egglog.Var("tb"), @egglog.Var("arr")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("a"), @egglog.Var("ta")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Var("tb")),
      ],
    },
  ]
}
```

- [ ] **Step 4: Run — expect pass**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda
```

- [ ] **Step 5: Commit**

```bash
git add egglog/examples/lambda/
git commit -m "feat(egglog/lambda): App typing rule"
```

---

### Task 7: Let Rules

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`
- Modify: `egglog/examples/lambda/lambda_test.mbt`

- [ ] **Step 1: Write failing test**

Add to `lambda_test.mbt`:

```moonbit
///|
test "let binding synthesizes body type" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  // let x = 42 in x + 1
  let num_42 = db.call("Num", [@egglog.IntVal(42)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let let_e = db.call("Let", [@egglog.StrVal("x"), num_42, body])
  let _ = db.set("Typing", [env, let_e], @egglog.IntVal(1))
  run(db, [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..let_rules()])
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, let_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda 2>&1 | grep "let_rules\|FAIL"
```

- [ ] **Step 3: Add let_rules() to lambda.mbt**

```moonbit
///|
/// Let typing rules.
///
/// type-let-body: once val is typed, extend env and seed Typing for body.
///   Uses LetAction to call ExtendEnv (hashconsed), creating the scope id.
///
/// type-let-return: once body is typed in the extended env, propagate to Let.
///   Queries ExtendEnv as a Fact to reconstruct the ext_env id deterministically.
pub fn let_rules() -> Array[@egglog.Rule] {
  [
    // type-let-body: Let(x, v, body, e), Typing(env, e), HasType(env, v)=tv
    //   → let ext_env = ExtendEnv(env, x, tv)
    //     Typing(ext_env, body)
    //     InEnv(ext_env, x) = tv
    {
      name: "type-let-body",
      query: [
        @egglog.Fact("Let", [@egglog.Var("x"), @egglog.Var("v"), @egglog.Var("body"), @egglog.Var("e")]),
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("v"), @egglog.Var("tv")]),
      ],
      actions: [
        @egglog.LetAction("ext_env", @egglog.Call("ExtendEnv", [@egglog.Var("env"), @egglog.Var("x"), @egglog.Var("tv")])),
        @egglog.Set("Typing", [@egglog.Var("ext_env"), @egglog.Var("body")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("InEnv", [@egglog.Var("ext_env"), @egglog.Var("x")], @egglog.Var("tv")),
      ],
    },
    // type-let-return: Let(x, v, body, e), HasType(env, v)=tv,
    //                  ExtendEnv(env, x, tv)=ext_env, HasType(ext_env, body)=ty
    //   → HasType(env, e) = ty
    {
      name: "type-let-return",
      query: [
        @egglog.Fact("Let", [@egglog.Var("x"), @egglog.Var("v"), @egglog.Var("body"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("v"), @egglog.Var("tv")]),
        @egglog.Fact("ExtendEnv", [@egglog.Var("env"), @egglog.Var("x"), @egglog.Var("tv"), @egglog.Var("ext_env")]),
        @egglog.Fact("HasType", [@egglog.Var("ext_env"), @egglog.Var("body"), @egglog.Var("ty")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Var("ty")),
      ],
    },
  ]
}
```

- [ ] **Step 4: Run — expect pass**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda
```

- [ ] **Step 5: Commit**

```bash
git add egglog/examples/lambda/
git commit -m "feat(egglog/lambda): Let typing rules (type-let-body, type-let-return)"
```

---

### Task 8: check-lam Rule

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`
- Modify: `egglog/examples/lambda/lambda_test.mbt`

Note: `check-lam` is **bidirectional** — it requires `HasType(env, lam_e) = Arrow(...)` to be seeded externally. Synthesis of unannotated lambdas is not supported without parameter type annotations.

- [ ] **Step 1: Write failing test**

Add to `lambda_test.mbt`:

```moonbit
///|
test "check-lam: lambda body typed in extended env" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // λx. x + 1, seeded with expected type Int -> Int
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let _ = db.set("Typing", [env, lam_e], @egglog.IntVal(1))
  let _ = db.set("HasType", [env, lam_e], arr_ty)  // seed expected type
  run(db, [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..lam_rules()])
  // body should be typed as Int in the extended env
  let ext_env = db.call("ExtendEnv", [env, @egglog.StrVal("x"), int_ty])
  let result = db.lookup("HasType", [ext_env, body])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda 2>&1 | grep "lam_rules\|FAIL"
```

- [ ] **Step 3: Add lam_rules() to lambda.mbt**

```moonbit
///|
/// Lambda typing rules (bidirectional checking).
///
/// check-lam: requires HasType(env, lam_e) = Arrow(a, b) to already exist.
///   Seeds Typing and InEnv for the body in the extended environment.
pub fn lam_rules() -> Array[@egglog.Rule] {
  [
    {
      name: "check-lam",
      query: [
        @egglog.Fact("Lam", [@egglog.Var("x"), @egglog.Var("body"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("arr")]),
        @egglog.Fact("Arrow", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("arr")]),
      ],
      actions: [
        @egglog.LetAction("ext_env", @egglog.Call("ExtendEnv", [@egglog.Var("env"), @egglog.Var("x"), @egglog.Var("a")])),
        @egglog.Set("Typing", [@egglog.Var("ext_env"), @egglog.Var("body")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("InEnv", [@egglog.Var("ext_env"), @egglog.Var("x")], @egglog.Var("a")),
      ],
    },
  ]
}
```

- [ ] **Step 4: Run — expect pass**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda
```

- [ ] **Step 5: Commit**

```bash
git add egglog/examples/lambda/
git commit -m "feat(egglog/lambda): check-lam bidirectional typing rule"
```

---

### Task 9: all_rules() + Integration Tests (Shadowing, Type Errors)

**Files:**
- Modify: `egglog/examples/lambda/lambda.mbt`
- Modify: `egglog/examples/lambda/lambda_test.mbt`
- Modify: `docs/README.md`

- [ ] **Step 1: Add all_rules() to lambda.mbt**

```moonbit
///|
/// All lambda typing rules combined.
pub fn all_rules() -> Array[@egglog.Rule] {
  [
    ..propagation_rules(),
    ..atom_rules(),
    ..arith_rules(),
    ..if_rules(),
    ..app_rules(),
    ..let_rules(),
    ..lam_rules(),
  ]
}
```

- [ ] **Step 2: Write shadowing + integration tests**

Add to `lambda_test.mbt`:

```moonbit
///|
test "let shadowing: inner x shadows outer x" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  // let x = 1 in let x = true in x
  // outer x : Int, inner x : Bool → result should be BoolTy
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let bool_true = db.call("BoolLit", [@egglog.IntVal(1)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let inner_let = db.call("Let", [@egglog.StrVal("x"), bool_true, var_x])
  let outer_let = db.call("Let", [@egglog.StrVal("x"), num_1, inner_let])
  let _ = db.set("Typing", [env, outer_let], @egglog.IntVal(1))
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(all_rules()), 30))
  let bool_ty = db.call("BoolTy", [])
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, outer_let])
  // inner x is BoolTy, so outer_let : BoolTy
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(bool_ty)), content="true")
  // IntTy and BoolTy are NOT unioned (no type error occurred)
  inspect(db.find(unwrap_id(int_ty)) != db.find(unwrap_id(bool_ty)), content="true")
}

///|
test "app + lam full round-trip" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // (λx. x + 1) 42
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let num_42 = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [lam_e, num_42])
  let _ = db.set("Typing", [env, app_e], @egglog.IntVal(1))
  let _ = db.set("HasType", [env, lam_e], arr_ty)  // seed lam type
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(all_rules()), 30))
  let result = db.lookup("HasType", [env, app_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}
```

```moonbit
///|
test "LambdaEnv inherited bindings: let x=1 in let y=2 in x+y" {
  // Exercises LambdaEnv::extend transitive seeding.
  // When typing the body `x+y`, both x and y must be visible even though
  // only y is directly bound by the inner Let. Without transitive seeding,
  // the `type-var` rule for x would fire in the inner env and find no InEnv entry.
  let db = lambda_db()
  let env0 = LambdaEnv::make(db)
  // outer: let x = 1 in ...
  let num_1  = db.call("Num", [@egglog.IntVal(1)])
  let num_2  = db.call("Num", [@egglog.IntVal(2)])
  let var_x  = db.call("Var", [@egglog.StrVal("x")])
  let var_y  = db.call("Var", [@egglog.StrVal("y")])
  let body   = db.call("Add", [var_x, var_y])
  let inner_let = db.call("Let", [@egglog.StrVal("y"), num_2, body])
  let outer_let = db.call("Let", [@egglog.StrVal("x"), num_1, inner_let])
  // Seed Typing at root env0; all_rules propagate downward
  let _ = db.set("Typing", [env0.id, outer_let], @egglog.IntVal(1))
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(all_rules()), 30))
  // outer_let : Int (x:Int + y:Int → Int, Let returns body type)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env0.id, outer_let])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}
```

- [ ] **Step 3: Run — expect pass**

```bash
cd egglog && moon test -p dowdiness/egglog/examples/lambda
```

Expected: all tests pass.

- [ ] **Step 4: Run full egglog test suite to confirm no regressions**

```bash
cd egglog && moon test
```

Expected: all tests pass.

- [ ] **Step 5: Update docs/README.md — add plan to active plans index**

In `docs/README.md`, under **Active Plans**, the entry for this plan is already present from the design doc commit. Verify it's there:

```bash
grep "egglog-lambda-typechecker" docs/README.md
```

If missing, add:
```
- [plans/2026-03-28-egglog-lambda-typechecker-impl.md](plans/2026-03-28-egglog-lambda-typechecker-impl.md) — Egglog Lambda Type Checker Implementation Plan
```

- [ ] **Step 6: Commit**

```bash
git add egglog/examples/lambda/ docs/README.md docs/plans/2026-03-28-egglog-lambda-typechecker-impl.md
git commit -m "feat(egglog/lambda): all_rules + integration tests (shadowing, type errors)"
```
