# Analysis-Driven Rewrites

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

## What Analysis Adds

Pattern-based rewrites are *structural* — they match syntax. A rule like `(Add ?x (Num:0)) => ?x` fires whenever the e-graph contains an `Add` node whose second child is `Num(0)`. It knows nothing about the *meaning* of `?x`.

Analysis adds *semantic* information to each e-class:

- "This e-class represents the constant value 5."
- "This e-class has type `Int`."
- "Evaluating this subexpression costs 3 cycles."

This semantic data can drive rewrites that no pattern could express. Constant folding, for instance, needs to *compute* `2 + 3 = 5` — there is no finite set of patterns that covers all possible arithmetic.

## The Analysis Interface

The library represents analysis as a record of three callbacks:

```moonbit
priv struct Analysis[L, D] {
  make : (L, (Id) -> D) -> D
  merge : (D, D) -> D
  modify : (AnalyzedEGraph[L, D], Id) -> Unit
}
```

- **`make(node, get_data)`** — Compute the analysis datum for a single e-node. The `get_data` function looks up the data of child e-classes.
- **`merge(a, b)`** — Combine data when two e-classes are unioned. Must be commutative and associative (it forms a join-semilattice).
- **`modify(egraph, id)`** — Post-merge hook. May inspect the data for e-class `id` and react by calling `egraph.add()` or `egraph.union()`.

The analysis is stored in `AnalyzedEGraph[L, D]`, which wraps a plain `EGraph[L]` and maintains a parallel `data : Map[Id, D]`.

## Pattern: Constant Folding (Detailed Walkthrough)

Constant folding is the canonical analysis. The data type is `Int?` — `Some(n)` if the e-class is known to equal the integer `n`, `None` otherwise.

### The three callbacks

```moonbit
fn constant_fold_analysis() -> Analysis[LambdaLang, Int?] {
  {
    make: fn(node, get_data) {
      match node {
        LNum(n) => Some(n)
        LAdd(a, b) =>
          match (get_data(a), get_data(b)) {
            (Some(x), Some(y)) => Some(x + y)
            _ => None
          }
        LMul(a, b) =>
          match (get_data(a), get_data(b)) {
            (Some(x), Some(y)) => Some(x * y)
            _ => None
          }
        _ => None
      }
    },
    merge: fn(a, b) {
      match (a, b) {
        (Some(x), _) => Some(x)
        (_, Some(y)) => Some(y)
        _ => None
      }
    },
    modify: fn(egraph, id) {
      match egraph.get_data(id) {
        Some(n) => {
          let num_id = egraph.add(LNum(n))
          egraph.union(id, num_id) |> ignore
        }
        None => ()
      }
    },
  }
}
```

**`make`**: A `LNum(n)` node carries its value directly. An `LAdd(a, b)` node is constant only if both children are — then the result is their sum. Variables, lambdas, and applications produce `None`.

**`merge`**: When two e-classes merge, if either has a known constant, the merged class inherits it. (If both have constants, they must agree — the e-graph only merges truly equivalent classes.)

**`modify`**: If the analysis discovers that an e-class has value `n`, the hook adds a `LNum(n)` node and unions it into the class. This makes the constant explicit in the e-graph, so extraction can find it.

### Tracing through `(2 + 3) * 4`

Here is every step the analyzed e-graph performs:

```
1. eg.add(LNum(2))
   → Creates e-class 0. make(LNum(2), _) = Some(2).
   → modify: data is Some(2), add LNum(2) — already exists, no-op.

2. eg.add(LNum(3))
   → Creates e-class 1. make(LNum(3), _) = Some(3).
   → modify: no-op (LNum(3) already in class 1).

3. eg.add(LAdd(Id(0), Id(1)))
   → Creates e-class 2. make(LAdd(0, 1), get_data):
     get_data(0) = Some(2), get_data(1) = Some(3) → Some(5).
   → modify: data is Some(5).
     Calls eg.add(LNum(5)) → creates e-class 3.
     Calls eg.union(2, 3) → merges "Add(2,3)" class with "Num(5)" class.
     merge(Some(5), Some(5)) = Some(5). Winner is e-class 2.

4. eg.add(LNum(4))
   → Creates e-class 4. make(LNum(4), _) = Some(4).

5. eg.add(LMul(Id(2), Id(4)))
   → Creates e-class 5. make(LMul(2, 4), get_data):
     get_data(2) = Some(5), get_data(4) = Some(4) → Some(20).
   → modify: data is Some(20).
     Calls eg.add(LNum(20)) → creates e-class 6.
     Calls eg.union(5, 6) → merges. Data = Some(20).

6. eg.rebuild()
   → Canonicalizes data, recomputes, runs modify on all classes.
   → No new unions — fixed point reached.
```

After rebuild, e-class 5 contains `{Mul(Add(2,3), 4), Num(20)}`. Extraction with `ast_size()` picks `Num(20)` (cost 1) over the original expression (cost 5).

## Pattern: Constant Propagation

Constant folding handles expressions built entirely from literals. Constant *propagation* goes further: when a variable is bound to a known constant, that knowledge flows through the body.

Consider `let x = 5 in x + 3`. The e-graph contains:

```
e-class 0: { LNum(5) }         -- data: Some(5)
e-class 1: { LVar("x") }      -- data: None
e-class 2: { LNum(3) }         -- data: Some(3)
e-class 3: { LAdd(1, 2) }      -- data: None (x is unknown)
e-class 4: { LLet("x", 0, 3) } -- the let-binding
```

Without propagation, `LAdd(1, 2)` stays at `None` because `LVar("x")` has no constant data. To propagate, the analysis must track variable bindings:

- `D` changes from `Int?` to a richer type: `{ value: Int?, env: Map[String, Int] }`.
- `make` for `LLet("x", val, body)`: if `get_data(val).value` is `Some(n)`, record `x = n` in the environment.
- `make` for `LVar("x")`: look up `x` in the environment.
- `modify`: if a `LVar("x")` class gains a known value, union it with `LNum(n)`.

This is more complex than folding because the analysis data must carry *context* (which variables are bound to what). In practice, you may choose to implement propagation as a separate pass rather than inside e-class analysis.

## Pattern: Type Inference

Analysis data can carry type information. Define a type enum:

```moonbit
enum Type {
  TInt
  TBool
  TFun(Type, Type)
  TUnknown
  TError
}
```

The three callbacks:

- **`make`**: `LNum(_) => TInt`. `LAdd(a, b)` checks both children — if both are `TInt`, the result is `TInt`; otherwise `TError`. `LLam("x", body)` produces `TFun(TUnknown, get_data(body))`.
- **`merge`**: Unification. `TUnknown` unifies with anything (takes the other type). Two concrete types unify only if structurally equal; otherwise produce `TError`.
- **`modify`**: Type-directed rewrites. If an `LAdd` node is in an e-class with type `TError`, the hook could add an `Error("type mismatch")` node to that class, making the type error explicit and extractable.

This pattern turns the e-graph into a type-checking engine: as rewrites explore equivalent programs, the analysis propagates types and flags errors.

## Pattern: Cost Annotations

Use `D = Int` representing estimated evaluation cost:

- **`make`**: `LNum(_) => 0` (free). `LAdd(a, b) => get_data(a) + get_data(b) + 1`. `LMul(a, b) => get_data(a) + get_data(b) + 3` (multiplication is more expensive).
- **`merge`**: `min(a, b)` — the cheapest known cost dominates.
- **`modify`**: If an e-class already has cost 0 (it is a literal), skip applying exploration rewrites (like commutativity) to it. This is implemented by checking cost in a conditional rewrite's closure.

Cost annotations let you prune the search space: the modify hook can avoid expanding already-optimal subexpressions, reducing e-graph growth without losing quality.

## The `modify` Hook as a Rewrite Engine

The `modify` callback has access to the full `AnalyzedEGraph` — it can call `add()` and `union()` freely. This makes it strictly more powerful than pattern-based rewrites for certain tasks:

- **Computed results**: Pattern rewrites can only rearrange existing structure. `modify` can *compute* new values (like `2 + 3 = 5`) that no finite rule set covers.
- **Data-dependent decisions**: `modify` can inspect analysis data from any e-class and react accordingly. A pattern rewrite only sees structural matches.
- **Multi-step transformations**: `modify` can add a chain of nodes in one call — for example, normalizing a polynomial representation.

The trade-off is clarity:

| Approach | Strengths | Weaknesses |
|----------|-----------|------------|
| Pattern rewrites | Declarative, inspectable, easy to reason about correctness | Limited to structural matching |
| `modify` hooks | Can compute arbitrary results, access semantic data | Opaque, harder to verify, risk of non-termination |

Use pattern rewrites for structural simplifications (`x + 0 => x`). Use `modify` for semantic computations (constant folding, type propagation).

## Pitfall: `modify` Loops

The `modify` hook runs during `add()`, `union()`, and `rebuild()`. If `modify` adds new nodes or unions, those changes can trigger further rebuilds, which call `modify` again. The library handles this with a fixed-point loop in `AnalyzedEGraph::rebuild()`:

```
rebuild:
  loop:
    egraph.rebuild()          -- canonicalize, detect congruences
    canonicalize_data()       -- merge stale data entries
    recompute_data()          -- re-run make on all nodes
    modify on all classes     -- may add nodes / union classes
    if no pending unions: break
```

This converges when `modify` stops producing new unions. In the constant folding example, `modify` adds `LNum(5)` and unions it with the `Add(2,3)` class. On the next iteration, `modify` fires again for that class — but `LNum(5)` is already present, `add()` returns the existing Id, `union()` finds they are already merged, and no new pending work is created. The loop terminates.

**Termination requirement:** `modify` must eventually stop adding new equivalences. Specifically:

- If `modify` only adds nodes that are already in the e-class (or unions classes that are already merged), it is safe.
- If `modify` creates genuinely new nodes on every call (e.g., `modify` always increments a counter and adds `LNum(counter)`), the e-graph grows without bound and `rebuild` never terminates.

A safe pattern: always check whether the node already exists before adding it. The `add()` method handles this via hashconsing — adding a duplicate node returns the existing Id without creating a new e-class. Combined with `union()` being a no-op on already-merged classes, well-designed `modify` hooks naturally reach a fixed point.
