# Adding an E-Graph Module to loom: Implementation Plan

## Overview

```
loom/
├── incr/          # Salsa-inspired incremental computation (existing)
├── seam/          # Language-agnostic CST infrastructure (existing)
├── loom/          # Parser framework (existing)
├── egraph/        # ← New module
│   ├── src/       # Steps 1-2: UnionFind, ENode/ENodeRepr/Language traits, EGraph core
│   ├── src/pat/   # Step 3: Pat enum, s-expression parser, e-matching
│   └── src/runner/# Steps 4-6: Rewrite, Extraction, Runner
└── examples/
    ├── lambda/     # Existing λ-calculus parser
    └── lambda-opt/ # ← Step 7: Optimization example using e-graphs
```

The package structure is kept small (3 packages) because the components are tightly coupled — e-matching needs e-graph internals, rewrite needs both. Whitebox tests within each package provide access to internal state for thorough testing.

---

## Step 1: Union-Find (Foundation Data Structure)

**Goal**: Equivalence class management — the foundation of the entire e-graph.

Every e-graph operation depends on union-find. An efficient implementation with path compression and union by rank is required.

### Data Structures

```moonbit
/// E-class identifier. Newtype for type safety.
type Id Int derive(Eq, Compare, Hash, Show)

/// Union-Find with path compression and union by rank
struct UnionFind {
  /// parent[i] == i means root. Otherwise points to parent.
  parents : Array[Id]
  /// Rank for union by rank (upper bound on tree height)
  ranks : Array[Int]
}
```

### Operations to Implement

```moonbit
fn UnionFind::new() -> UnionFind

/// Create a new equivalence class. Returns a fresh Id.
fn make_set(self : UnionFind) -> Id

/// Find the canonical representative (with path compression).
fn find(self : UnionFind, id : Id) -> Id

/// Merge two equivalence classes. Returns the representative Id.
fn union(self : UnionFind, a : Id, b : Id) -> Id

/// Current number of elements.
fn size(self : UnionFind) -> Int
```

### Test Cases

- `find(make_set())` returns itself
- After `union(a, b)`, `find(a) == find(b)`
- Path compression makes subsequent `find` calls faster
- Transitivity: `union(a, b); union(b, c)` → `find(a) == find(c)`

### Implementation Notes

In MoonBit, path compression is done with `Array[Id]`. During `find`, rewrite `parents[i] = root` while traversing the path. MoonBit's `Array` is mutable, so this is straightforward.

---

## Step 2: E-Graph Core (Central Data Structure)

**Goal**: Manage e-nodes (expression nodes) and e-classes (equivalence classes).

### Trait Design — Capability Traits + Super-Trait

Following egg's design, e-nodes are abstracted via traits. An e-node is "an operator + a sequence of child e-class Ids". We decompose this into fine-grained **capability traits**, then compose them into a convenience super-trait.

```moonbit
/// Capability 1: Structural access to children.
/// Required by: add, rebuild, extract.
trait ENode {
  /// Return the child Ids (for iteration).
  children(Self) -> Array[Id]
  /// Return a copy with children mapped (for congruence closure).
  map_children(Self, (Id) -> Id) -> Self
}

/// Capability 2: Serialization bridge for pattern matching.
/// Analogous to ToJson/FromJson — projects an e-node into a universal
/// (op_name, children) representation that patterns can match against.
/// Required by: ematch, instantiate.
///
/// Design note: Nodes with payloads (e.g., Num(42), Var("x")) encode the
/// payload into the op_name string (e.g., "Num:42", "Var:x"). This keeps
/// the bridge simple — `Pat::Node("Num:0", [])` matches `Num(0)` exactly.
trait ENodeRepr {
  /// Operator tag including payload (e.g., "Add", "Num:42", "Var:x").
  op_name(Self) -> String
  /// Reconstruct from operator tag + children. Returns None for unknown ops.
  from_op(String, Array[Id]) -> Self?
}

/// Convenience super-trait combining both capabilities.
/// Users implement this; internal functions declare minimal bounds.
trait Language : ENode + ENodeRepr {}
```

Internal e-graph operations declare only the bounds they need:

| Operation | Required traits |
|-----------|----------------|
| `add` (hashcons) | `ENode + Hash + Eq` |
| `rebuild` (congruence) | `ENode + Hash + Eq` |
| `ematch` (pattern matching) | `ENode + ENodeRepr` |
| `instantiate` (build from pattern) | `ENodeRepr` |
| `extract` (cost-based selection) | `ENode` |
| `run` (full runner) | `Language + Hash + Eq` |

**MoonBit-specific design decision**: Rust's egg requires `Ord + Hash` on `Language` and uses the `define_language!` macro to generate boilerplate. MoonBit has no macros, so we substitute `derive(Eq, Hash, Compare)` plus manual `ENode` / `ENodeRepr` implementations. The capability trait decomposition ensures Steps 1-2 can be built and tested without the `ENodeRepr` bridge (which is only needed from Step 3 onward).

### E-Class Structure

```moonbit
/// A single equivalence class.
/// In Steps 1-7 this is EClass[L] with no analysis data.
/// Step 8 generalizes to EClass[L, D] by adding a `data : D` field.
struct EClass[L] {
  /// E-nodes belonging to this class.
  nodes : Array[L]
}
```

### EGraph Core

```moonbit
struct EGraph[L] {
  /// Union-find.
  uf : UnionFind
  /// E-class Id → EClass mapping.
  classes : HashMap[Id, EClass[L]]
  /// Hashcons: e-node → owning e-class Id (deduplication).
  memo : HashMap[L, Id]
  /// Worklist of e-class Ids that need rebuilding.
  pending : Array[Id]
  /// Clean flag (whether rebuild has completed).
  clean : Bool
}
```

### Operations to Implement

```moonbit
fn EGraph::new[L]() -> EGraph[L]

/// Add an e-node to the e-graph.
/// Via hashconsing, returns the existing e-class Id if an equivalent e-node exists.
/// Otherwise creates a new e-class and returns its Id.
fn add[L : ENode + Hash + Eq](self : EGraph[L], node : L) -> Id

/// Merge two e-classes. Adds to pending for deferred congruence repair.
fn union[L](self : EGraph[L], a : Id, b : Id) -> Id

/// Return the canonical e-class Id (delegates to union-find's find).
fn find[L](self : EGraph[L], id : Id) -> Id

/// Restore invariants (congruence closure).
/// egg's key innovation: deferred repair instead of immediate repair for speed.
fn rebuild[L : ENode + Hash + Eq](self : EGraph[L]) -> Unit
```

### Rebuild Pseudocode

```
rebuild():
  while pending is not empty:
    id = pending.pop()
    id = find(id)  // canonicalize
    eclass = classes[id]

    // Canonicalize children of each node in the e-class
    new_nodes = []
    for node in eclass.nodes:
      canonical = node.map_children(fn(child) { find(child) })
      new_nodes.push(canonical)
    eclass.nodes = deduplicate(new_nodes)

    // Update hashcons: remove stale entries, add canonicalized versions
    // If collision found, union and add to pending (congruence)
    for node in eclass.nodes:
      if memo.contains(node) and memo[node] != id:
        // Congruence discovered! Must merge.
        union(id, memo[node])
      else:
        memo[node] = id

  clean = true
```

### RecExpr — Flattened Expression Representation

Extracted expressions need a concrete tree representation. Since `L`'s children are `Id`s (e-graph internal), we use a flattened array where children reference indices:

```moonbit
/// A recursively-defined expression stored as a flat array.
/// nodes[i]'s children are Ids that index into this same array.
/// The root is always the last element.
struct RecExpr[L] {
  nodes : Array[L]
}
```

This is the return type of extraction (Step 5) and the input format for bulk insertion.

### Visualization — DotNode for Debugging

Implement loom's `DotNode` trait for `EGraph` to enable DOT graph rendering. E-classes are rendered as clusters, e-nodes as nodes within clusters, and child edges cross cluster boundaries:

```moonbit
/// Render the e-graph as a DOT graph for debugging.
fn to_dot[L : ENode + Show](self : EGraph[L]) -> String
```

This is invaluable for debugging congruence closure and verifying e-class merges visually.

### Test Cases

- Idempotency of `add`: adding the same e-node twice returns the same Id
- After `union`, `find` agrees
- Congruence: after `union(a, b)`, `f(a)` and `f(b)` end up in the same e-class
- After `rebuild`, hashcons is correctly updated

---

## Step 3: E-Matching (Pattern Matching)

**Goal**: Search the e-graph for occurrences of a rewrite rule's left-hand side pattern.

### Pattern Definition — Language-Independent

Patterns are a **separate, concrete AST** — not parameterized by the language type `L`. This is analogous to `JsonValue`: a universal intermediate representation that any `Language` can be matched against via the `ENodeRepr` bridge.

```moonbit
/// Pattern: either a variable or a concrete operator with child patterns.
/// Language-independent — uses operator names (strings), not L values.
enum Pat {
  /// Pattern variable (matches any e-class). e.g., `?x`
  Var(String)
  /// Concrete operator pattern. e.g., `(Add ?x (Num 0))`
  Node(String, Array[Pat])
}

/// Match result: pattern variable → e-class Id substitution.
type Subst Map[String, Id]
```

### S-Expression Pattern Parser

The `pattern("(Add ?x (Num 0))")` syntax used in rewrite rules requires a mini s-expression parser:

```moonbit
/// Parse an s-expression string into a Pat.
/// Grammar:
///   pat  = var | atom | '(' op pat* ')'
///   var  = '?' identifier
///   atom = identifier | integer
///   op   = identifier
///
/// Examples:
///   "?x"                → Var("x")
///   "(Num:0)"           → Node("Num:0", [])
///   "(Add ?x (Num:0))"  → Node("Add", [Var("x"), Node("Num:0", [])])
fn Pat::parse(s : String) -> Pat!Error
```

This parser is small (< 50 lines) but load-bearing — all rewrite rules depend on it.

### E-Match Algorithm

E-matching returns all `(e-class Id, Subst)` pairs where the pattern matches within the e-graph. Matching uses the `ENodeRepr` bridge to compare operator names.

```
ematch(egraph, pattern, eclass_id) -> Array[Subst]:
  match pattern:
    Var(name):
      // Variable: bind to this e-class (check consistency if already bound)
      return [{ name: eclass_id }]

    Node(op, children_patterns):
      results = []
      for enode in egraph.classes[eclass_id].nodes:
        if enode.op_name() == op and enode.children().length() == children_patterns.length():
          // Recursively match each child pattern
          substs = [empty_subst]
          for (child_id, child_pat) in zip(enode.children(), children_patterns):
            new_substs = []
            for s in substs:
              for s2 in ematch(egraph, child_pat, child_id):
                if compatible(s, s2):
                  new_substs.push(merge(s, s2))
            substs = new_substs
          results.extend(substs)
      return results
```

**A `search` function that scans all e-classes is also needed:**

```moonbit
/// Search the entire e-graph for pattern matches.
fn search[L : ENode + ENodeRepr](self : EGraph[L], pattern : Pat) -> Array[(Id, Subst)]
```

### Instantiate — Build E-Nodes from a Pattern

Uses `ENodeRepr::from_op` to reconstruct concrete e-nodes from pattern matches:

```moonbit
/// Instantiate a pattern with a substitution, adding nodes to the e-graph.
fn instantiate[L : ENodeRepr + ENode + Hash + Eq](
  self : EGraph[L], pattern : Pat, subst : Subst
) -> Id
```

### Test Cases

- `Var("x")` matches any e-class
- `Pat::parse("(Add ?x (Num:0))")` correctly parses to `Node("Add", [Var("x"), Node("Num:0", [])])`
- `Node("Add", [Var("x"), ...])` matches expressions of the form `a + 0` via `op_name`
- Same variable binds to the same e-class: `(Add ?x ?x)` matches `a + a` but not `a + b`
- Post-union matching: after `union(a, b)`, if `Var("x")` matches `a` it also matches `b`
- Round-trip: `from_op(op_name(node), children(node))` reconstructs the original node

---

## Step 4: Rewrite Rules

**Goal**: Use pattern match results to add new equivalences to the e-graph.

### Data Structures

Rewrite rules are language-independent — they use `Pat`, not `L`:

```moonbit
/// Rewrite rule: lhs → rhs (language-independent).
struct Rewrite {
  name : String
  /// Search pattern (left-hand side).
  lhs : Pat
  /// Apply pattern (right-hand side).
  rhs : Pat
  /// Conditional rewrite (optional). Receives the e-graph opaquely.
  condition : ((Subst) -> Bool)?
}

/// Convenience constructor using s-expression syntax.
fn rewrite(name : String, lhs : String, rhs : String) -> Rewrite!Error {
  { name, lhs: Pat::parse!(lhs), rhs: Pat::parse!(rhs), condition: None }
}
```

### Apply Operation

`instantiate` (defined in Step 3) uses `ENodeRepr::from_op` to reconstruct concrete e-nodes from the pattern's operator names.

```
apply_rewrite(egraph, rewrite):
  matches = search(egraph, rewrite.lhs)
  for (matched_eclass, subst) in matches:
    if rewrite.condition is Some(cond) and not cond(subst):
      continue
    // Instantiate rhs pattern with subst and add to e-graph
    new_id = instantiate(egraph, rewrite.rhs, subst)
    // Merge matched e-class with the new node's e-class
    egraph.union(matched_eclass, new_id)
```

### Test Cases

- `x + 0 → x` rule causes `a + 0` and `a` to end up in the same e-class
- `x * 1 → x` rule causes `a * 1` and `a` to end up in the same e-class
- Conditional rule: not applied when the condition is false
- Chaining: the result of rule A enables rule B to match

---

## Step 5: Extraction (Selecting the Optimal Representation)

**Goal**: Extract the lowest-cost equivalent expression from the e-graph.

### Cost Function — Plain Function Type

A cost function does not need to be a trait — it does not vary by `Self` type. Use a plain function:

```moonbit
/// Cost function type: given an e-node and a way to look up child costs, return the node cost.
/// Using a function type avoids the trait-with-type-parameter problem (MoonBit traits are Self-based).
type CostFn[L] (L, (Id) -> Int) -> Int

/// Simplest example: AST size (1 per node + sum of children).
fn ast_size[L : ENode]() -> CostFn[L] {
  fn(node, child_cost) {
    1 + node.children().fold(init=0, fn(acc, child) { acc + child_cost(child) })
  }
}
```

### Extraction Algorithm (Bottom-Up Fixed-Point)

Returns a `RecExpr[L]` (defined in Step 2) — the flattened optimal expression.

```
extract(egraph, root_id, cost_fn) -> (Int, RecExpr[L]):
  // Compute minimum cost per e-class via fixed-point iteration
  best_cost : HashMap[Id, Int] = {}
  best_node : HashMap[Id, L] = {}

  changed = true
  while changed:
    changed = false
    for (id, eclass) in egraph.classes:
      for node in eclass.nodes:
        cost = cost_fn(node, fn(child) { best_cost.get_or(find(child), MAX_INT) })
        canonical_id = find(id)
        if cost < best_cost.get_or(canonical_id, MAX_INT):
          best_cost[canonical_id] = cost
          best_node[canonical_id] = node
          changed = true

  // Recursively reconstruct the optimal tree into a RecExpr
  reconstruct(best_node, find(root_id))
```

**Complexity note:** This fixed-point iteration is O(iterations × nodes). For acyclic e-graphs it converges in one pass. For cyclic e-graphs (created by rules like commutativity), it may require multiple passes. A Dijkstra-like extraction would be O(n log n) but more complex to implement. The naive version is acceptable for initial implementation; optimize if benchmarks show it's a bottleneck.

### Test Cases

- A constant-only expression has minimum cost 1
- After applying `x + 0 → x` to `a + 0`, extraction returns `a` (cost 1, vs `a + 0` at cost 3)
- After applying multiple rules to `(a * 2) / 2`, optimal result `a` is extracted
- Extracted `RecExpr` can be pretty-printed back to a readable expression

---

## Step 6: Runner (Equality Saturation Loop)

**Goal**: An automatic equality saturation executor that ties all the pieces together.

### Data Structures

```moonbit
struct Runner[L] {
  egraph : EGraph[L]
  roots : Array[Id]
  /// Stopping conditions
  iter_limit : Int
  node_limit : Int
  time_limit : Int64  // milliseconds
}

enum StopReason {
  Saturated     // No more changes possible
  IterLimit
  NodeLimit
  TimeLimit
}
```

### Equality Saturation Pseudocode

```
run(runner, rewrites) -> StopReason:
  for iter in 0..runner.iter_limit:
    // === Read Phase ===
    // Collect matches for all rewrite rules
    all_matches = []
    for rw in rewrites:
      matches = search(runner.egraph, rw.lhs)
      all_matches.push((rw, matches))

    // === Write Phase ===
    // Apply rewrites at matched locations
    applied = 0
    for (rw, matches) in all_matches:
      for (eclass, subst) in matches:
        new_id = instantiate(runner.egraph, rw.rhs, subst)
        if find(eclass) != find(new_id):
          runner.egraph.union(eclass, new_id)
          applied += 1

    // === Rebuild Phase ===
    runner.egraph.rebuild()

    // === Termination Check ===
    if applied == 0:
      return Saturated
    if egraph.size() > runner.node_limit:
      return NodeLimit
    if elapsed > runner.time_limit:
      return TimeLimit

  return IterLimit
```

### Commutativity and Explosion

**Warning:** Bidirectional rules like `add-comm` (`a + b → b + a`) generate e-nodes on every iteration without ever reaching saturation. The `node_limit` is **essential** (not optional) to prevent runaway growth. When writing rules:

- Commutativity rules are useful but always pair them with a `node_limit`
- Monitor e-graph size growth per iteration during development
- Consider whether a rule is truly needed or if extraction-time symmetry breaking suffices

### Test Cases

- Simple arithmetic rules reach saturation
- Stops correctly at `IterLimit`
- Stops correctly at `NodeLimit`
- Commutativity rules grow the e-graph but are bounded by `node_limit`
- Post-saturation extraction returns the correct optimal result

---

## Step 7: examples/lambda-opt — λ-Calculus Optimization Example

**Goal**: Connect the existing `examples/lambda` parser with the e-graph to run actual equality saturation.

### Language Definition

```moonbit
/// E-node definition for lambda calculus
enum LambdaLang {
  /// Numeric literal
  Num(Int)
  /// Variable
  Var(String)
  /// Addition: children = [lhs, rhs]
  Add(Id, Id)
  /// Multiplication: children = [lhs, rhs]
  Mul(Id, Id)
  /// Lambda abstraction: name + body
  Lam(String, Id)
  /// Function application: children = [func, arg]
  App(Id, Id)
  /// Let expression: name + value + body
  Let(String, Id, Id)
} derive(Eq, Hash, Compare, Show)
```

### Capability Trait Implementations

```moonbit
/// ENode: structural access to children.
pub impl ENode for LambdaLang with children(self) {
  match self {
    Num(_) | Var(_) => []
    Add(a, b) | Mul(a, b) | App(a, b) => [a, b]
    Lam(_, body) => [body]
    Let(_, value, body) => [value, body]
  }
}

pub impl ENode for LambdaLang with map_children(self, f) {
  match self {
    Num(_) | Var(_) => self
    Add(a, b) => Add(f(a), f(b))
    Mul(a, b) => Mul(f(a), f(b))
    App(a, b) => App(f(a), f(b))
    Lam(name, body) => Lam(name, f(body))
    Let(name, value, body) => Let(name, f(value), f(body))
  }
}

/// ENodeRepr: serialization bridge for pattern matching.
/// Payload-carrying nodes encode the payload into the op_name string.
pub impl ENodeRepr for LambdaLang with op_name(self) {
  match self {
    Num(n) => "Num:\{n}"
    Var(name) => "Var:\{name}"
    Add(_, _) => "Add"
    Mul(_, _) => "Mul"
    Lam(name, _) => "Lam:\{name}"
    App(_, _) => "App"
    Let(name, _, _) => "Let:\{name}"
  }
}

pub impl ENodeRepr for LambdaLang with from_op(op, children) {
  // Split "Tag:payload" on first ':'
  let (tag, payload) = split_op(op)
  match (tag, payload, children) {
    ("Num", Some(s), []) => Some(Num(@strconv.parse_int!(s)))
    ("Var", Some(s), []) => Some(Var(s))
    ("Add", None, [a, b]) => Some(Add(a, b))
    ("Mul", None, [a, b]) => Some(Mul(a, b))
    ("App", None, [a, b]) => Some(App(a, b))
    ("Lam", Some(name), [body]) => Some(Lam(name, body))
    ("Let", Some(name), [value, body]) => Some(Let(name, value, body))
    _ => None
  }
}
```

### Example Rewrite Rules

```moonbit
fn lambda_rules() -> Array[Rewrite] {
  [
    // === Arithmetic simplification ===
    // x + 0 → x  (Num:0 encodes the payload in the op name)
    rewrite!("add-0", "(Add ?x (Num:0))", "?x"),
    // 0 + x → x
    rewrite!("0-add", "(Add (Num:0) ?x)", "?x"),
    // x * 1 → x
    rewrite!("mul-1", "(Mul ?x (Num:1))", "?x"),
    // x * 0 → 0
    rewrite!("mul-0", "(Mul ?x (Num:0))", "(Num:0)"),
    // Constant folding (implemented via e-class analysis in Step 8)

    // === Commutativity ===
    // WARNING: These rules never saturate — they generate new e-nodes every iteration.
    // The runner's node_limit is essential to prevent runaway growth.
    // x + y → y + x
    rewrite!("add-comm", "(Add ?x ?y)", "(Add ?y ?x)"),
    // x * y → y * x
    rewrite!("mul-comm", "(Mul ?x ?y)", "(Mul ?y ?x)"),

    // === Associativity ===
    // (x + y) + z → x + (y + z)
    rewrite!("add-assoc", "(Add (Add ?x ?y) ?z)", "(Add ?x (Add ?y ?z))"),

    // === Let-inlining ===
    // let x = v in body → body[x := v]
    // (Conditional: only when v is "small". Determined via e-class analysis in Step 8.)
  ]
}
```

### Pipeline Integration (MoonBit)

```moonbit
// 1. Parse source to CST via loom parser
let cst = parse(source)

// 2. Convert to AST
let ast = to_ast(cst)

// 3. Insert AST into e-graph
let egraph = EGraph::new()
let root = ast_to_egraph(egraph, ast)

// 4. Run equality saturation
let runner = Runner::new(egraph)
  |> with_root(root)
  |> with_iter_limit(30)
  |> with_node_limit(10_000)
let stop = runner.run(lambda_rules())

// 5. Extract the optimal representation
let (cost, best_expr) = extract(runner.egraph, root, ast_size())
```

---

## Step 8 (Future): E-Class Analysis

**Goal**: Domain-specific data associated with e-classes (constant values, type info, free variable sets, etc.)

Corresponds to egg's `Analysis` trait. Since MoonBit traits lack associated types, we use a **type-parameterized struct** approach instead of a trait — making the analysis data type `D` an explicit type parameter on `EGraph`.

### Design: EGraph[L, D] with Analysis Functions

```moonbit
/// E-graph parameterized by both language and analysis data.
struct EGraph[L, D] {
  uf : UnionFind
  classes : Map[Id, EClass[L, D]]
  memo : Map[L, Id]
  pending : Array[Id]
  clean : Bool
}

struct EClass[L, D] {
  nodes : Array[L]
  data : D
}

/// Analysis is a record of functions, not a trait.
/// This avoids the associated-type problem entirely.
struct Analysis[L, D] {
  /// Compute data from an e-node.
  make : (L, (Id) -> D) -> D
  /// Merge data from two e-classes (semilattice join).
  merge : (D, D) -> D
  /// Hook called on data change (e.g., constant folding adds new nodes).
  modify : (EGraph[L, D], Id) -> Unit
}
```

Using a function record (Solution 4 from the Expression Problem) instead of a trait:
- Sidesteps the associated-type limitation completely
- Analyses are first-class values (can be stored, composed, swapped at runtime)
- No orphan-rule issues

### Constant Folding Example

```moonbit
fn constant_folding() -> Analysis[LambdaLang, Int?] {
  {
    make: fn(node, get_data) {
      match node {
        Num(n) => Some(n)
        Add(a, b) =>
          match (get_data(a), get_data(b)) {
            (Some(x), Some(y)) => Some(x + y)
            _ => None
          }
        Mul(a, b) =>
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
      // If a constant value is known, add a Num(n) node to the e-class
      match egraph.get_data(id) {
        Some(n) => {
          let num_id = egraph.add(Num(n))
          egraph.union(id, num_id)
        }
        None => ()
      }
    },
  }
}
```

### Integration Note: For Steps 1-7, use `EGraph[L, Unit]`

The analysis-free e-graph is simply `EGraph[L, Unit]` with a trivial analysis. This keeps Steps 1-7 unchanged — the `D` parameter is only meaningful in Step 8.

---

## Step Dependencies and Trait Requirements

```
Step 1: Union-Find         ← No dependencies        (no traits)
Step 2: E-Graph core       ← Step 1                 (ENode + Hash + Eq)
Step 3: E-Matching + Pat   ← Step 2                 (+ ENodeRepr → Language)
Step 4: Rewrite rules      ← Steps 2, 3             (Language + Hash + Eq)
Step 5: Extraction         ← Step 2                 (ENode only)
Step 6: Runner             ← Steps 2, 3, 4, 5       (Language + Hash + Eq)
Step 7: lambda-opt example ← Step 6 + existing code (full stack)
Step 8: E-Class Analysis   ← Steps 2, 6             (adds D parameter)
```

Note: Steps 3 and 5 are independent of each other and can be developed in parallel.

**Shortest path (to a working demo):** Steps 1 → 2 → (3 ∥ 5) → 4 → 6 → 7.

## Benchmarking Targets

Benchmark early and often (`moon bench --release`). Key measurements:

| Metric | Where | Why |
|--------|-------|-----|
| `add` throughput (ops/sec) | Step 2 | HashMap/hashcons performance |
| `rebuild` cost vs. e-graph size | Step 2 | Congruence closure scaling |
| `ematch` per rule × e-class count | Step 3 | Pattern matching is the hot loop |
| Saturation time for N rules | Step 6 | End-to-end runner performance |
| E-graph memory footprint | Step 6 | HashMap overhead in MoonBit |

The plan flags MoonBit's `HashMap` as a potential bottleneck (see Design Considerations §4). Benchmarking `add` throughput in Step 2 will surface this early — before building the full stack on top.

## Future Integration: `incr` (Reactive Incremental Computation)

The loom project's `incr/` module provides `Signal` and `Memo` for reactive incremental computation. A natural future extension is an **incremental e-graph** that reacts to source edits:

```
Signal[String] → Memo[CstNode] → Memo[Ast] → Memo[EGraph optimized result]
```

This is explicitly out of scope for Steps 1-8, but the API should not preclude it. In particular:
- `EGraph` should be cheaply cloneable or support incremental rebuild from a delta
- The `Runner` should accept pre-populated e-graphs (not just fresh ones)
- Extraction results should be cacheable by e-graph generation/version

---

## MoonBit-Specific Design Considerations

### 1. No Macros

Rust's egg uses the `define_language!` macro to auto-generate Language implementations. In MoonBit, manual implementation is required. `derive` can generate `Eq`, `Hash`, and `Compare`, but `ENode` (`children` / `map_children`) and `ENodeRepr` (`op_name` / `from_op`) must be written by hand.

**Mitigation**: Use pattern matching on each Language enum variant. There is some added boilerplate (see Step 7's `LambdaLang` implementations), but MoonBit's pattern matching is readable enough that this is not a significant burden.

### 2. Single-Parameter Traits → Capability Decomposition

MoonBit traits are Self-based with no type parameters or associated types. This plan addresses this via:

- **Capability traits** (`ENode`, `ENodeRepr`): fine-grained, each with Self-closed or fixed-type methods
- **Super-trait composition** (`trait Language : ENode + ENodeRepr {}`): convenience for users
- **Function records for Analysis** (Step 8): avoids the associated-type problem entirely by using `Analysis[L, D]` as a struct of functions rather than a trait
- **Plain function types for CostFunction** (Step 5): `(L, (Id) -> Int) -> Int` instead of a trait

### 3. Pattern Representation — The ENodeRepr Bridge

E-graphs require structural observation (hashconsing, congruence closure), so Finally Tagless encoding is not viable. Instead, patterns use a **separate, language-independent AST** (`Pat`) bridged to concrete languages via `ENodeRepr` — analogous to `ToJson`/`FromJson`. See Step 3 for details.

### 4. Monomorphization

MoonBit compiles via monomorphization, so `EGraph[LambdaLang, Unit]` generates specialized code. This is advantageous for performance in inner loops like those found in e-graphs.

### 5. HashMap Performance

The e-graph's hashcons (memo table) is heavily dependent on HashMap. Benchmark MoonBit's standard library `HashMap` performance early (see Benchmarking Targets above).

---

## Future Work

### Pattern Construction API

The current `rewrite("name", "(Add ?x (Num:0))", "?x")` API uses s-expression strings parsed at runtime. This is the standard approach in e-graph literature (egg, egglog) and convenient for quick rule definitions, but has trade-offs:

- **Runtime parse errors**: typos in pattern strings are caught at runtime, not compile time.
- **Positional string parameters**: `(name, lhs, rhs)` are all `String`, easy to transpose.

**Alternative 1 — Direct Pat construction** (no parsing, partially typed):
```moonbit
let rw : Rewrite = {
  name: "add-zero",
  lhs: Node("Add", None, [Var("x"), Node("Num", Some("0"), [])]),
  rhs: Var("x"),
  condition: None,
}
```

**Alternative 2 — Helper functions** (readable, no parsing):
```moonbit
fn var(name : String) -> Pat { Var(name) }
fn node(tag : String, children : Array[Pat]) -> Pat { Node(tag, None, children) }
fn atom(tag : String, payload : String) -> Pat { Node(tag, Some(payload), []) }

// Usage
let lhs = node("Add", [var("x"), atom("Num", "0")])
```

**Note**: Tag strings ("Add", "Num") will always be strings because `Pat` is language-independent — that's the fundamental design choice enabling reusable patterns across different `ENodeRepr` implementations. A fully typed pattern API would require patterns parameterized by `L`, losing language-independence and s-expression compatibility.

**Recommendation**: Keep s-expression parser as the primary API. Consider adding helper functions if verbosity becomes a pain point. Consider labelled arguments (`rewrite(name~, lhs~, rhs~)`) to prevent parameter transposition.

### E-Matching Performance

The `ematch` hot loop has known optimization opportunities:

- **`merge_substs` copies the entire map** on every call via `a_map.copy()`. For patterns with many variables or deeply nested structures, this creates O(|vars| × |matches|) allocation pressure. A mutable substitution with backtracking, or a persistent/immutable map with structural sharing, would reduce this.
- **`ematch` allocates fresh `Array[Subst]`** at every recursion level. Pre-allocated buffers or a stack-based approach would reduce GC pressure.
- **`search` uses a `visited` HashSet** to deduplicate canonical Ids. After `rebuild`, class keys should already be canonical — the set may be redundant if `search` is always called post-rebuild.

These are optimization targets for Step 7 benchmarking, not correctness issues.

---

## References

- Willsey et al. "egg: Fast and Extensible Equality Saturation" POPL 2021
  - https://arxiv.org/abs/2004.03082
- egg tutorial
  - https://docs.rs/egg/latest/egg/tutorials/
- hegg (Haskell implementation) — type-class-based implementation for reference
  - https://hackage.haskell.org/package/hegg
- Philip Zucker "A Simplified E-graph Implementation" (Julia) — minimal implementation reference
  - https://www.philipzucker.com/egraph-2/
- SIGPLAN Blog explanation
  - https://blog.sigplan.org/2021/04/06/equality-saturation-with-egg/
