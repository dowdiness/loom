# E-Graph: An Introduction

## The Problem: "Which Way Should I Simplify This?"

Imagine you have the expression `(x + 0) * 1`. You know two simplification rules:

- `x + 0 → x` (adding zero does nothing)
- `x * 1 → x` (multiplying by one does nothing)

Which rule do you apply first? In this case it doesn't matter — both paths lead to `x`. But in general, **the order you apply rules changes the result.** A traditional optimizer picks one path and hopes it's the best. Sometimes it isn't.

This is called the **phase-ordering problem**, and it has plagued compilers for decades.

An **e-graph** solves this by refusing to choose. Instead of applying one rule and discarding the original, it keeps *both* versions — the original and the rewritten form — recorded as equivalent. It explores all possible rewrites simultaneously, then picks the best result at the end.

## What Is an E-Graph?

An **equality graph (e-graph)** is a data structure that stores many equivalent expressions in compact space.

Think of it like a dictionary of synonyms, but for code:

```
"x + 0"  =  "x"           (because adding zero does nothing)
"x * 1"  =  "x"           (because multiplying by one does nothing)
"2 + 3"  =  "5"           (because we can compute the result)
"a + b"  =  "b + a"       (because addition is commutative)
```

The e-graph doesn't just store pairs — it groups all equivalent expressions into **e-classes**. If `A = B` and `B = C`, then `A`, `B`, and `C` are all in the same e-class. You can ask the e-graph: "what is the simplest expression equivalent to this one?" and it will find it.

## A Concrete Example

Let's walk through optimizing `(x + 0) * 1` step by step.

**Step 1: Build the expression.**

```
(Mul (Add (Var "x") (Num 0)) (Num 1))
```

The e-graph stores each subexpression in its own e-class:

```
e-class 0: { Var("x") }
e-class 1: { Num(0) }
e-class 2: { Num(1) }
e-class 3: { Add(e0, e1) }        -- represents x + 0
e-class 4: { Mul(e3, e2) }        -- represents (x + 0) * 1
```

**Step 2: Apply rewrite rules.**

Rule `x + 0 → x` matches `Add(e0, e1)` in e-class 3. The e-graph learns that e-class 3 is also equivalent to whatever is in e-class 0:

```
e-class 0: { Var("x") }
e-class 3: { Add(e0, e1), Var("x") }    -- x + 0 = x (merged with e0)
e-class 4: { Mul(e3, e2) }
```

Rule `x * 1 → x` now matches `Mul(e3, e2)` in e-class 4. The e-graph merges:

```
e-class 4: { Mul(e3, e2), Var("x") }    -- (x + 0) * 1 = x
```

**Step 3: Extract the cheapest.**

E-class 4 contains both `Mul(Add(Var("x"), Num(0)), Num(1))` (cost 5 nodes) and `Var("x")` (cost 1 node). The e-graph returns `Var("x")` — the simplest equivalent expression.

No rule ordering needed. Both rules fired, both results were kept, and the best one was selected at the end.

## The Golden Rule: Equivalence-Preserving Rewrites

Every rewrite rule in an e-graph must be **equivalence-preserving**: the left side and right side must mean the same thing for all possible inputs.

This is the foundational guarantee. The e-graph records `lhs = rhs`, not "replace lhs with rhs." Both sides coexist. If a rule is wrong — if the two sides aren't actually equal — the e-graph will silently derive false equivalences, and extraction will return incorrect results.

### Valid Rules

These are safe because both sides always produce the same value:

| Rule | Why it's valid |
|------|---------------|
| `x + 0 → x` | Adding zero is identity |
| `x * 1 → x` | Multiplying by one is identity |
| `a + b → b + a` | Addition is commutative |
| `(a + b) + c → a + (b + c)` | Addition is associative |
| `x * (y + z) → x*y + x*z` | Distributivity |
| `x * 0 → 0` | Multiplication by zero |

### Invalid Rules

These look reasonable but break the equivalence guarantee:

| Rule | Why it's invalid |
|------|-----------------|
| `x / 2 → x >> 1` | Only equal for non-negative integers; wrong for negative values or floats |
| `sin(x) → x` | Only approximately equal near zero |
| `f(x) → cached_f(x)` | Semantically different if `f` has side effects |
| `sqrt(x²) → x` | Fails for negative `x` (should be `\|x\|`) |

### Why This Matters

1. **Correctness by construction.** If every rule preserves equivalence, the e-graph can never derive a false equality. Every expression in an e-class truly represents the same value.

2. **Order independence.** Because every rule is safe to apply anywhere, the e-graph can apply all rules simultaneously without worrying about interactions.

3. **Extraction safety.** After optimization, any expression chosen from an e-class is semantically correct — they're all equivalent. Only cost differs.

### What If Your Transform Isn't Equivalence-Preserving?

If you need lossy approximations (`sin(x) ≈ x`), platform-specific rewrites (`x / 2 → x >> 1` on unsigned integers), or side-effect-changing transforms, a plain e-graph is the wrong tool. Use a traditional rewrite system with explicit preconditions, or encode the precondition as a **conditional rewrite** that checks the substitution before firing.

## Can I Use This as an Evaluator?

Partially — with important caveats.

### What Works

**Constant folding.** Using e-class analysis, `Add(2, 3)` automatically gets the value `5`. The analysis hook adds `Num(5)` to the same e-class. This is evaluation embedded in the e-graph.

**Symbolic reduction.** Rules like `x + 0 → x` simplify expressions. Combined with constant folding, you get a partial evaluator: `(2 + 3) * y` becomes `5 * y`.

**Partial evaluation.** When some variables are known and others aren't, the e-graph simplifies what it can — more powerfully than a traditional evaluator, because it explores all simplification paths.

### What Doesn't Work

Not all limitations are the same. Some break the equivalence guarantee; others are practical problems with correct rules.

| Issue | Equivalence broken? | Real problem |
|-------|---------------------|-------------|
| **Side effects** | **Yes** | `print("hello"); 5` and `5` produce different observable behavior — treating them as equal is semantically wrong |
| **Runtime control flow** | No | `if ?cond then ?a else ?b → ?a` would be wrong, but `if true then ?a else ?b → ?a` is fine. The issue is that runtime conditions aren't known at rewrite time |
| **Unbounded recursion** | No | `factorial(3) → 3 * factorial(2)` is a valid rule — both sides truly are equal. But applying it repeatedly causes infinite e-graph growth. Each step is correct; saturation just never terminates |
| **Performance** | No | E-graph saturation is correct but too slow for runtime use. This is a compile-time tool |

**The sweet spot:** Use the e-graph as an **optimizer between parsing and evaluation**:

```
Parse → Optimize with e-graph → Extract cheapest → Evaluate with traditional interpreter
```

## Preparing Your Code for E-Graph Optimization

Source languages aren't directly suitable for e-graphs. You need an intermediate representation (IR) with specific properties.

### What the E-Graph Needs

| Property | Why | Source language problem |
|----------|-----|----------------------|
| **Pure** | Every rewrite must be equivalence-preserving | Source has side effects (print, mutation, I/O) |
| **Tree-shaped** | E-nodes are `operator(child₁, child₂, ...)` | Source has sequential statements, goto, loops |
| **Explicit data flow** | Children point to values, not memory locations | Source has mutable variables, aliasing |
| **Fixed arity** | Each operator has known number of children | Source has varargs, overloading |

### How to Get There

**1. Separate pure from effectful.** Only pure parts enter the e-graph. Side effects stay in a sequential wrapper.

```
Source:           print(x + 0); y * 1

Split into:       pure₁ = x + 0        -- enters e-graph
                  pure₂ = y * 1        -- enters e-graph
                  effect: print(pure₁)  -- stays outside

After e-graph:    pure₁ = x            -- optimized
                  pure₂ = y            -- optimized
                  effect: print(pure₁)  -- unchanged
```

**2. Flatten control flow into expressions.** Convert `if` statements to conditional expressions.

```
Source:     if (c) { x = a; } else { x = b; } return x;
IR:         let x = select(c, a, b)    -- now a pure tree node
```

**3. Eliminate mutable variables (SSA / let-bindings).** Each name refers to exactly one value.

```
Source:     x = 1; x = x + 2; return x
SSA:        x₀ = 1; x₁ = Add(x₀, 2); return x₁
```

**Lambda calculus is already e-graph-ready** — it's pure, tree-shaped, and has explicit data flow. That's why it's the canonical example language for e-graphs.

### The Practical Pipeline

```
Source code
  → Parse (AST)
  → Lower to pure IR (ANF/SSA, separate effects)
  → E-graph optimization (rewrite rules + extraction)
  → Lower to target (codegen or evaluate)
```

The e-graph doesn't replace your compiler pipeline — it sits in the middle, operating on the pure computational core while effects flow around it.

## When to Use This Library

**Good fit:**

- You have a **term language** (AST, IR, expression tree) and **equivalence-preserving rewrite rules**
- You want the **globally optimal** rewrite, not a greedy local one
- The search space is manageable (hundreds to low thousands of e-classes)
- You need **correctness guarantees** — every rewrite preserves equivalence by construction

**Concrete use cases:**

- Compiler middle-end optimizers
- Symbolic math simplifiers
- DSL compilers (SQL, shader, tensor)
- Theorem proving (equational reasoning)
- Educational tools for understanding program equivalences

**Not a good fit:**

- **No rewrite rules**: If your optimization doesn't involve term rewriting, e-graphs add unnecessary complexity
- **Huge search spaces**: Commutativity + associativity + distributivity can cause exponential growth. `NodeLimit` bounds memory, but results may be suboptimal
- **Runtime hot paths**: This is a compile-time/offline tool, not a runtime data structure
- **Side-effectful code**: E-graphs assert equality. Side effects break this — separate them first
- **Simple peephole rewrites**: If your rewrites are non-overlapping and order-independent, a single-pass rewriter is simpler and faster

## Core Concepts in Detail

### E-Nodes and E-Classes

An **e-node** is an operator with children that point to e-classes (not individual expressions):

```
Add(e-class-1, e-class-2)
```

An **e-class** is a set of e-nodes that have been proven equivalent:

```
e-class-3 = { Add(e-class-1, e-class-2), Var("x") }
```

Because children point to e-classes (which themselves contain multiple e-nodes), a single e-class implicitly represents all combinations — exponentially many expressions in compact space.

### The E-Graph Internals

The e-graph manages three data structures:

1. **Union-Find** — tracks which e-classes have been merged (with path compression and union by rank for near-O(1) operations)
2. **E-class map** — maps each canonical Id to its set of e-nodes
3. **Hashcons (memo)** — ensures structural sharing: adding the same e-node twice returns the same Id

**Key invariant: congruence closure.** If two e-nodes have the same operator and their children belong to the same e-classes, those e-nodes must also belong to the same e-class. The `rebuild` method restores this invariant after unions.

### Patterns and E-Matching

Patterns are expressions with variables (prefixed by `?`):

```
(Add ?x (Num:0))     -- matches any addition where the right child is zero
?x                   -- matches anything
(Mul ?x ?x)          -- matches self-multiplication (same ?x in both positions)
```

**E-matching** finds all ways a pattern matches within an e-graph. Unlike normal pattern matching (one expression, one result), e-matching searches across all equivalent expressions in every e-class, producing substitutions that map pattern variables to e-class Ids.

### Equality Saturation

The core optimization loop:

```
repeat until done:
  1. Search:  find all pattern matches for all rules
  2. Apply:   instantiate right-hand sides and union with matches
  3. Rebuild: restore congruence closure
  4. Check:   stop if saturated, or limits exceeded
```

**Saturated** means no rule produces a new equivalence — the e-graph has learned everything the rules can teach. Three stop conditions prevent runaway growth:

- `Saturated` — no new equivalences found (optimal result)
- `IterLimit` — maximum iterations reached (default: 30)
- `NodeLimit` — e-graph too large (default: 10,000 entries)

### Extraction

After saturation, **extraction** selects the lowest-cost expression from an e-class. The default cost function (`ast_size`) counts nodes — smaller is cheaper. Custom cost functions can model instruction latency, register pressure, or any domain-specific metric.

### E-Class Analysis

Analysis attaches domain-specific data to each e-class. The classic example is **constant folding**:

```
e-class = { Add(2, 3), Num(5) }   -- analysis data: Some(5)
e-class = { Var("x") }            -- analysis data: None
```

When analysis discovers that `Add(2, 3)` has value `5`, the `modify` hook adds `Num(5)` to the same e-class — constant folding happens automatically during saturation.

## Quick Start

### Step 1: Define Your Language

```moonbit
enum MyLang {
  Num(Int)
  Var(String)
  Add(Id, Id)
  Mul(Id, Id)
} derive(Eq, Hash)
```

### Step 2: Implement the Traits

Three traits are required:

**`ENode`** — how to access children:

```moonbit
impl ENode for MyLang with arity(self) {
  match self {
    Num(_) | Var(_) => 0
    Add(_, _) | Mul(_, _) => 2
  }
}

impl ENode for MyLang with child(self, i) {
  match self {
    Add(a, b) | Mul(a, b) => if i == 0 { a } else { b }
    _ => abort("no children")
  }
}

impl ENode for MyLang with map_children(self, f) {
  match self {
    Num(_) | Var(_) => self
    Add(a, b) => Add(f(a), f(b))
    Mul(a, b) => Mul(f(a), f(b))
  }
}
```

**`ENodeRepr`** — how to serialize/deserialize for pattern matching:

```moonbit
impl ENodeRepr for MyLang with op_tag(self) {
  match self { Num(_) => "Num"; Var(_) => "Var"; Add(..) => "Add"; Mul(..) => "Mul" }
}

impl ENodeRepr for MyLang with payload(self) {
  match self { Num(n) => Some(n.to_string()); Var(s) => Some(s); _ => None }
}

impl ENodeRepr for MyLang with from_op(tag, payload, children) {
  match (tag, payload, children.length()) {
    ("Num", Some(s), 0) => Some(Num(parse_int(s)))
    ("Var", Some(s), 0) => Some(Var(s))
    ("Add", None, 2) => Some(Add(children[0], children[1]))
    ("Mul", None, 2) => Some(Mul(children[0], children[1]))
    _ => None
  }
}
```

### Step 3: Build, Optimize, Extract

```moonbit
// Build the expression: (x + 0) * 1
let eg = EGraph::new()
let x = eg.add(Var("x"))
let zero = eg.add(Num(0))
let one = eg.add(Num(1))
let sum = eg.add(Add(x, zero))
let expr = eg.add(Mul(sum, one))

// Define rewrite rules
let rules = [
  rewrite("add-0", "(Add ?x (Num:0))", "?x"),    // x + 0 = x
  rewrite("mul-1", "(Mul ?x (Num:1))", "?x"),    // x * 1 = x
]

// Run equality saturation
let runner = Runner::new(eg, roots=[expr])
let reason = runner.run(rules)
// reason == Saturated

// Extract the cheapest equivalent expression
let (cost, result) = runner.egraph.extract(expr, ast_size())
// cost == 1, result == Var("x")
```

### Step 4 (Optional): Add Analysis for Constant Folding

```moonbit
let analysis = {
  make: fn(node, get_data) {
    match node {
      Num(n) => Some(n)
      Add(a, b) => match (get_data(a), get_data(b)) {
        (Some(x), Some(y)) => Some(x + y)
        _ => None
      }
      _ => None
    }
  },
  merge: fn(a, b) {
    match (a, b) { (Some(x), _) => Some(x); (_, Some(y)) => Some(y); _ => None }
  },
  modify: fn(eg, id) {
    match eg.get_data(id) {
      Some(n) => { eg.union(id, eg.add(Num(n))) |> ignore }
      None => ()
    }
  },
}

let eg = AnalyzedEGraph::new(analysis)
let two = eg.add(Num(2))
let three = eg.add(Num(3))
let sum = eg.add(Add(two, three))
// eg.get_data(sum) == Some(5) — automatically computed!
```

## API at a Glance

### Core Types

| Type | Purpose |
|------|---------|
| `Id` | E-class identifier (newtype over `Int`) |
| `EGraph[L]` | E-graph without analysis |
| `AnalyzedEGraph[L, D]` | E-graph with per-e-class analysis data |
| `Pat` | Pattern for matching (`Var` or `Node`) |
| `Subst` | Substitution mapping variable names to `Id`s |
| `Rewrite` | Rewrite rule (lhs pattern → rhs pattern) |
| `CostFn[L]` | Cost function for extraction |
| `RecExpr[L]` | Extracted expression (flat node array) |
| `Runner[L]` | Equality saturation driver |
| `StopReason` | Why the runner stopped (`Saturated`, `IterLimit`, `NodeLimit`) |
| `Analysis[L, D]` | Analysis callbacks (`make`, `merge`, `modify`) |

### Traits to Implement

| Trait | Methods | Purpose |
|-------|---------|---------|
| `ENode` | `arity`, `child`, `map_children` | Structural access to children |
| `ENodeRepr` | `op_tag`, `payload`, `from_op` | Serialization for pattern matching |
| `Hash + Eq` | (derive) | Hashcons deduplication |

### Key Operations

| Operation | Description |
|-----------|-------------|
| `EGraph::add(node)` | Add an e-node, returns its e-class Id |
| `EGraph::union(a, b)` | Assert two e-classes are equivalent |
| `EGraph::rebuild()` | Restore congruence closure |
| `EGraph::search(pat)` | Find all matches for a pattern |
| `EGraph::extract(id, cost_fn)` | Extract cheapest expression from an e-class |
| `Runner::run(rules)` | Run equality saturation |
| `AnalyzedEGraph::get_data(id)` | Look up analysis data for an e-class |

## Current Limitations

- **No multi-pattern rules**: each rule has one lhs pattern. Rules like "if A=B and C=D then E=F" require manual implementation
- **No dynamic rewrite generation**: rhs patterns are fixed at rule creation time. For computed rewrites (e.g., "evaluate this function call"), use the `modify` hook in analysis instead
- **No built-in Runner for AnalyzedEGraph**: you must call `search`/`apply_matches`/`rebuild` manually in a loop, or use the inner `EGraph` via `Runner`
- **No time limit**: MoonBit lacks a cross-platform clock API, so only iteration and node count limits are available
- **No visualization**: the library does not produce DOT/GraphViz output (yet)
- **Research-scale only**: optimized for correctness and clarity, not for production compilers with millions of nodes

## References

- **egg paper**: [Fast and Extensible Equality Saturation](https://arxiv.org/abs/2004.03082) (Willsey et al., 2021)
- **egg library**: [egraphs-good/egg](https://github.com/egraphs-good/egg) (Rust)
- **egglog**: [egraphs-good/egglog](https://github.com/egraphs-good/egglog) (Datalog-based)
- **E-graphs tutorial**: [e-graphs good](https://egraphs-good.github.io/)

## Further Reading

- [Implementation Report](implementation-report.md) — step-by-step build log with architecture and test coverage
- [Design Concerns](design-concerns.md) — 26 deferred decisions with rationale and revisit criteria
- [TODO](TODO.md) — future work: API improvements, performance optimizations, integrations
