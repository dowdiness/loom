// ════════════════════════════════════════════════════════════════════
// E-Graph: Equality Graph Data Structure
// ════════════════════════════════════════════════════════════════════
//
// An e-graph compactly represents many equivalent programs simultaneously.
// It consists of:
//   - E-classes: sets of equivalent e-nodes (expressions that have been
//     proven equal by rewrite rules or explicit union).
//   - E-nodes: operators with children that point to e-classes (not
//     individual expressions), so one e-node implicitly represents all
//     combinations of its children's members.
//   - Union-Find: tracks which e-classes have been merged.
//   - Hashcons (memo): ensures structural sharing — identical e-nodes
//     always map to the same e-class.
//
// Key invariant: **congruence closure** — if two e-nodes have the same
// operator and their corresponding children belong to the same e-classes,
// then those e-nodes must also belong to the same e-class. The `rebuild`
// method restores this invariant after unions.
//
// References:
//   - egg paper: https://arxiv.org/abs/2004.03082
//   - "Fast and Extensible Equality Saturation" (Willsey et al., 2021)
// ════════════════════════════════════════════════════════════════════

///|
/// E-class identifier. Newtype wrapper around Int for type safety.
/// Each Id refers to a slot in the Union-Find's parent array.
pub(all) struct Id(Int) derive(Eq, Compare, Hash, Debug)

///|
/// Domain-specific Show: display as just the integer for readability.
pub impl Show for Id with output(self, logger) {
  let Id(i) = self
  logger.write_string(i.to_string())
}

// ── Union-Find (Disjoint Set Forest) ──
//
// Tracks equivalence classes using a forest of trees.
// Each element points to a parent; the root of each tree is the
// canonical representative ("leader") of its equivalence class.
//
// Two optimizations give near-O(1) amortized operations:
//   1. **Path compression** (in `find`): after finding the root,
//      repoint every node on the path directly to the root.
//   2. **Union by rank** (in `union`): always attach the shorter
//      tree under the taller one, keeping trees shallow.

///|
/// Tree height upper bound for union by rank.
type Rank = Int

///|
/// Union-Find with path compression and union by rank.
/// `parents[i]` is the parent of element i; roots point to themselves.
/// `ranks[i]` is an upper bound on the height of the subtree rooted at i.
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
///
/// Two-pass algorithm:
///   Pass 1 — Chase parent pointers to find the root (the element
///            whose parent is itself).
///   Pass 2 — Walk the same path again, repointing every node
///            directly to the root ("path compression").
///
/// After compression, subsequent finds on the same elements are O(1).
/// Overall amortized cost: O(α(n)) ≈ O(1) per operation.
fn UnionFind::find(self : UnionFind, id : Id) -> Id {
  // Pass 1: walk to root
  let mut current = id
  while self.parents[current.0] != current {
    current = self.parents[current.0]
  }
  let root = current
  // Pass 2: compress path — flatten the tree
  current = id
  while current != root {
    let next = self.parents[current.0]
    self.parents[current.0] = root
    current = next
  }
  root
}

///|
/// Merge two equivalence classes by rank. Returns the new representative.
///
/// Union by rank keeps trees balanced:
///   - Attach the shorter tree under the taller one (rank unchanged).
///   - If both have equal rank, pick one as root and increment its rank.
///
/// This ensures tree height is at most O(log n), which combined with
/// path compression gives O(α(n)) amortized per operation.
fn UnionFind::union(self : UnionFind, a : Id, b : Id) -> Id {
  let root_a = self.find(a)
  let root_b = self.find(b)
  if root_a == root_b {
    return root_a
  }
  let Id(ra) = root_a
  let Id(rb) = root_b
  if self.ranks[ra] < self.ranks[rb] {
    self.parents[ra] = root_b // shorter tree (a) goes under taller tree (b)
    root_b
  } else if self.ranks[ra] > self.ranks[rb] {
    self.parents[rb] = root_a // shorter tree (b) goes under taller tree (a)
    root_a
  } else {
    self.parents[rb] = root_a // equal rank: b goes under a
    self.ranks[ra] = self.ranks[ra] + 1 // a's rank increases
    root_a
  }
}

///|
/// Current number of elements.
fn UnionFind::size(self : UnionFind) -> Int {
  self.parents.length()
}

// ── ENode trait ──
//
// Structural interface for e-node children.
//
// Design: uses indexed access (`arity` + `child`) instead of
// `children() -> Array[Id]` to avoid allocation in the e-matching
// hot loop, where we compare patterns against many nodes per e-class.
// The convenience method `children()` is provided as a default for
// non-hot-path code that wants a collected array.
//
// Implementors must provide: arity, child, map_children.
// Default derived: children.

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
//
// Serialization bridge between concrete e-node types (L) and the
// language-independent pattern type (Pat).
//
// Why not just use Eq?
//   `Eq` compares L == L (same type). But e-matching compares a Pat
//   (language-independent) against an L (language-specific) — different
//   types. ENodeRepr decomposes L into (tag, payload) so patterns can
//   match without knowing the concrete type.
//
// Design: `op_tag()` returns a string literal (zero allocation),
// `payload()` only allocates when a value exists. The tag/payload
// split happens at Pat parse time, not at match time, so the ematch
// hot loop does only cheap comparisons.
//
// Implementors must provide: op_tag, payload, from_op.
// Default derived: op_name.

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

// ── Pat (Pattern AST) ──
//
// Patterns are language-independent: they use string tags instead of
// concrete enum variants, so the same pattern engine works for any
// language that implements ENodeRepr.
//
// Example pattern: "(Add ?x (Num:0))"
//   → Node("Add", None, [Var("x"), Node("Num", Some("0"), [])])
//
// The tag/payload split (e.g. "Num:0" → tag="Num", payload=Some("0"))
// happens at parse time in Pat::parse, NOT at match time. This means
// the ematch hot loop only does cheap string equality checks.

///|
/// Pattern: either a variable or a concrete operator with child patterns.
/// Node stores (tag, payload?, children) — split at parse time, not match time.
pub(all) enum Pat {
  Var(String)
  Node(String, String?, Array[Pat])
} derive(Eq, Show, Debug)

///|
/// Match result: maps pattern variable names to e-class Ids.
///
/// Example: matching "(Add ?x ?y)" against Add(Id(0), Id(1))
///   → Subst({ "x": Id(0), "y": Id(1) })
pub(all) struct Subst(Map[String, Id]) derive(Show, Debug)

///|
/// Look up a pattern variable binding.
#alias("_[_]")
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
/// An equivalence class: a set of e-nodes that have been proven equivalent.
///
/// All nodes in the same e-class represent the same semantic value.
/// For example, after learning that `a * 2 == a << 1`, both e-nodes
/// would appear in the same e-class.
priv struct EClass[L] {
  nodes : Array[L]
}

// ── EGraph ──

///|
/// E-graph: manages e-nodes and e-classes with hashconsing.
///
/// Four core components:
///   - `uf`: Union-Find that tracks which e-class Ids are equivalent.
///   - `classes`: maps each canonical Id to its EClass (set of e-nodes).
///   - `memo`: hashcons table — maps each canonical e-node to its e-class Id.
///     Ensures structural sharing: adding the same e-node twice returns
///     the same Id. Also used to detect congruences during rebuild.
///   - `pending`: Ids that were recently merged and need congruence repair.
///     After union(a, b), rebuild must check if any e-nodes that pointed
///     to a or b should now be considered congruent.
priv struct EGraph[L] {
  uf : UnionFind
  classes : Map[Id, EClass[L]]
  memo : Map[L, Id]
  pending : Array[Id]

  fn[L : Hash + Eq] new() -> EGraph[L]
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
/// Total number of e-class slots (Union-Find entries).
/// This grows monotonically — unions merge classes but don't remove slots.
fn[L] EGraph::size(self : EGraph[L]) -> Int {
  self.uf.size()
}

///|
/// Add an e-node to the e-graph. Returns its e-class Id.
///
/// Hashconsing: before inserting, canonicalize the node's children
/// (replace each child Id with its Union-Find root) and check the
/// memo table. If an identical canonical node already exists, return
/// its existing e-class Id — this is what makes the e-graph compact.
/// Otherwise, create a fresh e-class containing just this node.
fn[L : ENode + Hash + Eq] EGraph::add(self : EGraph[L], node : L) -> Id {
  // Step 1: Canonicalize children so Add(x, y) and Add(find(x), find(y))
  //         map to the same memo entry.
  let canonical = node.map_children(fn(child) { self.find(child) })
  // Step 2: Check hashcons — have we seen this exact canonical node before?
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
/// Merge two e-classes, asserting that a == b.
///
/// 1. Union the Ids in the Union-Find (determines winner/loser by rank).
/// 2. Move all e-nodes from the loser's e-class into the winner's.
/// 3. Remove the loser's e-class from the classes map.
/// 4. Push the merged Id onto `pending` so that `rebuild` will later
///    check for new congruences caused by this merge.
///
/// Note: this does NOT immediately restore the congruence invariant.
/// Call `rebuild()` after a batch of unions to restore it.
fn[L] EGraph::union(self : EGraph[L], a : Id, b : Id) -> Id {
  let root_a = self.find(a)
  let root_b = self.find(b)
  if root_a == root_b {
    return root_a
  }
  let merged = self.uf.union(root_a, root_b)
  let loser = if merged == root_a { root_b } else { root_a }
  // Merge e-class contents: move loser's nodes into winner
  match (self.classes.get(loser), self.classes.get(merged)) {
    (Some(loser_class), Some(winner_class)) =>
      winner_class.nodes.append(loser_class.nodes[:])
    _ => ()
  }
  self.classes.remove(loser)
  self.pending.push(merged) // schedule for congruence repair
  merged
}

///|
/// Restore the congruence invariant after a batch of unions.
///
/// Congruence closure: if f(a) and f(b) are in the e-graph and a == b
/// (same e-class), then f(a) and f(b) must also be in the same e-class.
/// Unions can violate this, so rebuild fixes it by:
///
///   1. Canonicalize all e-nodes (update children to Union-Find roots).
///   2. Deduplicate nodes within each e-class (same canonical form = same node).
///   3. Rebuild the memo (hashcons) table from scratch.
///   4. Detect congruences: if two e-classes contain the same canonical
///      e-node, they must be merged.
///   5. Apply discovered merges — which may create new congruences,
///      so repeat until no more pending work (fixed-point loop).
fn[L : ENode + Hash + Eq] EGraph::rebuild(self : EGraph[L]) -> Unit {
  while self.pending.length() > 0 {
    self.pending.clear()
    self.memo.clear()
    // Collect congruences to avoid mutating classes during iteration
    let to_union : Array[(Id, Id)] = []
    for id, eclass in self.classes {
      let canonical_id = self.find(id)
      // Canonicalize and deduplicate nodes in this e-class
      let new_nodes : Array[L] = []
      let seen : @hashset.HashSet[L] = @hashset.new()
      for node in eclass.nodes {
        let canonical = node.map_children(child => self.find(child))
        if seen.add_and_check(canonical) {
          new_nodes.push(canonical)
        }
      }
      eclass.nodes.clear()
      eclass.nodes.append(new_nodes[:])
      // Rebuild memo and detect congruences
      for node in new_nodes {
        match self.memo.get(node) {
          // Another e-class already has this canonical node → congruence!
          Some(existing) =>
            if self.find(existing) != canonical_id {
              to_union.push((canonical_id, self.find(existing)))
            }
          // First time seeing this canonical node → register in memo
          None => self.memo[node] = canonical_id
        }
      }
    }
    // Apply discovered congruences (may trigger further pending work)
    for pair in to_union {
      self.union(pair.0, pair.1) |> ignore
    }
  }
}

// ── E-Matching ──
//
// E-matching finds all ways a pattern matches within an e-class.
// Unlike normal pattern matching (one expression → one result),
// e-matching searches across all equivalent expressions in an e-class,
// producing multiple substitutions.
//
// Algorithm (recursive, per e-class):
//   - Var("x"): matches anything — bind x to this e-class Id.
//   - Node(tag, payload, child_pats): for each e-node in the e-class
//     whose operator matches (tag, payload, arity), recursively match
//     each child pattern against the corresponding child e-class.
//     Combine results using substitution merging (ensuring consistency:
//     if ?x appears twice, both occurrences must bind to the same e-class).

///|
/// E-match a pattern against an e-class, returning all valid substitutions.
///
/// Returns one Subst per successful match. A pattern with N variables
/// produces substitutions mapping each variable to an e-class Id.
fn[L : ENode + ENodeRepr] EGraph::ematch(
  self : EGraph[L],
  pattern : Pat,
  eclass_id : Id,
) -> Array[Subst] {
  let canonical_id = self.find(eclass_id)
  match pattern {
    // A variable matches any e-class — just record the binding
    Var(name) => {
      let subst : Map[String, Id] = {}
      subst[name] = canonical_id
      [Subst(subst)]
    }
    // A concrete operator pattern must match some e-node in this e-class
    Node(tag, payload, child_pats) => {
      let results : Array[Subst] = []
      match self.classes.get(canonical_id) {
        None => ()
        Some(eclass) =>
          for node in eclass.nodes {
            // Check operator match: tag, payload, and arity must all agree
            if node.op_tag() == tag &&
              node.payload() == payload &&
              node.arity() == child_pats.length() {
              // Match children left-to-right, threading substitutions through.
              // Start with one empty substitution; each child may multiply
              // or filter the set of valid substitutions.
              let mut substs : Array[Subst] = [Subst({})]
              for i = 0; i < child_pats.length(); i = i + 1 {
                let child_id = self.find(node.child(i))
                let new_substs : Array[Subst] = []
                for s in substs {
                  // Recursively match child pattern against child e-class
                  let child_results = self.ematch(child_pats[i], child_id)
                  for s2 in child_results {
                    // Merge: ensures variable consistency (e.g., ?x == ?x)
                    match merge_substs(s, s2) {
                      Some(merged) => new_substs.push(merged)
                      None => () // conflict — discard this combination
                    }
                  }
                }
                substs = new_substs
              }
              results.append(substs[:])
            }
          }
      }
      results
    }
  }
}

///|
/// Merge two substitutions. Returns None if they disagree on a variable binding.
///
/// This enforces variable consistency: if pattern "(Add ?x ?x)" matches
/// a node Add(a, b), the substitution for the first ?x (binding a) must
/// agree with the substitution for the second ?x (binding b).
/// If a != b (different e-classes), merge returns None → match fails.
fn merge_substs(a : Subst, b : Subst) -> Subst? {
  let Subst(a_map) = a
  let Subst(b_map) = b
  let result = a_map.copy()
  for k, v in b_map {
    match result.get(k) {
      Some(existing) => if existing != v { return None } // conflict!
      None => result[k] = v
    }
  }
  Some(Subst(result))
}

///|
/// Search the entire e-graph for pattern matches across all e-classes.
///
/// Iterates over every canonical e-class and runs ematch against it.
/// Deduplicates by canonical Id to avoid matching the same e-class twice
/// (the classes map may contain stale keys that map to the same canonical Id).
fn[L : ENode + ENodeRepr] EGraph::search(
  self : EGraph[L],
  pattern : Pat,
) -> Array[(Id, Subst)] {
  let results : Array[(Id, Subst)] = []
  let visited : @hashset.HashSet[Id] = @hashset.new()
  for id, _ in self.classes {
    let canonical_id = self.find(id)
    if not(visited.add_and_check(canonical_id)) {
      continue
    }
    let substs = self.ematch(pattern, canonical_id)
    for s in substs {
      results.push((canonical_id, s))
    }
  }
  results
}

///|
/// Instantiate a pattern with a substitution, adding new nodes to the e-graph.
///
/// This is the "apply" half of rewrite rules: after `search` finds matches,
/// `instantiate` builds the right-hand side of the rule using the matched
/// variable bindings.
///
/// Example: rule "(Add ?x (Num:0)) => ?x" (additive identity)
///   1. search finds: Subst({ "x": Id(3) }) for some Add(3, 0)
///   2. instantiate("?x", subst) returns Id(3) — the simplified result
///   3. union the original Add e-class with Id(3) to record the equivalence
fn[L : ENodeRepr + ENode + Hash + Eq] EGraph::instantiate(
  self : EGraph[L],
  pattern : Pat,
  subst : Subst,
) -> Id {
  let Subst(subst_map) = subst
  match pattern {
    // Variable: look up the binding in the substitution
    Var(name) =>
      match subst_map.get(name) {
        Some(id) => self.find(id)
        None => abort("unbound pattern variable: \{name}")
      }
    // Operator: recursively instantiate children, then add the node
    Node(tag, payload, child_pats) => {
      let child_ids : Array[Id] = []
      for child_pat in child_pats {
        child_ids.push(self.instantiate(child_pat, subst))
      }
      // Use from_op to construct the concrete language node from (tag, payload, children)
      match L::from_op(tag, payload, child_ids) {
        Some(node) => self.add(node)
        None => abort("from_op failed for tag: \{tag}")
      }
    }
  }
}

// ── Rewrite Rules ──
//
// A rewrite rule has a left-hand side (lhs) pattern to search for,
// and a right-hand side (rhs) pattern to instantiate. When applied:
//   1. Search the e-graph for all matches of lhs → get (e-class, Subst) pairs
//   2. For each match, instantiate rhs using the Subst → get a new e-class Id
//   3. Union the matched e-class with the new Id (asserting lhs == rhs)
//   4. Rebuild to restore congruence
//
// Optional `condition` allows conditional rewrites: the rule only fires
// when the condition function returns true for a given substitution.

///|
/// A rewrite rule: lhs pattern → rhs pattern.
priv struct Rewrite {
  name : String
  lhs : Pat
  rhs : Pat
  condition : ((Subst) -> Bool)?
}

///|
/// Convenience constructor: parse s-expression strings into a Rewrite.
fn rewrite(name : String, lhs : String, rhs : String) -> Rewrite raise Error {
  { name, lhs: Pat::parse(lhs), rhs: Pat::parse(rhs), condition: None }
}

///|
/// Apply pre-collected matches for a rewrite rule.
///
/// For each match:
///   1. Check the optional condition (skip if it returns false).
///   2. Instantiate the rhs pattern using the matched substitution.
///   3. Union the matched e-class with the instantiated rhs e-class.
///
/// Returns the number of new unions performed.
/// Used by both `apply_rewrite` (single-rule convenience) and
/// `Runner::run` (batched two-phase equality saturation).
fn[L : ENode + ENodeRepr + Hash + Eq] EGraph::apply_matches(
  self : EGraph[L],
  rule : Rewrite,
  matches : Array[(Id, Subst)],
) -> Int {
  let mut applied = 0
  for pair in matches {
    let (matched_id, subst) = pair
    match rule.condition {
      Some(cond) => if not(cond(subst)) { continue }
      None => ()
    }
    let new_id = self.instantiate(rule.rhs, subst)
    if self.find(matched_id) != self.find(new_id) {
      self.union(matched_id, new_id) |> ignore
      applied = applied + 1
    }
  }
  applied
}

///|
/// Apply a rewrite rule to the e-graph (search + apply in one call).
///
/// Convenience wrapper: searches for lhs matches, then applies them.
/// Caller should call `rebuild()` afterward to restore congruence.
fn[L : ENode + ENodeRepr + Hash + Eq] EGraph::apply_rewrite(
  self : EGraph[L],
  rule : Rewrite,
) -> Int {
  let matches = self.search(rule.lhs)
  self.apply_matches(rule, matches)
}

// ── Extraction ──
//
// Extraction selects the lowest-cost equivalent expression from an e-class.
// Since each e-class may contain many equivalent e-nodes (and their children
// are e-classes too), extraction must choose the best e-node at each level.
//
// Algorithm (bottom-up fixed-point):
//   1. Iterate over all e-classes, computing the cost of each e-node using
//      the cost function and the best known child costs.
//   2. Track the cheapest node per canonical e-class.
//   3. Repeat until costs stabilize (fixed point). For acyclic e-graphs
//      this converges in one pass; cyclic ones (e.g., commutativity) may
//      need multiple passes.
//   4. Reconstruct the optimal expression tree by following best-node
//      choices from the root, producing a RecExpr (flattened array).

///|
/// A recursively-defined expression stored as a flat array.
/// nodes[i]'s children are Ids that index into this same array.
/// The root is always the last element.
priv struct RecExpr[L] {
  nodes : Array[L]
}

///|
/// Return the root node (last element).
fn[L] RecExpr::root(self : RecExpr[L]) -> L {
  self.nodes[self.nodes.length() - 1]
}

///|
/// Cost function type: given an e-node and a lookup for child costs,
/// return the node's cost. Using a function type (not a trait) because
/// the cost function doesn't vary by Self — it varies by use case.
struct CostFn[L]((L, (Id) -> Int) -> Int)

///|
/// Simplest cost function: AST size (1 per node + sum of children).
fn[L : ENode] ast_size() -> CostFn[L] {
  CostFn(fn(node, child_cost) {
    let mut cost = 1
    for i = 0; i < node.arity(); i = i + 1 {
      cost = cost + child_cost(node.child(i))
    }
    cost
  })
}

///|
/// Extract the lowest-cost expression from an e-class.
///
/// Returns (cost, RecExpr) where RecExpr is a flattened tree with the
/// root as the last element. Children in RecExpr nodes use Ids that
/// index into the RecExpr's nodes array.
fn[L : ENode] EGraph::extract(
  self : EGraph[L],
  root : Id,
  cost_fn : CostFn[L],
) -> (Int, RecExpr[L]) {
  let best_cost : Map[Id, Int] = {}
  let best_node : Map[Id, L] = {}
  let max_cost = 1_000_000_000
  let CostFn(f) = cost_fn
  // Child cost lookup: children of canonical nodes are already canonical,
  // so no extra find() needed inside the cost function.
  let child_cost = fn(child) {
    match best_cost.get(child) {
      Some(c) => c
      None => max_cost
    }
  }
  // Fixed-point iteration: compute minimum cost per e-class
  let mut changed = true
  while changed {
    changed = false
    for id, eclass in self.classes {
      let canonical_id = self.find(id)
      for node in eclass.nodes {
        // Canonicalize children for cost lookup
        let canonical = node.map_children(fn(child) { self.find(child) })
        let cost = f(canonical, child_cost)
        let current_best = match best_cost.get(canonical_id) {
          Some(c) => c
          None => max_cost
        }
        if cost < current_best {
          best_cost[canonical_id] = cost
          best_node[canonical_id] = canonical
          changed = true
        }
      }
    }
  }
  // Reconstruct the optimal expression tree into a RecExpr
  let canonical_root = self.find(root)
  let rec_nodes : Array[L] = []
  let id_to_idx : Map[Id, Id] = {}
  reconstruct(best_node, canonical_root, rec_nodes, id_to_idx, self) |> ignore
  let final_cost = match best_cost.get(canonical_root) {
    Some(c) => c
    None => max_cost
  }
  (final_cost, { nodes: rec_nodes })
}

///|
/// Recursively reconstruct the optimal expression tree into a flat array.
/// Returns the index (as Id) in rec_nodes where this subtree was placed.
fn[L : ENode] reconstruct(
  best_node : Map[Id, L],
  eclass_id : Id,
  rec_nodes : Array[L],
  id_to_idx : Map[Id, Id],
  egraph : EGraph[L],
) -> Id {
  // Check if already reconstructed (handles DAG sharing)
  match id_to_idx.get(eclass_id) {
    Some(idx) => return idx
    None => ()
  }
  let node = match best_node.get(eclass_id) {
    Some(n) => n
    None => abort("no best node for e-class: \{eclass_id}")
  }
  // Recursively reconstruct children first, remapping Ids to array indices
  let remapped = node.map_children(fn(child) {
    reconstruct(best_node, egraph.find(child), rec_nodes, id_to_idx, egraph)
  })
  let idx = Id(rec_nodes.length())
  rec_nodes.push(remapped)
  id_to_idx[eclass_id] = idx
  idx
}

// ── Runner (Equality Saturation Loop) ──
//
// The Runner automates the equality saturation process: repeatedly
// search for pattern matches, apply rewrite rules, and rebuild the
// e-graph until no more changes occur (saturation) or a resource
// limit is hit.
//
// Each iteration follows the Read-Write-Rebuild pattern:
//   1. **Read phase**: search all rewrite rules, collecting matches.
//      Matches are collected BEFORE any writes so that all rules see
//      a consistent snapshot of the e-graph.
//   2. **Write phase**: instantiate the right-hand sides and union
//      them with their matched e-classes.
//   3. **Rebuild phase**: restore the congruence invariant, which may
//      expose new matches for the next iteration.
//
// Stopping conditions:
//   - Saturated: no rewrite rule produced a new union (fixed point).
//   - IterLimit: reached the maximum number of iterations.
//   - NodeLimit: the e-graph exceeded the maximum number of e-nodes.

///|
/// Why the equality saturation loop stopped.
priv enum StopReason {
  Saturated
  IterLimit
  NodeLimit
} derive(Eq, Show, Debug)

///|
/// Equality saturation executor.
///
/// Wraps an e-graph and runs rewrite rules until saturation or a limit.
/// `roots` are Ids of interest (e.g., the expression to optimize) —
/// currently for bookkeeping, future use in extraction after saturation.
priv struct Runner[L] {
  egraph : EGraph[L]
  roots : Array[Id]
  iter_limit : Int
  node_limit : Int
}

///|
/// Create a Runner with default limits.
/// iter_limit defaults to 30, node_limit defaults to 10_000.
fn[L] Runner::new(
  egraph : EGraph[L],
  roots? : Array[Id] = [],
  iter_limit? : Int = 30,
  node_limit? : Int = 10_000,
) -> Runner[L] {
  { egraph, roots, iter_limit, node_limit }
}

///|
/// Run equality saturation: apply rewrite rules until saturation or a limit.
///
/// Returns why the loop stopped.
fn[L : ENode + ENodeRepr + Hash + Eq] Runner::run(
  self : Runner[L],
  rules : Array[Rewrite],
) -> StopReason {
  for iter = 0; iter < self.iter_limit; iter = iter + 1 {
    // === Read Phase ===
    // Collect all matches before any writes, so every rule sees a
    // consistent e-graph snapshot (no cross-rule interference).
    let all_matches : Array[(Rewrite, Array[(Id, Subst)])] = []
    for rule in rules {
      let matches = self.egraph.search(rule.lhs)
      all_matches.push((rule, matches))
    }
    // === Write Phase ===
    // Apply rewrites at matched locations.
    let mut applied = 0
    for pair in all_matches {
      let (rule, matches) = pair
      applied = applied + self.egraph.apply_matches(rule, matches)
    }
    // === Rebuild Phase ===
    self.egraph.rebuild()
    // === Termination Check ===
    if applied == 0 {
      return Saturated
    }
    if self.egraph.size() > self.node_limit {
      return NodeLimit
    }
  }
  IterLimit
}
