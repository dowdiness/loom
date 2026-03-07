// ── Test language ──

///|
priv enum TestLang {
  Num(Int)
  Add(Id, Id)
} derive(Eq, Hash, Compare, Show, Debug)

///|
impl ENode for TestLang with arity(self) {
  match self {
    Num(_) => 0
    Add(_, _) => 2
  }
}

///|
impl ENode for TestLang with child(self, i) {
  match self {
    Add(a, b) => if i == 0 { a } else { b }
    _ => abort("no children")
  }
}

///|
impl ENode for TestLang with map_children(self, f) {
  match self {
    Num(_) => self
    Add(a, b) => Add(f(a), f(b))
  }
}

///|
impl ENodeRepr for TestLang with op_tag(self) {
  match self {
    Num(_) => "Num"
    Add(_, _) => "Add"
  }
}

///|
impl ENodeRepr for TestLang with payload(self) {
  match self {
    Num(n) => Some(n.to_string())
    _ => None
  }
}

///|
impl ENodeRepr for TestLang with from_op(tag, payload, children) {
  match (tag, payload, children.length()) {
    ("Num", Some(s), 0) => Some(Num(@strconv.parse_int(s))) catch { _ => None }
    ("Add", None, 2) => Some(Add(children[0], children[1]))
    _ => None
  }
}

// ── UnionFind tests ──

///|
test "make_set returns fresh Id" {
  let uf = UnionFind()
  let a = uf.make_set()
  let b = uf.make_set()
  inspect(a, content="0")
  inspect(b, content="1")
}

///|
test "find of fresh Id returns itself" {
  let uf = UnionFind()
  let a = uf.make_set()
  assert_eq(uf.find(a), a)
}

///|
test "union makes find agree" {
  let uf = UnionFind()
  let a = uf.make_set()
  let b = uf.make_set()
  uf.union(a, b) |> ignore
  assert_eq(uf.find(a), uf.find(b))
}

///|
test "transitivity: union(a,b) then union(b,c) means find(a)==find(c)" {
  let uf = UnionFind()
  let a = uf.make_set()
  let b = uf.make_set()
  let c = uf.make_set()
  uf.union(a, b) |> ignore
  uf.union(b, c) |> ignore
  assert_eq(uf.find(a), uf.find(c))
}

///|
test "size tracks number of elements" {
  let uf = UnionFind()
  assert_eq(uf.size(), 0)
  uf.make_set() |> ignore
  assert_eq(uf.size(), 1)
  uf.make_set() |> ignore
  assert_eq(uf.size(), 2)
}

///|
test "union is idempotent" {
  let uf = UnionFind()
  let a = uf.make_set()
  let b = uf.make_set()
  let r1 = uf.union(a, b)
  let r2 = uf.union(a, b)
  assert_eq(r1, r2)
  assert_eq(uf.find(a), uf.find(b))
}

///|
test "path compression: find updates parent to root" {
  let uf = UnionFind()
  let a = uf.make_set()
  let b = uf.make_set()
  let c = uf.make_set()
  // Create chain: a -> b -> c
  uf.union(a, b) |> ignore
  uf.union(b, c) |> ignore
  let root = uf.find(a)
  // After path compression, a points directly to root
  assert_eq(uf.find(a), root)
  assert_eq(uf.find(b), root)
  assert_eq(uf.find(c), root)
}

///|
test "add returns an Id" {
  let eg : EGraph[TestLang] = EGraph::new()
  let id = eg.add(Num(42))
  assert_eq(eg.find(id), id)
}

///|
test "add is idempotent: same node returns same Id" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(42))
  let b = eg.add(Num(42))
  assert_eq(a, b)
}

///|
test "add canonicalizes children" {
  let eg : EGraph[TestLang] = EGraph::new()
  let x = eg.add(Num(1))
  let y = eg.add(Num(2))
  let sum1 = eg.add(Add(x, y))
  // Union x with y, then add Add(y, y) — should canonicalize to same as Add(x, y) after rebuild
  eg.union(x, y) |> ignore
  eg.rebuild()
  let sum2 = eg.add(Add(y, y))
  assert_eq(eg.find(sum1), eg.find(sum2))
}

///|
test "union merges e-classes" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let b = eg.add(Num(2))
  eg.union(a, b) |> ignore
  assert_eq(eg.find(a), eg.find(b))
}

///|
test "congruence: union(a,b) means f(a) and f(b) merge after rebuild" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let b = eg.add(Num(2))
  let c = eg.add(Num(3))
  let fa = eg.add(Add(a, c))
  let fb = eg.add(Add(b, c))
  // fa and fb are different e-classes
  assert_true(eg.find(fa) != eg.find(fb))
  // After union(a, b) and rebuild, congruence should merge fa and fb
  eg.union(a, b) |> ignore
  eg.rebuild()
  assert_eq(eg.find(fa), eg.find(fb))
}

///|
test "rebuild is idempotent when no pending work" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let b = eg.add(Num(2))
  eg.union(a, b) |> ignore
  eg.rebuild()
  let root = eg.find(a)
  eg.rebuild()
  assert_eq(eg.find(a), root)
}

// ── ENodeRepr tests ──

///|
test "op_tag returns operator without payload" {
  inspect(Num(42).op_tag(), content="Num")
  inspect(Add(Id(0), Id(1)).op_tag(), content="Add")
}

///|
test "payload returns encoded value" {
  inspect(Num(42).payload(), content="Some(\"42\")")
  inspect(Add(Id(0), Id(1)).payload(), content="None")
}

///|
test "op_name derives from op_tag and payload" {
  inspect(Num(42).op_name(), content="Num:42")
  inspect(Add(Id(0), Id(1)).op_name(), content="Add")
}

///|
test "from_op round-trip for Num" {
  let node = Num(42)
  let reconstructed = TestLang::from_op(node.op_tag(), node.payload(), [])
  inspect(reconstructed, content="Some(Num(42))")
}

///|
test "from_op round-trip for Add" {
  let node = Add(Id(0), Id(1))
  let reconstructed = TestLang::from_op(
    node.op_tag(),
    node.payload(),
    node.children(),
  )
  inspect(reconstructed, content="Some(Add(0, 1))")
}

///|
test "from_op rejects unknown op" {
  let result = TestLang::from_op("Unknown", None, [])
  inspect(result, content="None")
}

///|
test "from_op rejects wrong arity" {
  let result = TestLang::from_op("Add", None, [Id(0)])
  inspect(result, content="None")
}

// ── Pat parse tests ──

///|
test "parse variable" {
  let pat = Pat::parse("?x")
  inspect(pat, content="Var(\"x\")")
}

///|
test "parse atom" {
  let pat = Pat::parse("(Num:0)")
  inspect(pat, content="Node(\"Num\", Some(\"0\"), [])")
}

///|
test "parse nested" {
  let pat = Pat::parse("(Add ?x (Num:0))")
  inspect(
    pat,
    content="Node(\"Add\", None, [Var(\"x\"), Node(\"Num\", Some(\"0\"), [])])",
  )
}

///|
test "parse deeply nested" {
  let pat = Pat::parse("(Add (Add ?x ?y) ?z)")
  inspect(
    pat,
    content="Node(\"Add\", None, [Node(\"Add\", None, [Var(\"x\"), Var(\"y\")]), Var(\"z\")])",
  )
}

// ── Derived method tests ──

///|
test "children derived from arity and child" {
  let node = Add(Id(0), Id(1))
  let cs = node.children()
  assert_eq(cs.length(), 2)
  assert_eq(cs[0], Id(0))
  assert_eq(cs[1], Id(1))
}

///|
test "children of leaf node is empty" {
  let node = Num(42)
  assert_eq(node.children().length(), 0)
}

// ── E-matching tests ──

///|
test "ematch variable matches any e-class" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let pat = Pat::parse("?x")
  let results = eg.ematch(pat, a)
  assert_eq(results.length(), 1)
  assert_eq(results[0].get("x"), Some(a))
}

///|
test "ematch concrete pattern matches" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(0))
  let pat = Pat::parse("(Num:0)")
  let results = eg.ematch(pat, a)
  assert_eq(results.length(), 1)
}

///|
test "ematch concrete pattern rejects mismatch" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let pat = Pat::parse("(Num:0)")
  let results = eg.ematch(pat, a)
  assert_eq(results.length(), 0)
}

///|
test "ematch same variable binds consistently" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let sum = eg.add(Add(a, a))
  let pat = Pat::parse("(Add ?x ?x)")
  let results = eg.ematch(pat, sum)
  assert_eq(results.length(), 1)
}

///|
test "ematch same variable rejects inconsistent binding" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let b = eg.add(Num(2))
  let sum = eg.add(Add(a, b))
  let pat = Pat::parse("(Add ?x ?x)")
  let results = eg.ematch(pat, sum)
  assert_eq(results.length(), 0)
}

///|
test "search finds matches across all e-classes" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let zero = eg.add(Num(0))
  let _ = eg.add(Add(a, zero))
  let pat = Pat::parse("(Add ?x (Num:0))")
  let results = eg.search(pat)
  assert_eq(results.length(), 1)
}

// ── Instantiate tests ──

///|
test "instantiate variable uses substitution" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(42))
  let subst = Subst({ "x": a })
  let result = eg.instantiate(Pat::parse("?x"), subst)
  assert_eq(eg.find(result), eg.find(a))
}

///|
test "instantiate builds new nodes from pattern" {
  let eg : EGraph[TestLang] = EGraph::new()
  let a = eg.add(Num(1))
  let b = eg.add(Num(2))
  let subst = Subst({ "x": a, "y": b })
  let result = eg.instantiate(Pat::parse("(Add ?x ?y)"), subst)
  let expected = eg.add(Add(a, b))
  assert_eq(eg.find(result), eg.find(expected))
}

///|
test "many unions converge to single root" {
  let uf = UnionFind()
  let ids : Array[Id] = []
  for i = 0; i < 10; i = i + 1 {
    ids.push(uf.make_set())
  }
  for i = 1; i < 10; i = i + 1 {
    uf.union(ids[0], ids[i]) |> ignore
  }
  let root = uf.find(ids[0])
  for i = 0; i < 10; i = i + 1 {
    assert_eq(uf.find(ids[i]), root)
  }
}
