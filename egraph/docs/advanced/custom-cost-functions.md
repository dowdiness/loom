# Custom Cost Functions

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

## How Extraction Works

After equality saturation fills the e-graph with equivalent expressions, **extraction** selects the best one. The algorithm is bottom-up fixed-point iteration:

1. For each e-class, examine every e-node it contains.
2. Compute the cost of each e-node using a `CostFn` — a function that receives the node and a lookup for child costs.
3. Track the cheapest node per e-class.
4. Repeat until no cost improves (fixed point). Acyclic e-graphs converge in one pass; cyclic ones (e.g., from commutativity) may need several.
5. Reconstruct the optimal expression tree by following best-node choices from the root.

The cost function type is:

```moonbit
struct CostFn[L]((L, (Id) -> Int) -> Int)
```

The inner function receives two arguments: an e-node of type `L`, and a child-cost lookup `(Id) -> Int` that returns the best known cost for any child e-class. It returns the total cost for that node.

## The Default: `ast_size`

The built-in `ast_size` cost function counts 1 per node plus the sum of all children's costs. It extracts the structurally simplest expression.

```moonbit
fn[L : ENode] ast_size() -> CostFn[L] {
  CostFn(fn(node, child_cost) {
    let mut cost = 1
    for i = 0; i < node.arity(); i = i + 1 {
      cost = cost + child_cost(node.child(i))
    }
    cost
  })
}
```

This is the right choice when "simplest" means "fewest nodes" — algebraic simplification, dead code elimination, or any setting where you want the most compact representation.

## Example: Instruction Latency

Different operations have different execution costs on real hardware. A cost function can model this by assigning per-operator weights.

Suppose your language includes `Add`, `Mul`, `Div`, and `Shr` (right shift). On a typical CPU, addition and shifts are single-cycle, multiplication is multi-cycle, and division is expensive:

```moonbit
fn instruction_latency() -> CostFn[MyLang] {
  CostFn(fn(node, child_cost) {
    let op_cost = match node.op_tag() {
      "Add" => 1
      "Mul" => 3
      "Div" => 10
      "Shr" => 1
      _ => 1  // leaves (Num, Var) cost 1
    }
    let mut total = op_cost
    for i = 0; i < node.arity(); i = i + 1 {
      total = total + child_cost(node.child(i))
    }
    total
  })
}
```

With this cost function, the e-graph prefers `Add(?x, ?x)` (cost 1 + 1 + 1 = 3) over `Mul(?x, Num:2)` (cost 3 + 1 + 1 = 5) for doubling a value. Under `ast_size`, both would tie at cost 3 — the latency model breaks the tie in favor of the cheaper instruction.

## Example: Register Pressure (Sethi-Ullman)

Deep expression trees require more registers to evaluate than balanced ones. A Sethi-Ullman-style cost function models this by tracking depth rather than summing sizes:

```moonbit
fn register_pressure() -> CostFn[MyLang] {
  CostFn(fn(node, child_cost) {
    if node.arity() == 0 {
      1  // leaf: needs one register
    } else {
      let mut max_child = 0
      for i = 0; i < node.arity(); i = i + 1 {
        let c = child_cost(node.child(i))
        if c > max_child {
          max_child = c
        }
      }
      max_child + 1
    }
  })
}
```

This prefers balanced trees over deep chains. Given the equivalences `(a + b) + (c + d)` and `((a + b) + c) + d` (via associativity), the balanced form has depth 3 while the chain has depth 4. Extraction under `register_pressure` picks the balanced form.

## Example: Weighted Code Size vs Speed

When optimizing for both code size and execution speed, combine the two metrics with tunable weights:

```moonbit
fn weighted_cost(alpha : Int, beta : Int) -> CostFn[MyLang] {
  CostFn(fn(node, child_cost) {
    let size = 1  // every node contributes 1 to code size
    let latency = match node.op_tag() {
      "Mul" => 3
      "Div" => 10
      _ => 1
    }
    let mut children_cost = 0
    for i = 0; i < node.arity(); i = i + 1 {
      children_cost = children_cost + child_cost(node.child(i))
    }
    alpha * size + beta * latency + children_cost
  })
}
```

- When `alpha >> beta`: extraction prefers small code — suitable for embedded systems with tight memory.
- When `beta >> alpha`: extraction prefers fast code — suitable for HPC inner loops.
- `weighted_cost(1, 0)` degenerates to `ast_size`. `weighted_cost(0, 1)` degenerates to pure latency.

## Requirements for Correctness

The extraction algorithm assumes certain properties of the cost function. Violating them produces wrong results or non-termination.

### Non-negative costs

Every call to the cost function must return a value >= 0. Negative costs break the fixed-point iteration: a node could appear cheaper than its children, causing the algorithm to cycle between competing "improvements" without converging.

### Monotonicity

A parent's cost should be strictly greater than each child's cost. Formally: `cost(node) > child_cost(child_i)` for every child. If a parent is cheaper than a child, the fixed-point loop may never stabilize — each pass finds a "better" cost by routing through the cheaper parent, triggering another pass.

In practice, `cost(node) = op_cost + sum(child_costs)` with `op_cost >= 1` satisfies monotonicity automatically.

### Finite sentinel for unreachable classes

E-classes with no reachable e-node (e.g., after partial extraction) receive the sentinel value `1_000_000_000` from the child-cost lookup. Your cost function does not need to handle this explicitly — just be aware that if you see this value in debugging, it means an e-class had no extractable representative.

Do not return actual infinity or `@int.max_value` from your cost function. Arithmetic on such values (e.g., adding child costs) would overflow, producing negative numbers that violate the non-negativity requirement.

### What happens when violated

| Violation | Symptom |
|-----------|---------|
| Negative cost | Extraction loop does not converge; may return an arbitrary expression |
| Non-monotonic (parent < child) | Extraction loop does not converge; costs keep changing each pass |
| Overflow to negative | Same as negative cost — silent incorrect results |

## Interaction with Analysis

Cost functions can use e-class analysis data by capturing the `AnalyzedEGraph` in a closure. This enables cost models that depend on semantic properties, not just syntactic structure.

The classic example: if constant-folding analysis has determined that an e-class evaluates to a known integer, the cheapest representation is always a single `Num` literal — regardless of how complex the original expression was.

```moonbit
fn analysis_aware_cost(eg : AnalyzedEGraph[MyLang, Int?]) -> CostFn[MyLang] {
  CostFn(fn(node, child_cost) {
    // If this node is a Num and its e-class has a known constant,
    // it costs just 1 — the constant-folded literal.
    match node {
      Num(_) => 1
      _ => {
        let mut total = match node.op_tag() {
          "Mul" => 3
          "Div" => 10
          _ => 1
        }
        for i = 0; i < node.arity(); i = i + 1 {
          let child_id = node.child(i)
          // If the child e-class has a known constant, its best
          // cost is 1 (a Num literal), even if child_cost reports
          // a higher value from a non-constant e-node.
          let c = match eg.get_data(child_id) {
            Some(_) => 1
            None => child_cost(child_id)
          }
          total = total + c
        }
        total
      }
    }
  })
}
```

With this cost function, an expression like `Add(Mul(Num(2), Num(3)), Var("x"))` where the `Mul` e-class has been constant-folded to `Some(6)` would score the `Mul` child at cost 1 instead of cost 5 — because extraction will ultimately pick the `Num(6)` literal from that e-class.

This pattern works because `extract` delegates to the inner e-graph, and the closure captures the analysis data. The cost function runs during extraction, after saturation is complete, so the analysis data is stable.
