# Conditional Rewrites

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

## Motivation

Some rewrites are only valid under certain conditions. Consider the rule `x / 2 → x >> 1` (replace division by two with a right shift). This is correct for non-negative integers, but produces wrong results for negative values or floats. Applying it unconditionally would introduce false equivalences into the e-graph — a violation of the foundational guarantee that every e-class member represents the same value.

The introduction listed this rule as an example of an **invalid** unconditional rewrite. But the underlying equivalence is real — it just has a restricted domain. Conditional rewrites let you express exactly that: "apply this rule, but only when a predicate holds."

## The API

The `Rewrite` struct carries an optional `condition` field:

```moonbit
priv struct Rewrite {
  name : String
  lhs : Pat
  rhs : Pat
  condition : ((Subst) -> Bool)?
}
```

When `condition` is `None`, the rule fires unconditionally (the common case). When `condition` is `Some(predicate)`, each match is tested before the right-hand side is instantiated. The check happens inside `apply_matches`:

```moonbit
match rule.condition {
  Some(cond) => if not(cond(subst)) { continue }
  None => ()
}
```

If the predicate returns `false`, that particular match is skipped — the rule does not fire, no union is performed, and no false equivalence is introduced. Other matches of the same rule (with different substitutions) are tested independently.

The convenience constructor `rewrite(name, lhs, rhs)` always sets `condition` to `None`. To create a conditional rewrite, construct the struct directly:

```moonbit
let rw : Rewrite = {
  name: "my-conditional-rule",
  lhs: Pat::parse("(Div ?x (Num:2))"),
  rhs: Pat::parse("(Shr ?x (Num:1))"),
  condition: Some(fn(subst) {
    // ... check whether ?x is non-negative ...
  }),
}
```

## Example: Guarded Arithmetic

Suppose your language includes `Div` and `Shr` (right shift) operators, and you use constant-folding analysis to track known integer values. You want the rule:

```
Div(?x, Num:2) → Shr(?x, Num:1)
```

but only when `?x` is known to be non-negative.

The condition closure captures a reference to the `AnalyzedEGraph` so it can inspect analysis data:

```moonbit
// `eg` is an AnalyzedEGraph[MyLang, Int?] with constant-folding analysis.
// Analysis data is Some(n) when the e-class has a known constant value,
// None otherwise.

let div_to_shr : Rewrite = {
  name: "div2-to-shr1",
  lhs: Pat::parse("(Div ?x (Num:2))"),
  rhs: Pat::parse("(Shr ?x (Num:1))"),
  condition: Some(fn(subst) {
    match subst["x"] {
      Some(x_id) =>
        match eg.get_data(x_id) {
          Some(n) => n >= 0   // known non-negative constant
          None => false       // unknown value — don't risk it
        }
      None => false
    }
  }),
}
```

When `?x` binds to an e-class whose analysis data is `Some(7)`, the condition returns `true` and the shift rewrite fires. When `?x` is a symbolic variable with no constant data, the condition returns `false` and the original `Div` node is left alone.

## Example: Preventing Infinite Loops

Commutativity rules like `a + b → b + a` are valid equivalences, but applying them naively creates an infinite loop: `Add(x, y)` produces `Add(y, x)`, which matches again and produces `Add(x, y)`, and so on. In practice the e-graph handles this gracefully — both sides end up in the same e-class after one application, so subsequent matches produce unions that are already present, and saturation terminates.

But in more complex scenarios (commutativity combined with associativity and other rules), the interaction can cause significant e-graph growth before convergence. A conditional rewrite can impose a canonical ordering to cut this short:

```moonbit
let comm_canonical : Rewrite = {
  name: "add-comm-canonical",
  lhs: Pat::parse("(Add ?a ?b)"),
  rhs: Pat::parse("(Add ?b ?a)"),
  condition: Some(fn(subst) {
    match (subst["a"], subst["b"]) {
      (Some(Id(a)), Some(Id(b))) => a > b  // only fire if out of canonical order
      _ => false
    }
  }),
}
```

This rule only fires when the left child's e-class Id is numerically greater than the right child's. Once `Add(?a, ?b)` and `Add(?b, ?a)` are in the same e-class, subsequent matches where `a < b` are suppressed, preventing redundant work. The equivalence is still recorded — just with fewer wasted iterations.

## Equivalence-Preservation with Conditions

Conditional rewrites do not weaken the e-graph's correctness guarantee. They strengthen it.

An unconditional rule asserts: "for all possible values, `lhs = rhs`." If that assertion is false for some inputs, the e-graph silently records incorrect equivalences. There is no runtime check — the damage is done at rewrite time.

A conditional rule asserts: "for values where `condition` holds, `lhs = rhs`." The condition restricts the domain to cases where the equivalence is genuine. Outside that domain, the rule simply does not fire. No union is performed, so no false equivalence is introduced.

This means:

- **With condition:** The rule fires less often, but every firing is correct. The e-graph remains sound.
- **Without condition (when the equivalence is partial):** The rule fires on inputs where `lhs != rhs`, polluting the e-graph with false equivalences. Extraction may return incorrect results.

The tradeoff is completeness, not correctness. A conservative condition may miss valid opportunities (e.g., refusing `div2-to-shr1` for a variable that happens to be non-negative but whose analysis data is `None`). The e-graph stays correct; it just fails to discover some optimizations.

## Limitations and Workarounds

### The condition only sees `Subst`

The `condition` function receives a `Subst` — a `Map[String, Id]` mapping pattern variable names to e-class Ids. It does not directly receive analysis data, the e-graph, or the matched e-nodes.

To inspect analysis data or e-graph structure, **capture the e-graph reference in the closure**:

```moonbit
// Capture `eg` (an AnalyzedEGraph) by reference in the closure.
let rw : Rewrite = {
  name: "guarded-rule",
  lhs: Pat::parse("(SomeOp ?x)"),
  rhs: Pat::parse("(Optimized ?x)"),
  condition: Some(fn(subst) {
    match subst["x"] {
      Some(id) => {
        let data = eg.get_data(id)
        // ... inspect data ...
      }
      None => false
    }
  }),
}
```

This is the standard pattern. The closure closes over the `AnalyzedEGraph`, giving the condition full access to analysis data, `find`, and any other e-graph queries.

### No anti-patterns

You cannot express "apply this rule only if e-class X does **not** contain pattern Y." The condition function receives variable bindings (Ids), not structural information about what other e-nodes exist in a class. To approximate anti-pattern behavior, you would need to manually search for the unwanted pattern inside the condition closure by iterating over the e-class's nodes — which is possible but verbose and fragile, since the e-class contents change as saturation proceeds.

### Condition evaluation timing

Conditions are evaluated during the **write phase** of equality saturation, after all matches have been collected in the read phase. This means the condition sees the e-graph state at the time of application, not at the time of matching. In practice, this rarely matters — but if your condition depends on e-graph structure that changes between the read and write phases (e.g., whether two Ids are in the same e-class), be aware that the answer may differ from what it was when the match was found.
