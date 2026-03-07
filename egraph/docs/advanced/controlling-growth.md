# Controlling E-Graph Growth

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

## Why E-Graphs Explode

An e-graph grows every time a rewrite rule adds a new e-node. Simplification rules like `x + 0 -> x` are gentle — they add at most one node per match and often merge e-classes, keeping the graph compact. Exploration rules are a different story.

Consider commutativity alone: `a + b = b + a`. Every `Add` node in the e-graph now spawns a mirror image. If you have 100 `Add` nodes, one iteration doubles them to 200.

Now add associativity: `(a + b) + c = a + (b + c)`. Each group of three terms generates a new grouping. Combined with commutativity, the two rules interact: commutativity permutes operands, associativity regroups them, and the next iteration permutes the new groupings.

Add distributivity — `a * (b + c) = a*b + a*c` — and the graph can grow faster than exponentially, because distributing creates new `Add` nodes that commutativity and associativity then explore.

**Concrete example.** Start with `(a + b) + (c + d)` using commutative + associative addition:

| Iteration | E-nodes | New groupings |
|-----------|---------|---------------|
| 0 | 7 | initial tree |
| 1 | 19 | commutativity mirrors + one associative regrouping |
| 2 | 48 | all 2-way groupings, both orderings |
| 3 | 91 | approaching all 14 binary trees over 4 leaves x orderings |
| 4 | 131 | near-saturation for this expression |

With 5 variables instead of 4, the numbers roughly triple. With 6, they grow by another factor. Commutativity and associativity together produce `n! * C(n)` equivalences for `n` leaves (where `C(n)` is the Catalan number), and the e-graph must represent all of them.

## Understanding the Growth Curve

Not all rule sets produce the same growth profile:

- **Simplification-only** (identity removal, constant folding): linear or sub-linear growth. Each rule fires once per matching site and typically reduces the number of distinct e-classes. The graph often saturates in a few iterations.

- **Exploration-only** (commutativity, associativity, distributivity): exponential growth. Each iteration produces nodes that feed the next iteration's matches. Saturation may be unreachable within practical limits.

- **Mixed**: the typical case. Growth is moderate in early iterations (simplification rules reduce what they can), then accelerates as exploration rules kick in. There is a **knee** in the growth curve — the iteration where exploration rules start dominating.

The practical goal is to let the simplification rules finish their work before the exploration rules blow up the graph. The mechanisms below all aim at this.

## NodeLimit and IterLimit

The `Runner` provides two resource bounds that prevent runaway growth:

**`node_limit`** caps the total number of e-node slots in the Union-Find. When `egraph.size()` exceeds this value, the runner stops and returns `NodeLimit`. This bounds memory consumption directly. The default is 10,000 — enough for small-to-medium expression optimization, too small for aggressive exploration over large terms.

**`iter_limit`** caps the number of search-apply-rebuild iterations. When the iteration counter reaches this value, the runner stops and returns `IterLimit`. This bounds wall-clock time (since each iteration's cost is roughly proportional to the graph size). The default is 30.

```moonbit
// Default limits: 30 iterations, 10,000 nodes
let runner = Runner::new(eg, roots=[expr])
let reason = runner.run(rules)

// Custom limits for a larger problem
let runner = Runner::new(eg, roots=[expr], iter_limit=50, node_limit=50_000)
let reason = runner.run(rules)
```

**How to choose values:**

1. Start with defaults.
2. Run your workload and inspect `StopReason`.
3. If the result is `Saturated`, your limits are fine — the graph found everything.
4. If the result is `NodeLimit` or `IterLimit`, check whether the extracted result is acceptable. If not, increase the limit that triggered and re-run.
5. If increasing limits doesn't improve the result (the same suboptimal expression keeps winning), the rule set may be fundamentally too explosive — see "When to Give Up" below.
6. If saturation is too slow, decrease limits. A good-enough result in 100ms beats a perfect result in 10 seconds for most use cases.

**Interpreting `StopReason`:**

| StopReason | Meaning | Action |
|------------|---------|--------|
| `Saturated` | All rules reached fixed point | Optimal result. No changes needed. |
| `IterLimit` | Ran out of iterations | Increase `iter_limit` or reduce rule set. |
| `NodeLimit` | Ran out of space | Increase `node_limit`, simplify rules, or use multi-pass scheduling. |

## Rule Scheduling: Multi-Pass Strategy

The equality saturation loop applies all rules in every iteration. When simplification rules and exploration rules run together, they compete: exploration rules create new nodes, which create new match sites for more exploration, drowning out the simplification rules that would have shrunk the graph.

**Solution: run in phases.** Apply simplification rules first with a tight iteration limit. Then apply exploration rules on the already-simplified graph.

```moonbit
// Phase 1: Simplification only (cheap, converges fast)
let simplify_rules = [
  rewrite("add-0",   "(Add ?x (Num:0))", "?x"),
  rewrite("mul-1",   "(Mul ?x (Num:1))", "?x"),
  rewrite("mul-0",   "(Mul ?x (Num:0))", "Num:0"),
  rewrite("add-self", "(Add ?x ?x)",     "(Mul ?x (Num:2))"),
]

let runner = Runner::new(eg, roots=[expr], iter_limit=10, node_limit=10_000)
let _ = runner.run(simplify_rules)

// Phase 2: Exploration (expensive, bounded tightly)
let explore_rules = [
  rewrite("comm-add", "(Add ?x ?y)", "(Add ?y ?x)"),
  rewrite("assoc-add", "(Add (Add ?x ?y) ?z)", "(Add ?x (Add ?y ?z))"),
  rewrite("dist", "(Mul ?x (Add ?y ?z))", "(Add (Mul ?x ?y) (Mul ?x ?z))"),
]

let runner2 = Runner::new(runner.egraph, roots=[expr], iter_limit=5, node_limit=20_000)
let reason = runner2.run(explore_rules)
```

Notice that `runner2` reuses the same `egraph` from the first pass. The simplification rules have already normalized what they can, so the exploration rules start from a smaller base.

You can chain as many phases as your domain needs. A common three-phase pattern:

1. **Canonicalize** — orient expressions into a normal form (small `iter_limit`)
2. **Explore** — apply commutativity/associativity/distributivity (tight `node_limit`)
3. **Clean up** — re-run simplification rules to normalize anything the exploration created

## Rule Design Principles

The way you write rules has a direct impact on growth rate.

**Orient rules when possible.** A bidirectional rule `a + b = b + a` must be applied in both directions. But if one direction is always preferred (e.g., canonical ordering by variable name), write a one-directional rule. The e-graph will still find equivalences through other paths, but it won't eagerly double the `Add` node count.

```
// Bidirectional (doubles Add nodes each iteration)
rewrite("comm-add", "(Add ?x ?y)", "(Add ?y ?x)")

// Oriented (only fires when not already canonical)
// Requires a conditional rewrite to check ordering — see conditional-rewrites.md
```

**Avoid redundant rule pairs.** `a + b -> b + a` and `b + a -> a + b` are the same rule (commutativity is its own inverse). Including both doubles the work without adding any new equivalences. One direction suffices — the e-graph will discover the reverse through the existing rule.

**Combine rules that co-occur.** If you always apply `x + 0 -> x` and `0 + x -> x` together, merge them or apply commutativity first so only one identity rule is needed. Fewer rules mean fewer matches per iteration.

**Minimize exploration rule arity.** A rule with 3 pattern variables generates more matches than one with 2. If a rule can be split into smaller rules that fire independently, do so — the smaller rules generate fewer intermediate nodes.

## Analysis-Based Pruning

E-class analysis provides a principled mechanism for skipping unnecessary rewrites. If analysis data tells you an e-class is already in its simplest form, there is no reason to apply exploration rules to it.

**Example: skip arithmetic identities on constants.** Suppose your analysis computes `Int?` — `Some(n)` for known constants, `None` otherwise. If an e-class already has a known constant value, applying `Add ?x (Num:0) -> ?x` to it is pointless — it is already a literal.

Implement this via a conditional rewrite that checks analysis data:

```moonbit
// Only apply the rule if ?x is NOT a known constant
let add_zero_rule = {
  name: "add-0",
  lhs: Pat::parse("(Add ?x (Num:0))"),
  rhs: Pat::parse("?x"),
  condition: Some(fn(subst) {
    // Lookup analysis data for ?x; skip if already a constant
    match subst["x"] {
      Some(id) => analyzed_eg.get_data(id).is_empty()
      None => true
    }
  }),
}
```

This pattern is especially valuable when constant folding has already reduced large subexpressions to literals. Without the guard, exploration rules would still permute and regroup those literals, creating many nodes that all evaluate to the same constant.

**General principle:** any analysis that can classify an e-class as "done" (fully simplified, known constant, canonical form) should be paired with conditions that skip exploration rules on those classes.

## When to Give Up

Some rule sets are fundamentally incompatible with equality saturation at scale. Recognize the signs:

- **`NodeLimit` hit every run**, even at 100,000+ nodes.
- **Increasing limits doesn't improve the extracted result** — the graph grows but the best expression stays the same.
- **Saturation time exceeds seconds** for expressions that should be simple.
- **The extracted cost barely changes** between iteration 5 and iteration 50.

When these signs appear, consider alternatives:

**Greedy + targeted.** Use a single-pass greedy rewriter for cheap, obvious simplifications (identity removal, constant folding). Then use the e-graph only for the hard cases — subexpressions where rule interactions actually matter.

**Domain-specific scheduling.** Instead of general commutativity/associativity, write domain-specific rules that capture the optimization you actually want. For example, instead of "reorder any addition", write "merge adjacent constants" — same effect, far fewer intermediate nodes.

**Bounded exploration.** Limit exploration rules to specific subtree depths or expression sizes using conditional rewrites. Only explore subexpressions with fewer than N nodes.

**egglog.** For rule sets that are inherently relational (many variables, complex join patterns), consider a Datalog-based approach like egglog, which can handle larger rule sets more efficiently through bottom-up evaluation. This library's pattern-matching approach works well for tree-shaped rules but struggles with heavily relational ones.

The e-graph is a powerful tool, but it is not the only tool. The best optimizers combine multiple strategies, using the e-graph where its strengths shine and simpler techniques everywhere else.
