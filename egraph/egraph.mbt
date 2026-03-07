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

// ── ENode trait ──

///|
/// Structural access to children of an e-node.
pub(open) trait ENode {
  children(Self) -> Array[Id]
  map_children(Self, (Id) -> Id) -> Self
}

// ── EClass ──

///|
/// An equivalence class containing a set of equivalent e-nodes.
priv struct EClass[L] {
  nodes : Array[L]
}

// ── EGraph ──

///|
/// E-graph: manages e-nodes and e-classes with hashconsing.
priv struct EGraph[L] {
  uf : UnionFind
  classes : Map[Id, EClass[L]]
  memo : Map[L, Id]
  pending : Array[Id]
}

///|
fn[L : Hash + Eq] EGraph::new() -> EGraph[L] {
  { uf: UnionFind(), classes: {}, memo: {}, pending: [] }
}

///|
/// Find the canonical representative.
fn[L] EGraph::find(self : EGraph[L], id : Id) -> Id {
  self.uf.find(id)
}

///|
/// Add an e-node. Returns existing Id if hashcons hit, else creates new e-class.
fn[L : ENode + Hash + Eq] EGraph::add(self : EGraph[L], node : L) -> Id {
  let canonical = node.map_children(fn(child) { self.find(child) })
  match self.memo.get(canonical) {
    Some(id) => self.find(id)
    None => {
      let id = self.uf.make_set()
      self.classes[id] = { nodes: [canonical] }
      self.memo[canonical] = id
      id
    }
  }
}

///|
/// Merge two e-classes. Adds to pending for deferred congruence repair.
fn[L] EGraph::union(self : EGraph[L], a : Id, b : Id) -> Id {
  let root_a = self.find(a)
  let root_b = self.find(b)
  if root_a == root_b {
    return root_a
  }
  let merged = self.uf.union(root_a, root_b)
  let loser = if merged == root_a { root_b } else { root_a }
  match (self.classes.get(loser), self.classes.get(merged)) {
    (Some(loser_class), Some(winner_class)) =>
      for n in loser_class.nodes {
        winner_class.nodes.push(n)
      }
    _ => ()
  }
  self.classes.remove(loser)
  self.pending.push(merged)
  merged
}

///|
/// Restore invariants (congruence closure).
fn[L : ENode + Hash + Eq] EGraph::rebuild(self : EGraph[L]) -> Unit {
  while self.pending.length() > 0 {
    self.pending.clear()
    // Rebuild entire memo with canonicalized nodes
    self.memo.clear()
    // Collect congruences to avoid mutating classes during iteration
    let to_union : Array[(Id, Id)] = []
    for id, eclass in self.classes {
      let canonical_id = self.find(id)
      let new_nodes : Array[L] = []
      let seen : Map[L, Unit] = {}
      for node in eclass.nodes {
        let canonical = node.map_children(fn(child) { self.find(child) })
        if not(seen.contains(canonical)) {
          seen[canonical] = ()
          new_nodes.push(canonical)
        }
      }
      eclass.nodes.clear()
      for n in new_nodes {
        eclass.nodes.push(n)
      }
      for node in new_nodes {
        match self.memo.get(node) {
          Some(existing) =>
            if self.find(existing) != canonical_id {
              to_union.push((canonical_id, self.find(existing)))
            }
          None => self.memo[node] = canonical_id
        }
      }
    }
    // Apply deferred congruence unions
    for pair in to_union {
      self.union(pair.0, pair.1) |> ignore
    }
  }
}
