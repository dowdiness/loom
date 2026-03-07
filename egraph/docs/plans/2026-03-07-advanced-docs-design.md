# Design: Advanced E-Graph Documentation Suite

**Date:** 2026-03-07
**Status:** Draft

## Goal

Create a set of standalone advanced topic documents that bridge the gap between the beginner-friendly introduction and real-world e-graph usage. Each document covers one topic in depth, mixing conceptual explanation with concrete MoonBit examples using the library's existing types.

## Audience

Dual audience per document:
- **Compiler/PL students** — conceptual understanding of the technique
- **Library users** — practical "how to do this with this MoonBit e-graph library"

Each doc starts with theory, then shows concrete implementation using `MyLang`/`LambdaLang`.

## Prerequisites

All documents assume the reader has read `introduction.md`. Each opens with a one-line prerequisite link. No re-introduction of basic concepts (e-class, e-node, union, rebuild).

## Structure

```
docs/advanced/
├── README.md                    — index with one-line summaries
├── egraph-ready-ir.md           — IR transformations
├── conditional-rewrites.md      — rules with predicates
├── analysis-driven-rewrites.md  — modify hooks and analysis patterns
├── controlling-growth.md        — managing e-graph explosion
├── custom-cost-functions.md     — domain-specific extraction
├── multi-language-patterns.md   — ENode/ENodeRepr design for different domains
└── debugging-egraphs.md         — troubleshooting and inspection
```

## Document Outlines

### 1. egraph-ready-ir.md (~250 lines)

Why source languages aren't e-graph-ready. Three transformations:

- **Effect separation** — split pure computation from side effects. Theory: algebraic effects / monadic IO. Practice: wrap effectful spine around pure e-graph core. Example: extend MyLang with Print/Seq, show before/after.
- **Control flow flattening** — if-statements to select nodes, loops to fixed-point operators. Theory: CPS, ANF. Practice: add Select(Id, Id, Id) to MyLang.
- **SSA / let-binding form** — eliminate mutable variables. Theory: SSA phi-functions vs let-bindings. Practice: show variable renaming, how each binding becomes an e-graph add().
- **The pipeline** — source → parse → lower → e-graph optimize → extract → codegen/eval. Diagram.

### 2. conditional-rewrites.md (~150 lines)

Rules that only fire when a predicate holds on the substitution.

- **Motivation** — platform-specific rewrites (`x / 2 → x >> 1` only for unsigned), guard conditions, type-directed rewrites.
- **API** — `Rewrite` struct's `condition: ((Subst) -> Bool)?` field.
- **Examples** — arithmetic guards, preventing infinite loops, analysis-informed conditions.
- **Interaction with equivalence-preservation** — conditional rewrites are still equivalence-preserving *within their domain* (the condition defines the domain).
- **Limitations** — can only inspect substitution (e-class Ids), not analysis data directly. Workaround: look up analysis data via the e-graph inside the condition closure.

### 3. analysis-driven-rewrites.md (~200 lines)

Using e-class analysis to drive optimization beyond pattern matching.

- **Recap** — `Analysis[L, D]` with make/merge/modify.
- **Pattern: constant folding** — already in introduction, show the full flow in detail.
- **Pattern: constant propagation** — when a variable is bound to a known constant.
- **Pattern: type inference** — analysis data = type, merge = unify, modify = type-directed rewrites.
- **Pattern: cost annotations** — analysis data = estimated cost, used to prune expensive branches.
- **The modify hook as a rewrite engine** — modify can call add() and union(), making it strictly more powerful than pattern-based rewrites for computed results.
- **Pitfall: modify loops** — modify adds a node → rebuild fires → modify fires again. How the library's fixed-point loop handles this.

### 4. controlling-growth.md (~200 lines)

Practical strategies for managing e-graph explosion.

- **Why e-graphs explode** — commutativity × associativity × distributivity = exponential. Concrete example showing growth.
- **NodeLimit and IterLimit** — how to choose values, trade-offs.
- **Rule ordering** — apply simplification rules before explosion-causing rules. Manual scheduling with multiple Runner passes.
- **Rule design** — oriented rules (A → B, not A ↔ B) when one direction is always better. Avoiding redundant rules.
- **Analysis-based pruning** — use analysis data to avoid applying rules to already-optimal subexpressions.
- **When to give up** — signs that your rule set is too powerful for e-graphs, alternative approaches.

### 5. custom-cost-functions.md (~150 lines)

Beyond `ast_size`: designing cost functions for real domains.

- **The CostFn[L] interface** — how extraction uses it, fixed-point convergence.
- **Example: instruction latency** — different operators have different costs (Add=1, Mul=3, Div=10).
- **Example: register pressure** — penalize deep expression trees.
- **Example: code size vs speed trade-off** — weighted combination.
- **Gotchas** — cost must be monotonic (children cost ≤ parent cost), non-negative, finite. What happens if violated.
- **Interaction with analysis** — using analysis data to inform cost (e.g., constant expressions are free).

### 6. multi-language-patterns.md (~200 lines)

Designing ENode/ENodeRepr for different domains.

- **Arithmetic (MyLang)** — already covered, recap as baseline.
- **Lambda calculus (LambdaLang)** — binding, substitution, De Bruijn indices vs named variables.
- **SQL** — Select, From, Where, Join. Operator fusion, predicate pushdown as rewrites.
- **Tensor/linear algebra** — MatMul, Transpose, Reshape. Associativity of MatMul, fusion.
- **Design principles** — choosing operators, arity decisions, payload encoding, when to use payload vs children.

### 7. debugging-egraphs.md (~150 lines)

Troubleshooting when things don't work.

- **"My rewrite didn't fire"** — common causes: pattern doesn't match (wrong op_tag, wrong arity, payload mismatch), rule applied but result already existed.
- **"Wrong result after extraction"** — invalid rewrite rule, cost function issues, unsaturated e-graph.
- **Inspecting e-graph state** — iterating e-classes, checking e-class membership, verifying unions.
- **Common mistakes** — forgetting rebuild(), non-equivalence-preserving rules, infinite growth from bidirectional rules.
- **Testing strategies** — small examples first, assert intermediate state, use Runner stop reason.

## Depth

Each document: 150-250 lines. Substantial enough to stand alone, concise enough to read in one sitting. Theory sections use pseudocode; practice sections use MoonBit with the library's actual API.

## Implementation Order

Documents are independent — can be written in parallel. Suggested order by dependency:

1. `README.md` (index) + `egraph-ready-ir.md` (extends introduction material)
2. `conditional-rewrites.md` + `analysis-driven-rewrites.md` (build on each other)
3. `controlling-growth.md` + `custom-cost-functions.md` (independent)
4. `multi-language-patterns.md` + `debugging-egraphs.md` (independent)
