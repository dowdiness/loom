# Debugging E-Graphs

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

When an e-graph produces unexpected results, the cause is almost always one of a small number of issues. This guide covers systematic techniques for diagnosing them.

## "My Rewrite Didn't Fire"

You defined a rule, ran saturation, but the expected equivalence never appeared. Work through these checks in order.

**Wrong `op_tag` (case-sensitive).** Pattern tags are compared with exact string equality. If your `op_tag` implementation returns `"add"` but your pattern says `"Add"`, no match will ever occur.

**Wrong arity.** The pattern `(Add ?x ?y ?z)` expects arity 3, but if `Add` has arity 2, the arity check in `ematch` rejects it silently. Count the children in both the pattern and the `arity` implementation.

**Payload mismatch.** The pattern `(Num:0)` requires `payload()` to return exactly `Some("0")`. If your implementation returns `Some("0.0")` or `Some(" 0")` (note the space), the match fails. Patterns compare payloads as literal strings — no numeric parsing.

**Already equivalent.** The rule matched and applied, but the lhs and rhs were already in the same e-class. `apply_matches` returns 0, and `Runner` reports `Saturated`. This is correct behavior — the e-graph already knows the equivalence.

**Condition blocked.** If the rule has a `condition` closure, it may be returning `false` for every match. See [Conditional Rewrites](conditional-rewrites.md) for details.

**Debugging technique:** Call `search` manually and inspect the results.

```moonbit
let matches = egraph.search(Pat::parse("(Add ?x (Num:0))"))
// Empty array → pattern didn't match. Check op_tag, arity, payload.
// Non-empty array → pattern matched. Check condition closure.
```

If `matches` is empty, the pattern itself is wrong. If `matches` is non-empty but `apply_matches` returns 0, either the condition blocked every match or lhs and rhs were already equivalent.

## "Wrong Result After Extraction"

Extraction returned an expression that is semantically incorrect or unexpectedly large.

**Invalid rewrite rule.** The most common cause. A rule that is not equivalence-preserving introduces false equivalences into the e-graph. Once a false equivalence exists, extraction may return any member of the polluted e-class. Review every rule by hand — both sides must mean the same thing for all inputs.

**Cost function issue.** Extraction found the cheapest expression according to your cost function, but "cheapest" does not match your intent. Try `ast_size()` first to verify correctness, then switch to a custom cost function. If `ast_size()` gives the right answer but your custom function does not, the bug is in the cost function.

**Unsaturated e-graph.** Check the `StopReason`:

```moonbit
let reason = runner.run(rules)
// Saturated    → all rewrites explored (optimal result)
// IterLimit    → stopped early, may have missed rewrites
// NodeLimit    → e-graph grew too large, may have missed rewrites
```

If the result is `IterLimit` or `NodeLimit`, the e-graph did not explore all possible rewrites. Increase limits or simplify rules to reduce growth.

**Missing rebuild.** If you called `union` without `rebuild` afterward, internal invariants are broken: the hashcons table is stale and congruence closure is incomplete. Subsequent `search` and `extract` calls may return incorrect results.

## Inspecting E-Graph State

When something goes wrong, inspect the e-graph directly.

**Check membership.** Are two expressions in the same e-class?

```moonbit
let same = egraph.find(a) == egraph.find(b)
// true → a and b are equivalent
// false → a and b are in different e-classes
```

**Count e-classes.** How large is the e-graph?

```moonbit
let num_classes = egraph.classes.size()
```

Note that `egraph.size()` returns Union-Find entries (which grow monotonically and include merged slots). `egraph.classes.size()` returns the number of live e-class entries in the map.

**Iterate over e-classes.** Print every e-class and its e-nodes:

```moonbit
for id, eclass in egraph.classes {
  let canonical = egraph.find(id)
  let nodes_str = eclass.nodes.map(fn(n) { n.op_name() }).join(", ")
  println("e-class \{canonical}: [\{nodes_str}]")
}
```

**Print a specific e-class.** Look up a known Id:

```moonbit
match egraph.classes.get(egraph.find(my_id)) {
  Some(eclass) =>
    for node in eclass.nodes {
      println("  \{node.op_name()} (arity \{node.arity()})")
    }
  None => println("e-class not found (stale Id?)")
}
```

## Common Mistakes

**Forgetting `rebuild()`.** After `union()`, always call `rebuild()` before `search()` or `extract()`. Without rebuild, the hashcons table is stale and congruence closure is not maintained. The `Runner` handles this automatically, but if you call `union` manually, you must rebuild.

```moonbit
egraph.union(a, b) |> ignore
egraph.rebuild()              // do not skip this
let matches = egraph.search(pattern)
```

**Bidirectional rules causing explosion.** Two rules `a + b -> b + a` and `b + a -> a + b` are equivalent to a single commutativity rule — but if expressed as two separate rules, both fire every iteration, creating redundant work and potentially excessive growth. Use a single bidirectional rule, or add a condition that imposes canonical ordering (see [Conditional Rewrites](conditional-rewrites.md)).

**Non-canonical Ids.** After `union`, old Ids may be stale. Always use `find(id)` to get the canonical representative before comparing Ids:

```moonbit
// Wrong: comparing raw Ids after union
let same = (a == b)

// Correct: comparing canonical Ids
let same = (egraph.find(a) == egraph.find(b))
```

**Payload format mismatch between `from_op` and `payload`.** The `from_op` function must be the exact inverse of `op_tag` and `payload`. If `payload` returns `Some("42")`, then `from_op("Num", Some("42"), [])` must return `Some(Num(42))`. If the formats diverge — for example, `payload` returns `"42"` but `from_op` expects `"42.0"` — then `instantiate` will call `abort("from_op failed")` when it tries to build the right-hand side of a rewrite.

## Testing Strategies

**Start small.** Test with 2-3 node expressions before scaling up. A single `Add(Num(1), Num(0))` is enough to verify that your `x + 0 -> x` rule works.

**Assert intermediate state.** After each `apply_rewrite` + `rebuild`, check that expected equivalences hold:

```moonbit
egraph.apply_rewrite(rule) |> ignore
egraph.rebuild()
assert_eq(egraph.find(sum), egraph.find(a))
```

Do not wait until the end of saturation to check — catch problems at the first iteration where they appear.

**Check StopReason.** `Saturated` means all rewrites were fully explored. `IterLimit` or `NodeLimit` may mean the result is suboptimal. In tests, assert the expected stop reason:

```moonbit
let reason = runner.run(rules)
assert_eq(reason, Saturated)
```

**Round-trip test for `ENodeRepr`.** For every variant of your language enum, verify that `from_op` is the inverse of `op_tag` + `payload` + `children`:

```moonbit
fn round_trip(node : MyLang) -> Bool {
  match MyLang::from_op(node.op_tag(), node.payload(), node.children()) {
    Some(reconstructed) => reconstructed == node
    None => false
  }
}

assert_true(round_trip(Num(42)))
assert_true(round_trip(Add(Id(0), Id(1))))
assert_true(round_trip(Mul(Id(2), Id(3))))
```

If any variant fails the round-trip, pattern instantiation will break for rules that produce that variant on the right-hand side.
