///|
/// E-class identifier. Newtype for type safety.
pub(all) struct Id(Int) derive(Eq, Compare, Hash, Debug)

///|
/// Domain-specific Show: display as just the integer for readability.
pub impl Show for Id with output(self, logger) {
  let Id(i) = self
  logger.write_string(i.to_string())
}

///|
/// Tree height upper bound for union by rank.
type Rank = Int

///|
/// Union-Find with path compression and union by rank.
priv struct UnionFind {
  parents : Array[Id]
  ranks : Array[Rank]

  fn new() -> UnionFind
} derive(Default, Show, Debug)

///|
fn UnionFind::new() -> UnionFind {
  UnionFind::default()
}

///|
/// Create a new equivalence class. Returns a fresh Id.
fn UnionFind::make_set(self : UnionFind) -> Id {
  let id = Id(self.parents.length())
  self.parents.push(id)
  self.ranks.push(0)
  id
}

///|
/// Find the canonical representative with iterative path compression.
fn UnionFind::find(self : UnionFind, id : Id) -> Id {
  // Pass 1: walk to root
  let mut current = id
  while self.parents[current.0] != current {
    current = self.parents[current.0]
  }
  let root = current
  // Pass 2: compress path
  current = id
  while current != root {
    let next = self.parents[current.0]
    self.parents[current.0] = root
    current = next
  }
  root
}

///|
/// Merge two equivalence classes. Returns the representative Id.
fn UnionFind::union(self : UnionFind, a : Id, b : Id) -> Id {
  let root_a = self.find(a)
  let root_b = self.find(b)
  if root_a == root_b {
    return root_a
  }
  let Id(ra) = root_a
  let Id(rb) = root_b
  if self.ranks[ra] < self.ranks[rb] {
    self.parents[ra] = root_b
    root_b
  } else if self.ranks[ra] > self.ranks[rb] {
    self.parents[rb] = root_a
    root_a
  } else {
    self.parents[rb] = root_a
    self.ranks[ra] = self.ranks[ra] + 1
    root_a
  }
}

///|
/// Current number of elements.
fn UnionFind::size(self : UnionFind) -> Int {
  self.parents.length()
}
