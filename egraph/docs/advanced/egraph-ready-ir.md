# Designing E-Graph-Ready Intermediate Representations

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

E-graphs operate on pure, tree-shaped expressions with fixed arity. Most source languages violate one or more of these requirements. This document explains how to transform a source language into an intermediate representation (IR) that an e-graph can optimize, and when you can skip those transformations entirely.

## Why Source Languages Aren't E-Graph-Ready

Consider a typical imperative program:

```
x = readInput();       // side effect: I/O
x = x + 1;             // mutation: reassignment
if (x > 0) {           // control flow: branching
  print(x);            // side effect: I/O
}
```

An e-graph records that `A = B` and then freely substitutes one for the other. Four properties of source languages break this:

| Property needed | Why the e-graph needs it | What breaks it |
|----------------|--------------------------|----------------|
| **Pure** | Substituting equals for equals must preserve behavior | Side effects (I/O, mutation, exceptions) make order matter |
| **Tree-shaped** | E-nodes are `Op(child1, child2, ...)` | Statements, goto, loops are sequential, not tree-shaped |
| **Explicit data flow** | Children point to values, not storage locations | Mutable variables alias the same storage; the "value" changes over time |
| **Fixed arity** | Pattern matching requires knowing how many children an operator has | Varargs, overloading, variadic print |

The rest of this document presents three transformations that convert a source language into a form the e-graph can work with.

## Transformation 1: Separating Pure from Effectful

### Theory

A computation is **pure** if its result depends only on its inputs and it produces no observable side effects. Pure expressions can be reordered, duplicated, or eliminated without changing behavior — exactly what e-graph rewrites do.

Side effects impose **ordering constraints**: `print("a"); print("b")` must execute in that order. An e-graph cannot represent this ordering because it treats both sides of an equation as interchangeable.

The solution is to split the program into two layers:

- **Pure core:** expressions that the e-graph can optimize (arithmetic, data transformations, function calls with no side effects).
- **Effect spine:** a sequential structure that preserves ordering of side effects and references into the pure core.

### Example

Suppose we have the source program:

```
print(x + 0); y * 1
```

We separate it into:

```
pure_1 = x + 0          -- enters the e-graph
pure_2 = y * 1           -- enters the e-graph
effect: print(pure_1)    -- stays outside, preserves ordering
result: pure_2           -- the program's value

After e-graph optimization:
pure_1 = x               -- simplified by Add-identity rule
pure_2 = y               -- simplified by Mul-identity rule
effect: print(pure_1)    -- unchanged (still prints x)
result: pure_2            -- returns y
```

The e-graph optimized the pure subexpressions independently, while the effect spine kept `print` in place.

### MoonBit sketch

To model this in the library, extend `MyLang` with effectful operators that stay outside the e-graph's rewrite rules:

```moonbit
enum EffectfulLang {
  // Pure (optimizable by the e-graph)
  Num(Int)
  Var(String)
  Add(Id, Id)
  Mul(Id, Id)

  // Effectful (not subject to rewrite rules)
  Print(Id)              // print a pure expression
  Seq(Id, Id)            // sequence two computations
} derive(Eq, Hash)
```

The key insight: rewrite rules only target the pure constructors. You would write rules like `(Add ?x (Num:0)) => ?x` but never `(Print ?x) => ?x` or `(Seq ?a ?b) => ?b`. The effectful constructors participate in the e-graph's data structure (they are valid e-nodes) but no rewrite rule touches them, so their ordering is preserved.

A more disciplined approach wraps the boundary explicitly:

```moonbit
enum PureLang {
  Num(Int)
  Var(String)
  Add(Id, Id)
  Mul(Id, Id)
} derive(Eq, Hash)

// Effect spine — NOT in the e-graph at all
enum Effect {
  Print(Id)               // Id refers into the PureLang e-graph
  Then(Effect, Effect)    // sequencing
  Done
}
```

This second design makes the boundary airtight: the e-graph only ever contains `PureLang` nodes, and the effect spine is a separate data structure that holds `Id` references into the e-graph.

### Connection to monads and algebraic effects

This separation is the same idea behind monadic IO in Haskell and algebraic effect systems in languages like Koka and Eff. The pure/effectful split is not an e-graph-specific invention — it is a fundamental principle of programming language design. The e-graph simply makes the requirement explicit: if it is in the e-graph, it must be pure.

## Transformation 2: Flattening Control Flow

### Theory

Imperative languages distinguish **statements** (which execute for their effects) from **expressions** (which produce values). E-graphs only understand expressions — tree-shaped terms with children.

The solution is to convert control flow constructs into expression nodes:

- **If-statements** become `Select(condition, then_value, else_value)` — a ternary expression node.
- **Loops** become recursive let-bindings or fixed-point operators (more advanced, usually not needed for a first pass).

### Example

Source code with an if-statement:

```
if (c) { a } else { b }
```

Becomes a single e-node:

```
Select(c, a, b)
```

This is now a tree node that the e-graph can work with. Better yet, it participates in rewrites:

```
Select(true,  a, b)  =>  a      -- constant condition: take then-branch
Select(false, a, b)  =>  b      -- constant condition: take else-branch
Select(c, a, a)      =>  a      -- both branches equal: condition irrelevant
```

These are valid equivalence-preserving rewrites because `Select` is a pure expression — it evaluates both branches symbolically and returns one.

### MoonBit sketch

Extend `MyLang` with control flow nodes:

```moonbit
enum ControlLang {
  Num(Int)
  Var(String)
  Add(Id, Id)
  Mul(Id, Id)

  // Booleans
  Bool(Bool)
  Gt(Id, Id)              // greater-than comparison

  // Control flow as expression
  Select(Id, Id, Id)      // Select(cond, then, else)
} derive(Eq, Hash)
```

The `ENode` implementation for `Select` has arity 3:

```moonbit
impl ENode for ControlLang with arity(self) {
  match self {
    Num(_) | Var(_) | Bool(_) => 0
    Add(_, _) | Mul(_, _) | Gt(_, _) => 2
    Select(_, _, _) => 3
  }
}

impl ENode for ControlLang with child(self, i) {
  match self {
    Add(a, b) | Mul(a, b) | Gt(a, b) =>
      if i == 0 { a } else { b }
    Select(c, t, e) =>
      if i == 0 { c } else if i == 1 { t } else { e }
    _ => abort("no children")
  }
}

impl ENode for ControlLang with map_children(self, f) {
  match self {
    Num(_) | Var(_) | Bool(_) => self
    Add(a, b) => Add(f(a), f(b))
    Mul(a, b) => Mul(f(a), f(b))
    Gt(a, b) => Gt(f(a), f(b))
    Select(c, t, e) => Select(f(c), f(t), f(e))
  }
}
```

With this representation, rewrite rules like `(Select (Bool:true) ?a ?b) => ?a` work naturally through the existing pattern matching and equality saturation machinery.

## Transformation 3: SSA / Let-Binding Form

### Theory

In imperative languages, a variable name can refer to different values at different points in the program:

```
x = 1;
x = x + 2;
return x;       // x is 3
```

The name `x` is reused, but the e-graph needs each `Id` to refer to exactly one value. **Static Single Assignment (SSA)** form eliminates this ambiguity by giving each definition a unique name:

```
x₀ = 1
x₁ = Add(x₀, Num(2))
return x₁
```

Now each name is defined exactly once, and each binding translates directly to an `egraph.add()` call:

```moonbit
let x0 = eg.add(Num(1))            // x₀ = 1
let two = eg.add(Num(2))
let x1 = eg.add(Add(x0, two))      // x₁ = x₀ + 2
// x1 is the Id we optimize and extract from
```

At control flow joins (where two branches define different values for the same variable), SSA uses **phi-functions**: `x₂ = φ(x₀, x₁)` selects the value from whichever branch was taken. In the e-graph world, phi-functions map directly to `Select` nodes from Transformation 2.

### Connection to lambda calculus

In functional languages, let-bindings are syntactic sugar for lambda application:

```
let x = 5 in x + x
```

is equivalent to:

```
(λx. x + x)(5)
```

Lambda calculus is SSA by default — every variable is bound exactly once by a lambda or let. This is one reason lambda calculus is the canonical example language for e-graphs: no SSA transformation is needed.

In the library's `LambdaLang`, the `LLet(name, value, body)` constructor is already in SSA form:

```moonbit
// let x = 5 in x + x
let five = eg.add(LNum(5))
let x = eg.add(LVar("x"))
let body = eg.add(LAdd(x, x))
let expr = eg.add(LLet("x", five, body))
```

Each `LLet` binding defines its variable exactly once, and the body is a pure expression tree — precisely what the e-graph requires.

## The Complete Pipeline

Putting all three transformations together:

```
Source Code
    │
    ▼
  Parse (AST)
    │
    ▼
  Lower to E-Graph-Ready IR
    ├── 1. Separate effects from pure computation
    ├── 2. Flatten control flow (if → Select, loops → fixpoint)
    └── 3. SSA / let-binding (unique names, no mutation)
    │
    ▼
  E-Graph Optimization
    ├── eg.add()     — add IR nodes
    ├── rules        — define equivalence-preserving rewrites
    ├── runner.run() — equality saturation
    └── eg.extract() — select cheapest equivalent
    │
    ▼
  Codegen / Eval
    ├── Reconstruct effect spine with optimized pure Ids
    └── Generate target code or interpret
```

### Which transformations are mandatory?

It depends on your source language:

| Source language | Effect separation | Control flow flattening | SSA |
|----------------|:-:|:-:|:-:|
| Lambda calculus | not needed | not needed | not needed |
| Pure functional (ML, Haskell core) | not needed | minor (case → match) | not needed |
| Expression-oriented (Rust expr subset) | needed for I/O | minor | needed for mut |
| Imperative (C, Python) | needed | needed | needed |
| DSL (SQL, tensor ops) | usually not needed | usually not needed | usually not needed |

**Practical advice:** Start with the smallest IR that captures your domain. If your expressions are already pure and tree-shaped (math formulas, SQL queries, tensor operations), you can skip all three transformations and feed them directly to the e-graph.

## Lambda Calculus: Already E-Graph-Ready

The library's `LambdaLang` type works directly with the e-graph because lambda calculus satisfies all four requirements:

| Property | How lambda calculus satisfies it |
|----------|-------------------------------|
| **Pure** | No side effects — every expression is a value |
| **Tree-shaped** | Application, abstraction, and let-binding are all tree nodes |
| **Explicit data flow** | Variables are bound by lambda/let, not by mutable storage |
| **Fixed arity** | `LAdd` has 2 children, `LLam` has 1, `LNum` has 0 — always fixed |

This is why `LambdaLang` needs no IR transformation. You parse a lambda expression, add its nodes to the e-graph, run equality saturation with arithmetic rules, and extract the optimized result:

```moonbit
let eg : EGraph[LambdaLang] = EGraph::new()
let x = eg.add(LVar("x"))
let zero = eg.add(LNum(0))
let one = eg.add(LNum(1))
let sum = eg.add(LAdd(x, zero))       // x + 0
let expr = eg.add(LMul(sum, one))     // (x + 0) * 1

let rules = [
  rewrite("add-0", "(Add ?x (Num:0))", "?x"),
  rewrite("mul-1", "(Mul ?x (Num:1))", "?x"),
]
let runner = Runner::new(eg, roots=[expr])
runner.run(rules)                       // Saturated

let (cost, result) = runner.egraph.extract(expr, ast_size())
// cost == 1, result.root() == LVar("x")
```

### The one caveat: variable capture

Lambda calculus has one subtlety that requires care: **variable capture during beta-reduction**. The rewrite `(λx. body)(arg) => body[x := arg]` (substituting `arg` for `x` in `body`) is only valid when `arg` contains no free variables that would be captured by a lambda inside `body`.

For example:

```
(λx. λy. x)(y)  =>  λy. y     -- WRONG: the outer y was captured
(λx. λy. x)(y)  =>  λz. y     -- CORRECT: rename the inner binder first
```

The library's current `LambdaLang` does not implement beta-reduction as a rewrite rule (it would require alpha-renaming or De Bruijn indices). Arithmetic rewrites like `Add ?x (Num:0) => ?x` are safe because they do not involve binders. If you need beta-reduction in the e-graph, consider encoding variables with De Bruijn indices or using explicit substitution calculi — both eliminate capture by construction.

## Summary

| Transformation | What it does | When needed |
|---------------|-------------|-------------|
| Effect separation | Isolates pure computation from side effects | When source has I/O, mutation, exceptions |
| Control flow flattening | Converts statements to expression nodes | When source has if-statements, loops, goto |
| SSA / let-binding | Gives each variable definition a unique name | When source has mutable variables |

The goal of all three transformations is the same: produce a pure, tree-shaped, explicit-data-flow IR with fixed arity — the form that e-graphs are designed to optimize. Lambda calculus already has this form. Imperative languages need all three. Domain-specific languages often need none.
