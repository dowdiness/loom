// ── Lambda calculus language (Step 7) ──
//
// A realistic language for demonstrating equality saturation.
// Covers: numeric literals, variables, arithmetic, lambda abstraction,
// function application, and let-binding.

///|
priv enum LambdaLang {
  LNum(Int)
  LVar(String)
  LAdd(Id, Id)
  LMul(Id, Id)
  LLam(String, Id)
  LApp(Id, Id)
  LLet(String, Id, Id)
} derive(Eq, Hash, Compare, Show, Debug)

///|
impl ENode for LambdaLang with arity(self) {
  match self {
    LNum(_) | LVar(_) => 0
    LAdd(_, _) | LMul(_, _) | LApp(_, _) => 2
    LLam(_, _) => 1
    LLet(_, _, _) => 2
  }
}

///|
impl ENode for LambdaLang with child(self, i) {
  match self {
    LAdd(a, b) | LMul(a, b) | LApp(a, b) => if i == 0 { a } else { b }
    LLam(_, body) => body
    LLet(_, value, body) => if i == 0 { value } else { body }
    _ => abort("no children")
  }
}

///|
impl ENode for LambdaLang with map_children(self, f) {
  match self {
    LNum(_) | LVar(_) => self
    LAdd(a, b) => LAdd(f(a), f(b))
    LMul(a, b) => LMul(f(a), f(b))
    LApp(a, b) => LApp(f(a), f(b))
    LLam(name, body) => LLam(name, f(body))
    LLet(name, value, body) => LLet(name, f(value), f(body))
  }
}

///|
impl ENodeRepr for LambdaLang with op_tag(self) {
  match self {
    LNum(_) => "Num"
    LVar(_) => "Var"
    LAdd(_, _) => "Add"
    LMul(_, _) => "Mul"
    LLam(_, _) => "Lam"
    LApp(_, _) => "App"
    LLet(_, _, _) => "Let"
  }
}

///|
impl ENodeRepr for LambdaLang with payload(self) {
  match self {
    LNum(n) => Some(n.to_string())
    LVar(name) => Some(name)
    LLam(name, _) => Some(name)
    LLet(name, _, _) => Some(name)
    _ => None
  }
}

///|
impl ENodeRepr for LambdaLang with from_op(tag, payload, children) {
  match (tag, payload, children.length()) {
    ("Num", Some(s), 0) => Some(LNum(@strconv.parse_int(s))) catch { _ => None }
    ("Var", Some(s), 0) => Some(LVar(s))
    ("Add", None, 2) => Some(LAdd(children[0], children[1]))
    ("Mul", None, 2) => Some(LMul(children[0], children[1]))
    ("App", None, 2) => Some(LApp(children[0], children[1]))
    ("Lam", Some(name), 1) => Some(LLam(name, children[0]))
    ("Let", Some(name), 2) => Some(LLet(name, children[0], children[1]))
    _ => None
  }
}

///|
/// Arithmetic simplification rules for lambda calculus.
fn lambda_arith_rules() -> Array[Rewrite] raise Error {
  [
    rewrite("add-0", "(Add ?x (Num:0))", "?x"),
    rewrite("0-add", "(Add (Num:0) ?x)", "?x"),
    rewrite("mul-1", "(Mul ?x (Num:1))", "?x"),
    rewrite("1-mul", "(Mul (Num:1) ?x)", "?x"),
    rewrite("mul-0", "(Mul ?x (Num:0))", "(Num:0)"),
    rewrite("0-mul", "(Mul (Num:0) ?x)", "(Num:0)"),
  ]
}

///|
/// Full rule set including commutativity and associativity.
/// WARNING: commutativity rules never saturate — always pair with node_limit.
fn lambda_full_rules() -> Array[Rewrite] raise Error {
  let rules = lambda_arith_rules()
  // Commutativity
  rules.push(rewrite("add-comm", "(Add ?x ?y)", "(Add ?y ?x)"))
  rules.push(rewrite("mul-comm", "(Mul ?x ?y)", "(Mul ?y ?x)"))
  // Associativity
  rules.push(
    rewrite("add-assoc", "(Add (Add ?x ?y) ?z)", "(Add ?x (Add ?y ?z))"),
  )
  rules
}

// ── Lambda calculus tests ──

///|
test "lambda: x + 0 simplifies to x" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let sum = eg.add(LAdd(x, zero))
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[sum])
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
  let (cost, expr) = runner.egraph.extract(sum, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LVar("x"))
}

///|
test "lambda: x * 0 simplifies to 0" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let prod = eg.add(LMul(x, zero))
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[prod])
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
  let (cost, expr) = runner.egraph.extract(prod, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LNum(0))
}

///|
test "lambda: x * 1 simplifies to x" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let one = eg.add(LNum(1))
  let prod = eg.add(LMul(x, one))
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[prod])
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
  let (cost, expr) = runner.egraph.extract(prod, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LVar("x"))
}

///|
test "lambda: (x + 0) * 1 simplifies to x" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let one = eg.add(LNum(1))
  let sum = eg.add(LAdd(x, zero))
  let prod = eg.add(LMul(sum, one))
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[prod])
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
  let (cost, expr) = runner.egraph.extract(prod, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LVar("x"))
}

///|
test "lambda: 0 + x simplifies to x via identity rule" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  // 0 + x — simplified directly by the 0-add identity rule
  let sum = eg.add(LAdd(zero, x))
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[sum])
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
  let (cost, expr) = runner.egraph.extract(sum, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LVar("x"))
}

///|
test "lambda: nested (0 + (x * 1)) + 0 simplifies to x" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let one = eg.add(LNum(1))
  // Build: (0 + (x * 1)) + 0
  let inner_mul = eg.add(LMul(x, one))
  let inner_add = eg.add(LAdd(zero, inner_mul))
  let outer = eg.add(LAdd(inner_add, zero))
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[outer])
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
  let (cost, expr) = runner.egraph.extract(outer, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LVar("x"))
}

///|
test "lambda: LambdaLang ENodeRepr round-trip" {
  // Verify from_op reconstructs all variants correctly
  let cases : Array[(LambdaLang, String, String?, Array[Id])] = [
    (LNum(42), "Num", Some("42"), []),
    (LVar("x"), "Var", Some("x"), []),
    (LAdd(Id(0), Id(1)), "Add", None, [Id(0), Id(1)]),
    (LMul(Id(0), Id(1)), "Mul", None, [Id(0), Id(1)]),
    (LApp(Id(0), Id(1)), "App", None, [Id(0), Id(1)]),
    (LLam("x", Id(0)), "Lam", Some("x"), [Id(0)]),
    (LLet("x", Id(0), Id(1)), "Let", Some("x"), [Id(0), Id(1)]),
  ]
  for c in cases {
    let (expected, tag, payload, children) = c
    let result = LambdaLang::from_op(tag, payload, children)
    assert_eq(result, Some(expected))
  }
}

///|
test "lambda: full rules with commutativity simplify (a + 0) + (b * 1)" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let a = eg.add(LVar("a"))
  let b = eg.add(LVar("b"))
  let zero = eg.add(LNum(0))
  let one = eg.add(LNum(1))
  // Build: (a + 0) + (b * 1) — should simplify to a + b
  let a_plus_0 = eg.add(LAdd(a, zero))
  let b_times_1 = eg.add(LMul(b, one))
  let root = eg.add(LAdd(a_plus_0, b_times_1))
  let rules = lambda_full_rules()
  let runner = Runner::new(eg, roots=[root], node_limit=1000)
  runner.run(rules) |> ignore
  let (cost, expr) = runner.egraph.extract(root, ast_size())
  // Optimal: Add(Var("a"), Var("b")) — cost 3
  assert_eq(cost, 3)
  assert_eq(expr.nodes.length(), 3)
}

///|
test "lambda: associativity explores equivalent groupings" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let a = eg.add(LVar("a"))
  let b = eg.add(LVar("b"))
  let c = eg.add(LVar("c"))
  // Build: (a + b) + c
  let ab = eg.add(LAdd(a, b))
  let abc = eg.add(LAdd(ab, c))
  // Also build: a + (b + c)
  let bc = eg.add(LAdd(b, c))
  let a_bc = eg.add(LAdd(a, bc))
  // Before saturation, these are different e-classes
  assert_true(eg.find(abc) != eg.find(a_bc))
  let rules = lambda_full_rules()
  let runner = Runner::new(eg, roots=[abc], node_limit=1000)
  runner.run(rules) |> ignore
  // After saturation with associativity, both groupings are equivalent
  assert_eq(runner.egraph.find(abc), runner.egraph.find(a_bc))
}

///|
test "lambda: function application in e-graph" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  // Build: (λx. x + 0) applied to 5
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let body = eg.add(LAdd(x, zero))
  let lam = eg.add(LLam("x", body))
  let five = eg.add(LNum(5))
  let app = eg.add(LApp(lam, five))
  // Just verify it's in the e-graph (beta reduction needs analysis, Step 8)
  assert_eq(eg.find(app), app)
  // Arithmetic rules can still simplify the body: x + 0 → x
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[app])
  runner.run(rules) |> ignore
  // After saturation, the body (x + 0) is equivalent to x
  assert_eq(runner.egraph.find(body), runner.egraph.find(x))
}

// ── Structural preservation tests ──

///|
test "lambda: let-binding in e-graph preserves structure" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  // Build: let x = 5 in x + x
  let five = eg.add(LNum(5))
  let x = eg.add(LVar("x"))
  let body = eg.add(LAdd(x, x))
  let let_expr = eg.add(LLet("x", five, body))
  // Arithmetic rules don't affect let-bindings (no let-inlining rule)
  let rules = lambda_arith_rules()
  let runner = Runner::new(eg, roots=[let_expr])
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
  // let_expr should remain unchanged (no simplification possible)
  let (cost, expr) = runner.egraph.extract(let_expr, ast_size())
  // LLet(1 + cost(Num) + cost(Add)) = 1+1+3 = 5
  // where Add = 1 + cost(Var) + cost(Var) = 1+1+1 = 3
  assert_eq(cost, 5)
  // Root is a Let node
  assert_true(
    match expr.root() {
      LLet("x", _, _) => true
      _ => false
    },
  )
}

// ── Negative tests ──

///|
test "lambda: from_op rejects unknown tag" {
  let result = LambdaLang::from_op("Unknown", None, [])
  assert_eq(result, None)
}

///|
test "lambda: from_op rejects wrong arity for Add" {
  // Add needs 2 children, not 1
  let result = LambdaLang::from_op("Add", None, [Id(0)])
  assert_eq(result, None)
}

///|
test "lambda: from_op rejects wrong arity for Lam" {
  // Lam needs 1 child, not 0
  let result = LambdaLang::from_op("Lam", Some("x"), [])
  assert_eq(result, None)
}

///|
test "lambda: from_op rejects Num with children" {
  let result = LambdaLang::from_op("Num", Some("42"), [Id(0)])
  assert_eq(result, None)
}

///|
test "lambda: from_op rejects Num without payload" {
  let result = LambdaLang::from_op("Num", None, [])
  assert_eq(result, None)
}

///|
test "lambda: from_op rejects Add with payload" {
  let result = LambdaLang::from_op("Add", Some("extra"), [Id(0), Id(1)])
  assert_eq(result, None)
}

///|
test "lambda: pattern mismatch produces no matches" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let y = eg.add(LVar("y"))
  let mul = eg.add(LMul(x, y))
  // Search for Add pattern in an e-graph with only Mul
  let pat = Pat::parse("(Add ?a ?b)")
  let results = eg.search(pat)
  assert_eq(results.length(), 0)
  // Also: Mul pattern should not match at the Num e-class
  let pat2 = Pat::parse("(Mul ?a ?b)")
  let results2 = eg.ematch(pat2, x)
  assert_eq(results2.length(), 0)
  // But should match at the Mul e-class
  let results3 = eg.ematch(pat2, mul)
  assert_eq(results3.length(), 1)
}

///|
test "lambda: no rules means immediate saturation" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let y = eg.add(LVar("y"))
  let _ = eg.add(LAdd(x, y))
  let runner = Runner::new(eg)
  let reason = runner.run([])
  assert_eq(reason, Saturated)
}

///|
test "lambda: rules that don't match produce saturation" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let y = eg.add(LVar("y"))
  let _ = eg.add(LMul(x, y))
  // Add rules don't match Mul nodes
  let rules = [rewrite("add-0", "(Add ?x (Num:0))", "?x")]
  let runner = Runner::new(eg)
  let reason = runner.run(rules)
  assert_eq(reason, Saturated)
}

///|
test "lambda: conditional rewrite blocks application" {
  let eg : EGraph[LambdaLang] = EGraph::new()
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let sum = eg.add(LAdd(x, zero))
  let rw : Rewrite = {
    name: "blocked-add-0",
    lhs: Pat::parse("(Add ?x (Num:0))"),
    rhs: Pat::parse("?x"),
    condition: Some(fn(_subst) { false }),
  }
  let runner = Runner::new(eg, roots=[sum])
  let reason = runner.run([rw])
  // Condition always false → no rewrites applied → saturated immediately
  assert_eq(reason, Saturated)
  // sum and x should NOT be equivalent
  assert_true(runner.egraph.find(sum) != runner.egraph.find(x))
}

///|
test "lambda: from_op with invalid Num payload returns None" {
  // Non-numeric payload for Num returns None (caught by try/catch in from_op)
  let result = LambdaLang::from_op("Num", Some("not_a_number"), [])
  assert_eq(result, None)
}

// ── E-Class Analysis tests (Step 8) ──

///|
/// Constant folding analysis: tracks known constant values per e-class.
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

///|
test "analysis: constant folding computes 2 + 3 = 5" {
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(two, three))
  // After adding, analysis should compute that sum's e-class has value Some(5)
  assert_eq(eg.get_data(sum), Some(5))
  // The modify hook should have added Num(5) to the same e-class
  eg.rebuild()
  let five = eg.add(LNum(5))
  assert_eq(eg.find(sum), eg.find(five))
}

///|
test "analysis: constant folding computes 2 * 3 = 6" {
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let prod = eg.add(LMul(two, three))
  assert_eq(eg.get_data(prod), Some(6))
  eg.rebuild()
  let six = eg.add(LNum(6))
  assert_eq(eg.find(prod), eg.find(six))
}

///|
test "analysis: variable has no constant data" {
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let x = eg.add(LVar("x"))
  assert_eq(eg.get_data(x), None)
}

///|
test "analysis: nested (2 + 3) * 4 = 20" {
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(two, three))
  let four = eg.add(LNum(4))
  let prod = eg.add(LMul(sum, four))
  assert_eq(eg.get_data(prod), Some(20))
  eg.rebuild()
  let twenty = eg.add(LNum(20))
  assert_eq(eg.find(prod), eg.find(twenty))
}

///|
test "analysis: merge preserves data on union" {
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let x = eg.add(LVar("x"))
  // x has no constant data; union x with 2+3 which has data Some(5)
  let sum = eg.add(LAdd(two, three))
  eg.union(x, sum) |> ignore
  // After union, the merged class should have Some(5) (from the sum)
  assert_eq(eg.get_data(x), Some(5))
}

///|
test "analysis: partial constants (x + 3) has no constant data" {
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let x = eg.add(LVar("x"))
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(x, three))
  // One child is variable → cannot fold
  assert_eq(eg.get_data(sum), None)
}

///|
test "analysis: constant folding with rewrite rules" {
  // Combine analysis (constant folding) with rewrite rules (x+0→x)
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let sum = eg.add(LAdd(x, zero))
  // sum has no constant data (x is variable)
  assert_eq(eg.get_data(sum), None)
  // Apply rewrite: x+0 → x (rule[0] = "add-0": (Add ?x (Num:0)) → ?x)
  let rules = lambda_arith_rules()
  let matches = eg.search(rules[0].lhs)
  eg.apply_matches(rules[0], matches) |> ignore
  eg.rebuild()
  // After rewrite + rebuild, sum and x should be equivalent
  assert_eq(eg.find(sum), eg.find(x))
}

///|
test "analysis: extract best from analyzed e-graph" {
  let eg = AnalyzedEGraph::new(constant_fold_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(two, three))
  eg.rebuild()
  // After constant folding, Num(5) was added and merged with sum's class
  let cost_fn = ast_size()
  let (cost, expr) = eg.extract(sum, cost_fn)
  // Num(5) has cost 1, Add(Num(2), Num(3)) has cost 3 → extract picks Num(5)
  assert_eq(cost, 1)
  assert_eq(expr.root(), LNum(5))
}
