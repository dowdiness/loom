// ── Test language ──

///|
priv enum TestLang {
  Num(Int)
  Add(Id, Id)
} derive(Eq, Hash, Compare, Show, Debug)

///|
impl ENode for TestLang with children(self) {
  match self {
    Num(_) => []
    Add(a, b) => [a, b]
  }
}

///|
impl ENode for TestLang with map_children(self, f) {
  match self {
    Num(_) => self
    Add(a, b) => Add(f(a), f(b))
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
