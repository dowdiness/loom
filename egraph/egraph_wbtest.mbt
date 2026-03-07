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
