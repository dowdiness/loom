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
/// Required: arity, child, map_children.
/// Default: children (derived from arity + child).
pub(open) trait ENode {
  arity(Self) -> Int
  child(Self, Int) -> Id
  map_children(Self, (Id) -> Id) -> Self
  children(Self) -> Array[Id] = _
}

///|
impl ENode with children(self) {
  let arr : Array[Id] = []
  for i = 0; i < self.arity(); i = i + 1 {
    arr.push(self.child(i))
  }
  arr
}

// ── ENodeRepr trait ──

///|
/// Serialization bridge for pattern matching.
/// Required: op_tag, payload, from_op.
/// Default: op_name (derived from op_tag + payload).
pub(open) trait ENodeRepr {
  op_tag(Self) -> String
  payload(Self) -> String?
  from_op(String, String?, Array[Id]) -> Self?
  op_name(Self) -> String = _
}

///|
impl ENodeRepr with op_name(self) {
  match self.payload() {
    Some(p) => "\{self.op_tag()}:\{p}"
    None => self.op_tag()
  }
}

// ── Pat ──

///|
/// Pattern: either a variable or a concrete operator with child patterns.
/// Node stores (tag, payload?, children) — split at parse time, not match time.
pub(all) enum Pat {
  Var(String)
  Node(String, String?, Array[Pat])
} derive(Eq, Show, Debug)

///|
/// Match result: pattern variable -> e-class Id substitution.
pub(all) struct Subst(Map[String, Id]) derive(Show, Debug)

///|
/// Look up a pattern variable binding.
pub fn Subst::get(self : Subst, name : String) -> Id? {
  self.0.get(name)
}

// ── Pat parser ──

///|
/// Parse an s-expression string into a Pat.
/// Grammar:
///   pat  = var | '(' op pat* ')'
///   var  = '?' identifier
///   op   = tag (':' payload)?
pub fn Pat::parse(s : String) -> Pat raise Error {
  let chars = s.to_array()
  let (pat, _) = parse_pat(chars, 0)
  pat
}

///|
fn parse_pat(chars : Array[Char], pos : Int) -> (Pat, Int) raise Error {
  let mut i = skip_ws(chars, pos)
  if i >= chars.length() {
    raise Failure::Failure("unexpected end of input")
  }
  if chars[i] == '?' {
    // Variable
    i = i + 1
    let start = i
    while i < chars.length() && is_ident_char(chars[i]) {
      i = i + 1
    }
    if i == start {
      raise Failure::Failure("expected variable name after '?'")
    }
    let name = String::from_array(chars[start:i].to_array())
    (Var(name), i)
  } else if chars[i] == '(' {
    // Node: (op pat*)
    i = i + 1
    i = skip_ws(chars, i)
    // Read operator token (may contain ':')
    let op_start = i
    while i < chars.length() &&
          chars[i] != ' ' &&
          chars[i] != ')' &&
          chars[i] != '(' {
      i = i + 1
    }
    let op_token = String::from_array(chars[op_start:i].to_array())
    let (tag, payload) = split_at_colon(op_token)
    // Read children
    let children : Array[Pat] = []
    i = skip_ws(chars, i)
    while i < chars.length() && chars[i] != ')' {
      let (child, next_i) = parse_pat(chars, i)
      children.push(child)
      i = skip_ws(chars, next_i)
    }
    if i >= chars.length() {
      raise Failure::Failure("expected ')'")
    }
    i = i + 1 // skip ')'
    (Node(tag, payload, children), i)
  } else {
    // Bare atom — treat as Node with no children
    let start = i
    while i < chars.length() && is_ident_char(chars[i]) {
      i = i + 1
    }
    let token = String::from_array(chars[start:i].to_array())
    let (tag, payload) = split_at_colon(token)
    (Node(tag, payload, []), i)
  }
}

///|
/// Split "Tag:payload" on first ':'. Returns (tag, payload).
fn split_at_colon(s : String) -> (String, String?) {
  let chars = s.to_array()
  let mut colon_idx = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ':' {
      colon_idx = i
      break
    }
  }
  if colon_idx < 0 {
    (s, None)
  } else {
    let tag = String::from_array(chars[:colon_idx].to_array())
    let payload = String::from_array(chars[colon_idx + 1:].to_array())
    (tag, Some(payload))
  }
}

///|
fn skip_ws(chars : Array[Char], pos : Int) -> Int {
  let mut i = pos
  while i < chars.length() && chars[i] == ' ' {
    i = i + 1
  }
  i
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == ':' ||
  c == '-'
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
        let canonical = node.map_children((child) => { self.find(child) })
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

// ── E-Matching ──

///|
/// E-match a pattern against an e-class, returning all valid substitutions.
fn[L : ENode + ENodeRepr] EGraph::ematch(
  self : EGraph[L],
  pattern : Pat,
  eclass_id : Id,
) -> Array[Subst] {
  let canonical_id = self.find(eclass_id)
  match pattern {
    Var(name) => {
      let subst : Map[String, Id] = {}
      subst[name] = canonical_id
      [Subst(subst)]
    }
    Node(tag, payload, child_pats) => {
      let results : Array[Subst] = []
      match self.classes.get(canonical_id) {
        None => ()
        Some(eclass) =>
          for node in eclass.nodes {
            if node.op_tag() == tag &&
              node.payload() == payload &&
              node.arity() == child_pats.length() {
              // Start with a single empty substitution
              let mut substs : Array[Subst] = [Subst({})]
              for i = 0; i < child_pats.length(); i = i + 1 {
                let child_id = self.find(node.child(i))
                let new_substs : Array[Subst] = []
                for s in substs {
                  let child_results = self.ematch(child_pats[i], child_id)
                  for s2 in child_results {
                    match merge_substs(s, s2) {
                      Some(merged) => new_substs.push(merged)
                      None => ()
                    }
                  }
                }
                substs = new_substs
              }
              for s in substs {
                results.push(s)
              }
            }
          }
      }
      results
    }
  }
}

///|
/// Merge two substitutions. Returns None if they disagree on a variable binding.
fn merge_substs(a : Subst, b : Subst) -> Subst? {
  let Subst(a_map) = a
  let Subst(b_map) = b
  let result : Map[String, Id] = {}
  for k, v in a_map {
    result[k] = v
  }
  for k, v in b_map {
    match result.get(k) {
      Some(existing) => if existing != v { return None }
      None => result[k] = v
    }
  }
  Some(Subst(result))
}

///|
/// Search the entire e-graph for pattern matches.
fn[L : ENode + ENodeRepr] EGraph::search(
  self : EGraph[L],
  pattern : Pat,
) -> Array[(Id, Subst)] {
  let results : Array[(Id, Subst)] = []
  let visited : Map[Id, Unit] = {}
  for id, _ in self.classes {
    let canonical_id = self.find(id)
    if visited.contains(canonical_id) {
      continue
    }
    visited[canonical_id] = ()
    let substs = self.ematch(pattern, canonical_id)
    for s in substs {
      results.push((canonical_id, s))
    }
  }
  results
}

///|
/// Instantiate a pattern with a substitution, adding nodes to the e-graph.
fn[L : ENodeRepr + ENode + Hash + Eq] EGraph::instantiate(
  self : EGraph[L],
  pattern : Pat,
  subst : Subst,
) -> Id {
  let Subst(subst_map) = subst
  match pattern {
    Var(name) =>
      match subst_map.get(name) {
        Some(id) => self.find(id)
        None => abort("unbound pattern variable: \{name}")
      }
    Node(tag, payload, child_pats) => {
      let child_ids : Array[Id] = []
      for child_pat in child_pats {
        child_ids.push(self.instantiate(child_pat, subst))
      }
      let op = match payload {
        Some(p) => "\{tag}:\{p}"
        None => tag
      }
      match L::from_op(tag, payload, child_ids) {
        Some(node) => self.add(node)
        None => abort("from_op failed for op: \{op}")
      }
    }
  }
}
