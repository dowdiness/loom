# E-Graph Module: Implementation Report

## Summary

A complete e-graph (equality graph) module implemented in MoonBit across 8 incremental steps, following TDD (Red-Green-Refactor) with code review (`/simplify`) after each step. The module implements equality saturation — a technique for program optimization that explores many equivalent rewrites simultaneously.

**Codebase**: 2,562 lines across 3 files, 85 tests, 24 design concerns documented.

| File | Lines | Purpose |
|------|------:|---------|
| `egraph.mbt` | 1,259 | Production code (all 8 steps) |
| `egraph_wbtest.mbt` | 712 | Core e-graph whitebox tests (54 tests) |
| `lambda_opt_wbtest.mbt` | 591 | Lambda calculus example + analysis tests (31 tests) |

---

## Implementation Steps

### Step 1: Union-Find

Foundation data structure for equivalence class management.

- `UnionFind` with path compression and union by rank
- `Id` newtype wrapper for type safety
- O(α(n)) amortized per operation

**Key types**: `Id`, `Rank`, `UnionFind`

### Step 2: EGraph Core

E-graph data structure with hashconsing and congruence closure.

- `EGraph[L]` with Union-Find, e-class map, memo (hashcons) table
- `add`: canonicalize children, deduplicate via memo
- `union`: merge e-classes, schedule pending congruence repair
- `rebuild`: fixed-point congruence closure

**Key types**: `EClass[L]`, `EGraph[L]`
**Key traits**: `ENode` (structural access to children)

### Step 3: E-Matching

Pattern matching over equivalence classes — the search engine of equality saturation.

- `Pat` enum: `Var(String)` | `Node(String, String?, Array[Pat])`
- S-expression parser: `Pat::parse("(Add ?x (Num:0))")`
- `ematch`: recursive pattern matching producing `Array[Subst]`
- `search`: match a pattern across all e-classes
- `instantiate`: construct concrete nodes from a pattern + substitution

**Key types**: `Pat`, `Subst`
**Key trait**: `ENodeRepr` (serialization bridge between concrete e-nodes and language-independent patterns)

### Step 4: Rewrite Rules

Declarative transformation rules that drive optimization.

- `Rewrite` struct with `lhs`/`rhs` patterns and optional `condition`
- `apply_rewrite` / `apply_matches`: search + instantiate + union
- Conditional rewrites: `condition: ((Subst) -> Bool)?`

**Key types**: `Rewrite`

### Step 5: Extraction

Select the lowest-cost equivalent expression from an e-class.

- Bottom-up fixed-point cost computation
- `CostFn[L]`: pluggable cost function (default: `ast_size`)
- `RecExpr[L]`: extracted expression as a flat node array
- `reconstruct`: recursive tree reconstruction from best-node map

**Key types**: `CostFn[L]`, `RecExpr[L]`

### Step 6: Runner

Equality saturation loop with termination conditions.

- Read-Write-Rebuild cycle per iteration
- Three stop conditions: `Saturated`, `IterLimit`, `NodeLimit`
- Configurable limits via labelled arguments

**Key types**: `StopReason`, `Runner[L]`

### Step 7: Lambda Calculus Example

End-to-end demonstration with a real language.

- `LambdaLang` enum: 7 variants (`LNum`, `LVar`, `LAdd`, `LMul`, `LLam`, `LApp`, `LLet`)
- `ENode` and `ENodeRepr` implementations
- 6 arithmetic rules, commutativity, associativity
- Negative tests: unknown tags, wrong arity, invalid payloads, blocked conditions

### Step 8: E-Class Analysis

Domain-specific data per e-class (constant folding, type inference, etc.)

- `Analysis[L, D]` function record: `make`, `merge`, `modify` callbacks
- `AnalyzedEGraph[L, D]` wrapper (composition over `EGraph[L]`)
- Side `Map[Id, D]` for analysis data — no modification to core `EGraph`
- Analysis-aware `instantiate` and `apply_matches` (hooks fire during rewriting)
- `rebuild` with full data propagation: canonicalize → recompute (fixed-point relaxation) → modify hooks → repeat until stable
- Constant folding example: `2 + 3` → `5`, nested `(2 + 3) * 4` → `20`, parent recomputation after child union

**Design decisions**:
- Used composition (`AnalyzedEGraph` wraps `EGraph`) instead of the plan's `EGraph[L, D]` approach, avoiding ~60+ call site changes while keeping the core e-graph simple
- `rebuild` uses fixed-point relaxation passes (`recompute_data`) to propagate new child facts through parent nodes after congruence changes

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  AnalyzedEGraph[L, D]            │
│  ┌──────────────────────┐  ┌─────────────────┐  │
│  │     EGraph[L]        │  │  Analysis[L, D]  │  │
│  │  ┌────────────────┐  │  │  make / merge /  │  │
│  │  │   UnionFind    │  │  │  modify          │  │
│  │  └────────────────┘  │  └─────────────────┘  │
│  │  classes : Map[Id,   │  data : Map[Id, D]    │
│  │            EClass]   │                       │
│  │  memo : Map[L, Id]   │                       │
│  └──────────────────────┘                       │
└─────────────────────────────────────────────────┘

Equality Saturation Loop (Runner):
  for each iteration:
    1. Read:    search(rule.lhs) for all rules
    2. Write:   apply_matches(rule, matches)
    3. Rebuild: rebuild() — restore congruence
    4. Check:   Saturated? IterLimit? NodeLimit?
```

## Trait Hierarchy

```
ENode           — structural child access (arity, child, map_children)
ENodeRepr       — serialization bridge (op_tag, payload, from_op)
Hash + Eq       — hashcons deduplication
```

All four trait bounds compose into the full `Language` constraint: `L : ENode + ENodeRepr + Hash + Eq`.

---

## Design Decisions

24 design concerns recorded in [`design-concerns.md`](design-concerns.md), including:

| # | Topic | Decision |
|---|-------|----------|
| 1 | Stringly-typed patterns | Accepted — standard in e-graph literature |
| 2 | ENodeRepr vs Eq | ENodeRepr required — cross-type matching |
| 8 | apply_rewrite return type | Raw `Int` — sufficient for saturation detection |
| 12 | max_cost sentinel | Silent failure — unreachable in correct usage |
| 17 | TimeLimit omitted | No MoonBit clock API — use IterLimit + NodeLimit |
| 18 | Capability traits | Deferred — only 2 implementors, phantom generality |
| 22 | Runner + AnalyzedEGraph | No integration yet — manual loop is straightforward |
| 23 | recompute_data pass count | O(n) passes — correct but conservative, early termination possible |
| 24 | Pat::parse error positions | No character offset in errors — patterns are short |

---

## Future Work

### API Design
- Pattern helper functions (`var()`, `node()`, `atom()`)
- Labelled arguments for `rewrite()`
- Richer `apply_rewrite` return type

### Performance
- `merge_substs` allocation optimization
- `ematch` buffer pre-allocation
- Dijkstra-style extraction
- Benchmark suite

### Integration
- Runner + AnalyzedEGraph unification
- Capability traits (when a third e-graph variant appears)
- TimeLimit (when MoonBit adds a clock API)

---

## Test Coverage

85 tests across two files:

| Category | Count | File |
|----------|------:|------|
| UnionFind | 8 | egraph_wbtest.mbt |
| EGraph core (add, union, rebuild) | 6 | egraph_wbtest.mbt |
| ENodeRepr | 7 | egraph_wbtest.mbt |
| Pat parsing | 6 | egraph_wbtest.mbt |
| E-matching | 5 | egraph_wbtest.mbt |
| Search | 1 | egraph_wbtest.mbt |
| Instantiate | 2 | egraph_wbtest.mbt |
| Rewrite rules | 6 | egraph_wbtest.mbt |
| Extraction | 4 | egraph_wbtest.mbt |
| Runner | 6 | egraph_wbtest.mbt |
| Analysis (TestLang) | 1 | egraph_wbtest.mbt |
| Misc | 2 | egraph_wbtest.mbt |
| Lambda arithmetic | 6 | lambda_opt_wbtest.mbt |
| Lambda full rules | 3 | lambda_opt_wbtest.mbt |
| Lambda let-binding | 1 | lambda_opt_wbtest.mbt |
| Negative tests | 7 | lambda_opt_wbtest.mbt |
| Analysis (LambdaLang) | 9 | lambda_opt_wbtest.mbt |
| Runner (lambda) | 5 | lambda_opt_wbtest.mbt |
