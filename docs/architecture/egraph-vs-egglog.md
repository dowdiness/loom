# EGraph vs Egglog: When to Use Which

Two modules in loom implement e-graph-based reasoning. They share the core idea — **store equivalent expressions compactly using union-find** — but differ in architecture, API, and use case.

## One-Sentence Summary

**EGraph** (`loom/egraph/`) explores all equivalent rewrites of an expression and extracts the cheapest one. **Egglog** (`loom/egglog/`) answers relational queries about expressions using Datalog rules that can assert new equalities.

## Comparison

| | EGraph | Egglog |
|---|---|---|
| **Model** | Functional e-graph (like [egg](https://egraphs-good.github.io/)) | Relational database + e-graph (like [egglog](https://egglog-python.readthedocs.io/)) |
| **Primary operation** | Rewrite rules: match pattern, add equivalent form | Datalog rules: match query, insert facts or assert equality |
| **Pattern language** | S-expression strings: `"(Add ?a ?b)"` | Programmatic MoonBit: `Fact("Add", [Var("a"), Var("b")])` |
| **Rule application** | Three-phase loop: search all rules → apply all matches → rebuild | Semi-naive fixpoint: fire rules on new facts only (delta-driven) |
| **E-class analysis** | First-class: `make`/`merge`/`modify` callbacks run during rebuild | Implicit: derived facts in tables serve the same role |
| **Extraction** | `extract(root, cost_fn) -> (cost, RecExpr)` — flat array of nodes | `extract(root, cost_fn) -> (cost, ExtractedExpr)` — nested tree |
| **Host-side computation** | Via analysis `modify` hooks (MoonBit callbacks during rebuild) | Via bridge functions called between Datalog iterations |
| **Growth control** | BackoffScheduler, NodeLimit, IterLimit | Saturate iteration cap, row count limits |
| **Binding** | Explicit substitution nodes + free-variable analysis | Reified environments: `EmptyEnv`, `ExtendEnv(parent, name, val)` |

## When to Use EGraph

Use the egraph when you want to **find the best equivalent form** of an expression.

- **Algebraic simplification**: `(x + 0) * 1 → x`
- **Constant folding**: `2 + 3 → 5` discovered via e-class analysis
- **Beta reduction**: `(λx. x + 1) 5 → 6` via explicit substitution rewrites
- **Cost-driven extraction**: "give me the simplest equivalent expression"

The egraph excels when many rewrite rules interact — it explores all orderings simultaneously (equality saturation) and picks the cheapest result afterward. This avoids the phase-ordering problem that plagues traditional optimizers.

**Limitation**: The egraph has no notion of "querying" — you add expressions, apply rewrites, and extract. It cannot answer questions like "what type does this expression have?" because type inference requires top-down information flow (checking mode), which rewrite rules cannot express.

## When to Use Egglog

Use egglog when you need **relational reasoning** — deriving new facts from existing ones, especially with multi-directional information flow.

- **Type inference**: `HasType(env, expr) → type` with bidirectional checking
- **Demand-driven evaluation**: `Demand(env, expr)` propagates down, `Eval(env, expr) → value` propagates up
- **Environment-based scoping**: `TypeEnv(env, name) → type` and `ValEnv(env, name) → value` as separate relations
- **Composition**: typing and evaluation rules coexist in one database without interference

Egglog excels when the problem is naturally relational — multiple tables, join conditions, and derived facts. Semi-naive evaluation ensures only new facts trigger rule re-firing, making fixpoint computation efficient.

**Limitation**: Egglog actions are restricted to `Set` (insert fact), `Union` (assert equality), and `LetAction` (bind variable). They cannot call arbitrary MoonBit functions. Operations like integer arithmetic or branch selection require a host-side bridge function that runs between Datalog iterations.

## How Canopy Uses Both

The lambda evaluator uses a three-tier architecture:

```
Tier 1: Direct Evaluator (μs)
  Simple recursive eval(env, term) → Value | Stuck
  Handles 95% of cases. Fast path.

Tier 2: Egglog Knowledge Base (ms)
  Relational Eval(env, expr) → value rules
  Handles partial programs: evaluates around holes.
  Typing + evaluation coexist in one database.
  Kicks in when Tier 1 returns Stuck.

Tier 3: EGraph Optimizer (on-demand)
  Equality saturation with algebraic rewrites.
  "Simplify this expression" — user-triggered.
  Seeds from Tier 2 equivalences, extracts cheapest form.
```

### Why Two Engines, Not One?

Egglog *contains* an e-graph (it uses union-find internally), but it is not a replacement for the egraph module:

1. **Rewrite rules vs Datalog rules** — Equality saturation with pattern-based rewrites is the egraph's core strength. Egglog can express rewrites as rules, but the egraph's three-phase loop with backoff scheduling is purpose-built for exploring large rewrite spaces without blowup.

2. **E-class analysis** — The egraph's `make`/`merge`/`modify` framework provides compositional semantic analysis (constant folding, free variable tracking) that runs during rebuild. Egglog achieves similar results through derived tables, but the analysis framework is more natural for optimization passes.

3. **Binding strategies differ** — Tier 2 (egglog) uses reified environments (`ExtendEnv` nodes) because evaluation needs to track scope. Tier 3 (egraph) uses explicit substitution (`LSubst` nodes pushed down via rewrites) because optimization needs capture-avoiding beta reduction without environment overhead.

4. **Different performance profiles** — The egraph is optimized for exploring many equivalent forms quickly (hashcons deduplication, congruence closure). Egglog is optimized for reaching a fixpoint of derived facts quickly (semi-naive delta processing). Neither subsumes the other's sweet spot.

## Decision Tree

```
Need to answer "what is the type/value of X?"
  → Egglog (relational query)

Need to find "what is the simplest form of X?"
  → EGraph (equality saturation + extraction)

Need top-down + bottom-up information flow?
  → Egglog (Datalog naturally supports both)

Need to explore many rewrite orderings?
  → EGraph (avoids phase-ordering problem)

Need host-side computation (arithmetic, branching)?
  → Both need bridges, but:
    - EGraph: analysis modify hooks (during rebuild)
    - Egglog: bridge functions (between iterations)

Need incremental updates after edits?
  → Both work with incr Runtime, but:
    - Egglog: semi-naive re-derives only new facts
    - EGraph: must re-saturate (future: incremental egg)
```

## Further Reading

- [egraph/docs/introduction.md](../../egraph/docs/introduction.md) — e-graph concepts, API walkthrough
- [egraph/docs/advanced/](../../egraph/docs/advanced/) — analysis, growth control, cost functions, debugging
- [egglog/src/README.mbt.md](../../egglog/src/README.mbt.md) — egglog database internals
- [egglog/docs/archive/2026-03-08-egglog-design.md](../../egglog/docs/archive/2026-03-08-egglog-design.md) — egglog architecture and design decisions
- Canopy evaluator design: `canopy/docs/plans/2026-04-02-lambda-evaluator-design.md`
