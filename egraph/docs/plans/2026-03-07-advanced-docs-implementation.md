# Advanced E-Graph Documentation Suite — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create 8 documents (1 index + 7 topics) in `docs/advanced/` covering advanced e-graph usage.

**Architecture:** Each document is standalone markdown, assumes reader has read `introduction.md`. Mixes conceptual explanation with MoonBit code examples using the library's actual API (`EGraph`, `ENode`, `ENodeRepr`, `CostFn`, `Analysis`, etc.).

**Tech Stack:** Markdown documentation, MoonBit code examples (not compiled — illustrative only).

---

### Task 1: Create index and directory

**Files:**
- Create: `egraph/docs/advanced/README.md`

**Step 1: Create the directory and index file**

```markdown
# Advanced E-Graph Topics

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

These documents cover advanced usage patterns, design guidance, and troubleshooting for the e-graph library.

## Topics

| Document | Summary |
|----------|---------|
| [E-Graph-Ready IR](egraph-ready-ir.md) | Transforming source languages into pure, tree-shaped IR suitable for e-graph optimization |
| [Conditional Rewrites](conditional-rewrites.md) | Rewrite rules that only fire when a predicate holds |
| [Analysis-Driven Rewrites](analysis-driven-rewrites.md) | Using e-class analysis (constant folding, type inference) to drive optimization |
| [Controlling E-Graph Growth](controlling-growth.md) | Strategies for managing combinatorial explosion |
| [Custom Cost Functions](custom-cost-functions.md) | Designing extraction cost functions beyond `ast_size` |
| [Multi-Language Patterns](multi-language-patterns.md) | Designing `ENode`/`ENodeRepr` for SQL, tensors, lambda calculus, and other domains |
| [Debugging E-Graphs](debugging-egraphs.md) | Troubleshooting rewrites, inspecting state, and common mistakes |
```

**Step 2: Commit**

```bash
git add egraph/docs/advanced/README.md
git commit -m "docs: add advanced topics index"
```

---

### Task 2: Write egraph-ready-ir.md

**Files:**
- Create: `egraph/docs/advanced/egraph-ready-ir.md`

**Content outline (~250 lines):**

1. **Prerequisite link** — one line pointing to `../introduction.md`
2. **Why source languages aren't e-graph-ready** — side effects, mutable state, control flow, sequential ordering. Brief recap of the 4 properties (pure, tree-shaped, explicit data flow, fixed arity).
3. **Transformation 1: Separating Pure from Effectful**
   - Theory: pure vs effectful computation. The key insight — side effects impose ordering, but pure code is order-independent (which is exactly what e-graphs exploit).
   - Example: extend MyLang with `Print(Id)` and `Seq(Id, Id)`. Show a source program, then the separated form where pure subexpressions enter the e-graph and the effect spine stays outside.
   - Monadic / algebraic effect perspective (brief — 2-3 sentences, not a full tutorial).
   - MoonBit sketch: an `EffectfulLang` enum with `Pure(Id)` wrapping optimizable subexpressions.
4. **Transformation 2: Flattening Control Flow**
   - Theory: statements vs expressions. If-statements become `Select(cond, then, else)` nodes. Loops become recursive let-bindings or fixed-point operators.
   - Example: `if (c) { a } else { b }` → `Select(c, a, b)` as an e-node.
   - Why this matters: `Select` can participate in rewrites like `Select(true, a, b) → a`.
   - MoonBit sketch: adding `Select(Id, Id, Id)` and `Bool(Bool)` to MyLang.
5. **Transformation 3: SSA / Let-Binding Form**
   - Theory: mutable variables → unique names. SSA (static single assignment) ensures each variable is defined exactly once. Phi-functions at control flow joins (or let-bindings in functional IR).
   - Example: `x = 1; x = x + 2; return x` → `x₀ = 1; x₁ = Add(x₀, Num(2)); return x₁`. Each binding = one `egraph.add()` call.
   - Connection to lambda calculus: let-bindings are syntactic sugar for lambda application. Lambda calculus is SSA by default.
6. **The Complete Pipeline**
   - Diagram: `Source → Parse → Lower (effects, control flow, SSA) → E-graph (add, rules, saturate, extract) → Codegen/Eval`
   - Which transformations are mandatory vs optional. Lambda calculus needs none (already pure + tree-shaped). An imperative language needs all three.
   - Practical advice: start with the smallest IR that captures your domain. Don't model what you won't optimize.
7. **Lambda Calculus: Already E-Graph-Ready**
   - Why `LambdaLang` works directly: pure, tree-shaped, explicit bindings, fixed arity per variant.
   - The one caveat: variable capture during beta-reduction requires care (alpha-renaming or De Bruijn indices).

**Step: Commit**

```bash
git add egraph/docs/advanced/egraph-ready-ir.md
git commit -m "docs: add e-graph-ready IR transformations guide"
```

---

### Task 3: Write conditional-rewrites.md

**Files:**
- Create: `egraph/docs/advanced/conditional-rewrites.md`

**Content outline (~150 lines):**

1. **Prerequisite link**
2. **Motivation** — some rewrites are only valid under certain conditions. `x / 2 → x >> 1` is only valid for non-negative integers. Without conditions, this rule would break equivalence-preservation.
3. **The API** — `Rewrite` struct has `condition : ((Subst) -> Bool)?`. When present, each match is checked before applying. Show the struct definition from `egraph.mbt:703-708`.
4. **Example: Guarded arithmetic**
   - Rule: `Div(?x, Num:2) → Shr(?x, Num:1)` with condition that checks analysis data to confirm `?x` is non-negative.
   - MoonBit code showing how to construct the rewrite with a condition closure.
5. **Example: Preventing infinite loops**
   - Bidirectional rule `a + b ↔ b + a` applied naively creates infinite rewriting. Condition: only fire if `a < b` (by e-class Id) to pick a canonical order.
6. **Equivalence-preservation with conditions**
   - Conditional rewrites are still equivalence-preserving — the condition *restricts the domain* to cases where the equivalence holds. The rule doesn't fire outside that domain, so no false equivalences are introduced.
   - Contrast with unconditional invalid rules.
7. **Limitations and workarounds**
   - The condition receives `Subst` (variable-to-Id mapping), not analysis data. To inspect analysis data, capture the e-graph reference in the closure.
   - Cannot express "apply only if this e-class does NOT contain pattern X" — would need anti-patterns (not supported).

**Step: Commit**

```bash
git add egraph/docs/advanced/conditional-rewrites.md
git commit -m "docs: add conditional rewrites guide"
```

---

### Task 4: Write analysis-driven-rewrites.md

**Files:**
- Create: `egraph/docs/advanced/analysis-driven-rewrites.md`

**Content outline (~200 lines):**

1. **Prerequisite link**
2. **What analysis adds** — pattern-based rewrites are structural (syntactic). Analysis adds semantic information: "this e-class represents the value 5", "this e-class has type Int", "this subexpression costs 3 cycles."
3. **The Analysis interface** — `Analysis[L, D]` with `make`, `merge`, `modify`. Brief recap with the actual struct from `egraph.mbt:1007-1014`.
4. **Pattern: Constant Folding (detailed walkthrough)**
   - `make`: compute `Int?` from e-node children. `Num(n) → Some(n)`, `Add(a, b)` → add if both known.
   - `merge`: take whichever is `Some`.
   - `modify`: if data is `Some(n)`, union with `Num(n)`.
   - Trace through `(2 + 3) * 4`: show each `add()` call, data computation, modify hook firing, and the final e-graph state.
5. **Pattern: Constant Propagation**
   - When `Let(x, Num(5), body)` is in the e-graph, analysis can record that `x = 5` and propagate through `body`.
   - More complex than folding — requires tracking variable bindings in analysis data.
6. **Pattern: Type Inference**
   - `D = Type` (enum: `TInt | TBool | TFun(Type, Type) | TUnknown`).
   - `make`: `Num(_) → TInt`, `Add(a, b) → if both TInt then TInt else TError`.
   - `merge`: unification. `TUnknown` unifies with anything.
   - `modify`: type-directed rewrites (e.g., `Add` on `TBool` → error node).
7. **Pattern: Cost Annotations**
   - `D = Int` representing estimated evaluation cost.
   - `modify`: skip applying expensive rewrites to already-cheap e-classes.
8. **The modify hook as a rewrite engine**
   - `modify` can call `self.add()` and `self.union()` — it's strictly more powerful than pattern-based rewrites for computed results (e.g., evaluating arbitrary arithmetic).
   - Contrast: pattern-based rewrites are declarative and inspectable; modify hooks are opaque but flexible.
9. **Pitfall: modify loops**
   - `modify` adds `Num(5)` → triggers `rebuild` → `recompute_data` → `modify` fires again. The library's `rebuild` uses a fixed-point loop (`while has_pending()`) that converges when modify stops producing new unions.
   - Termination: modify must eventually stop adding new nodes. If it doesn't (e.g., `modify` always creates a new node), the e-graph grows without bound.

**Step: Commit**

```bash
git add egraph/docs/advanced/analysis-driven-rewrites.md
git commit -m "docs: add analysis-driven rewrites guide"
```

---

### Task 5: Write controlling-growth.md

**Files:**
- Create: `egraph/docs/advanced/controlling-growth.md`

**Content outline (~200 lines):**

1. **Prerequisite link**
2. **Why e-graphs explode** — commutativity (`a + b = b + a`) doubles e-class size. Add associativity (`(a + b) + c = a + (b + c)`) and distributivity — exponential. Concrete example: 3 variables with commutative + associative addition → show e-class count growth per iteration.
3. **Understanding the growth curve** — typically linear for simplification-only rules, exponential when exploration rules (commutativity, associativity, distributivity) interact. The "knee" where growth accelerates.
4. **NodeLimit and IterLimit**
   - `NodeLimit(n)`: stop when total e-nodes exceed n. Default 10,000. Good for bounding memory.
   - `IterLimit(n)`: stop after n iterations. Default 30. Good for bounding time.
   - How to choose: start with defaults, increase if `StopReason` is `NodeLimit`/`IterLimit` and the result isn't optimal. Decrease if saturation is too slow.
   - Trade-off: lower limits = faster but possibly suboptimal. Higher limits = better results but more memory/time.
5. **Rule scheduling: multi-pass strategy**
   - Problem: applying all rules at once means simplification rules compete with explosion rules.
   - Solution: run simplification rules first (small IterLimit), then exploration rules.
   - MoonBit sketch: two `Runner::run()` calls with different rule sets.
6. **Rule design principles**
   - **Orient rules when possible**: `x + 0 → x` (one direction) is better than `x + 0 ↔ x` (bidirectional). Only use bidirectional when both directions are needed for saturation.
   - **Avoid redundant rules**: `a + b → b + a` and `b + a → a + b` are the same rule — one suffices.
   - **Combine rules that always co-occur**: if rule A's output always triggers rule B, consider merging them.
7. **Analysis-based pruning**
   - Use analysis data to skip rewrites on already-optimal subexpressions. Example: if constant folding already reduced an e-class to a literal, don't apply arithmetic identity rules to it.
   - Implemented via conditional rewrites that check analysis data.
8. **When to give up**
   - Signs: NodeLimit hit every time, increasing it doesn't improve results, saturation time > seconds.
   - Alternatives: greedy rewriter for cheap passes + e-graph for targeted optimization, domain-specific scheduling, egglog (relational e-matching, more scalable for certain workloads).

**Step: Commit**

```bash
git add egraph/docs/advanced/controlling-growth.md
git commit -m "docs: add controlling e-graph growth guide"
```

---

### Task 6: Write custom-cost-functions.md

**Files:**
- Create: `egraph/docs/advanced/custom-cost-functions.md`

**Content outline (~150 lines):**

1. **Prerequisite link**
2. **How extraction works** — bottom-up fixed-point. For each e-class, try every e-node, compute cost using `CostFn`, keep the cheapest. Repeat until stable. Show the `CostFn[L]` definition from `egraph.mbt:795`.
3. **The default: ast_size** — 1 per node + sum of children. Good for "simplest expression." Show the implementation from `egraph.mbt:799-807`.
4. **Example: Instruction latency**
   - Different operators have different costs: `Add = 1`, `Mul = 3`, `Div = 10`, `Shr = 1`.
   - MoonBit code: custom `CostFn` that matches operator tag.
   - Effect: extraction prefers `x + x` (cost 3) over `x * 2` (cost 4) for doubling.
5. **Example: Register Pressure**
   - Deep expression trees need more registers. Cost = max child depth + 1 (Sethi-Ullman style).
   - Prefers balanced trees over deep chains.
6. **Example: Weighted Code Size vs Speed**
   - `cost = alpha * size + beta * latency`. Tunable parameters.
   - When `alpha >> beta`: prefer small code (embedded). When `beta >> alpha`: prefer fast code (HPC).
7. **Requirements for correctness**
   - **Non-negative**: cost ≥ 0. Negative costs break fixed-point convergence.
   - **Monotonic**: parent cost ≥ each child cost. If violated, extraction may loop.
   - **Finite**: unreachable e-classes get `max_cost` (1,000,000,000). Don't return infinity.
   - What happens when violated: extraction may not converge, return wrong results, or panic.
8. **Interaction with analysis**
   - Use analysis data inside the cost function. Example: constant-folded e-classes have cost 1 (just a literal), regardless of original expression complexity.
   - Requires access to analysis data — pass it via closure capture.

**Step: Commit**

```bash
git add egraph/docs/advanced/custom-cost-functions.md
git commit -m "docs: add custom cost functions guide"
```

---

### Task 7: Write multi-language-patterns.md

**Files:**
- Create: `egraph/docs/advanced/multi-language-patterns.md`

**Content outline (~200 lines):**

1. **Prerequisite link**
2. **The design task** — when using this library for a new domain, you must define an enum implementing `ENode` and `ENodeRepr`. This document shows patterns for different domains and the design trade-offs.
3. **Review: MyLang (arithmetic baseline)**
   - 4 variants, 2 leaf (Num, Var), 2 binary (Add, Mul). Payload for leaves, children for operators.
   - ENodeRepr: `op_tag` = variant name, `payload` = leaf data as string, `from_op` = reconstruct.
4. **Lambda Calculus (LambdaLang)**
   - 7 variants including binding forms (`LLam`, `LLet`, `LApp`).
   - **Binding representation**: named variables (`LVar("x")`) vs De Bruijn indices (`LVar(0)`). Named: human-readable patterns, risk of capture. De Bruijn: capture-free, harder to read.
   - **Substitution as rewrite**: beta-reduction `(λx.body) arg → body[x:=arg]` — requires careful handling in e-graphs because substitution modifies the term structure.
   - The `LambdaLang` enum and its `ENode`/`ENodeRepr` implementations (reference existing code in `lambda_opt_wbtest.mbt`).
5. **SQL Query Optimization**
   - Enum sketch: `Select(Id, Id)`, `From(Id)`, `Where(Id, Id)`, `Join(Id, Id, Id)`, `Table(String)`, `Col(String)`, `And(Id, Id)`, `Eq(Id, Id)`.
   - Example rewrites: predicate pushdown `Select(cols, Where(Join(a, b, cond), pred)) → Select(cols, Join(Where(a, pred), b, cond))` when pred only references columns from `a`.
   - Design decision: `Table` and `Col` are leaves with string payload. `Join` has 3 children (left, right, condition).
6. **Tensor / Linear Algebra**
   - Enum sketch: `MatMul(Id, Id)`, `Transpose(Id)`, `Reshape(Id)`, `Add(Id, Id)`, `Scalar(Double)`, `Tensor(String)`.
   - Example rewrites: `Transpose(Transpose(x)) → x`, `MatMul(MatMul(a, b), c) → MatMul(a, MatMul(b, c))` (associativity — choose by cost).
   - Payload for shape metadata: could use analysis data instead of payload.
7. **Design Principles Summary**
   - **Leaves use payload, operators use children.** `Num(42)` → payload="42". `Add(a, b)` → children=[a, b].
   - **Fixed arity per variant.** If an operator has variable arguments (e.g., function call with N args), use a list encoding: `Call(fn, Args(arg1, Args(arg2, Nil)))`.
   - **op_tag must be unique per variant.** The pattern matcher uses `op_tag` to dispatch.
   - **Payload round-trips.** `from_op(op_tag(x), payload(x), children(x))` must reconstruct `x`. Test this invariant.
   - **Keep the language small.** Only model what you plan to optimize. A 50-variant language makes pattern matching slow and rule sets unwieldy.

**Step: Commit**

```bash
git add egraph/docs/advanced/multi-language-patterns.md
git commit -m "docs: add multi-language ENode/ENodeRepr patterns guide"
```

---

### Task 8: Write debugging-egraphs.md

**Files:**
- Create: `egraph/docs/advanced/debugging-egraphs.md`

**Content outline (~150 lines):**

1. **Prerequisite link**
2. **"My rewrite didn't fire"**
   - **Wrong op_tag**: Pattern says `"Add"` but `op_tag` returns `"add"` (case-sensitive).
   - **Wrong arity**: Pattern `(Add ?x ?y ?z)` but Add has arity 2.
   - **Payload mismatch**: Pattern `(Num:0)` but payload returns `"0.0"` or `" 0"`.
   - **Already equivalent**: The rule matched and applied, but the lhs and rhs were already in the same e-class (from a previous iteration). `apply_matches` returns 0 — not a bug, just saturation.
   - **Condition blocked**: The `condition` closure returned `false` for all matches.
   - **Debugging technique**: Call `egraph.search(rule.lhs)` manually and inspect the returned matches. Empty array = pattern didn't match. Non-empty = check condition.
3. **"Wrong result after extraction"**
   - **Invalid rewrite rule**: The most common cause. A rule that isn't equivalence-preserving introduces false equivalences. Check every rule by hand.
   - **Cost function issue**: Extraction found the cheapest expression, but your cost function doesn't match your intent. Try `ast_size()` first to verify correctness, then switch to custom cost.
   - **Unsaturated e-graph**: `StopReason` is `IterLimit` or `NodeLimit` — the e-graph didn't explore all rewrites. Increase limits.
   - **Missing rebuild**: Called `union` without `rebuild` afterward. The e-graph's internal invariants are broken.
4. **Inspecting e-graph state**
   - Iterate over e-classes: `for id, eclass in egraph.classes { ... }`.
   - Check membership: `egraph.find(a) == egraph.find(b)` → same e-class.
   - Count e-nodes: `egraph.classes.size()` for e-class count.
   - Print e-class contents: iterate `eclass.nodes` and show each e-node.
5. **Common mistakes**
   - **Forgetting rebuild()**: After `union()`, always call `rebuild()` before `search()` or `extract()`. Without rebuild, the hashcons is stale and congruence isn't closed.
   - **Bidirectional rules causing explosion**: `a + b → b + a` AND `b + a → a + b` — both fire every iteration, doubling e-class size. Use one direction + condition, or accept the growth.
   - **Non-canonical Ids**: After `union`, old Ids may be stale. Always use `find(id)` to get the canonical representative.
   - **Payload format mismatch**: `from_op` must be the inverse of `op_tag`/`payload`. If `payload` returns `Some("42")`, then `from_op("Num", Some("42"), [])` must return `Some(Num(42))`.
6. **Testing strategies**
   - **Start small**: Test with 2-3 node expressions before scaling up.
   - **Assert intermediate state**: After each `apply_rewrite` + `rebuild`, check that expected equivalences hold (`find(a) == find(b)`).
   - **Check StopReason**: `Saturated` is good. `NodeLimit`/`IterLimit` may mean suboptimal results.
   - **Round-trip test**: For every variant of your language, verify `from_op(op_tag(x), payload(x), children_of(x)) == Some(x)`.

**Step: Commit**

```bash
git add egraph/docs/advanced/debugging-egraphs.md
git commit -m "docs: add e-graph debugging guide"
```

---

### Task 9: Update design plan status and final commit

**Files:**
- Modify: `egraph/docs/plans/2026-03-07-advanced-docs-design.md`

**Step 1: Mark design as complete**

Add `**Status:** Complete` near the top of the design doc.

**Step 2: Commit**

```bash
git add egraph/docs/plans/2026-03-07-advanced-docs-design.md
git commit -m "docs: mark advanced docs design as complete"
```
