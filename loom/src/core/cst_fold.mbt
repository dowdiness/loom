// cst_fold.mbt — Memoized catamorphism over CstNode.
//
// The language author provides an algebra: (SyntaxNode, recurse) -> Ast.
// The framework owns the tree walk, hash-keyed caching, and child-visit
// verification. Unchanged subtrees are skipped at O(1) per subtree.

///|
pub struct FoldStats {
  mut reused : Int
  mut recomputed : Int
  mut unvisited : Int
} derive(Debug)

///|
pub fn FoldStats::zero() -> FoldStats {
  { reused: 0, recomputed: 0, unvisited: 0 }
}

///|
/// Cache entry: stores both the CstNode (for collision verification)
/// and the fold result. Hash is used as a fast lookup key, but two
/// different CstNodes can theoretically share the same hash.
priv struct CacheEntry[Ast] {
  cst : @seam.CstNode
  result : Ast
}

///|
/// Memoized catamorphism over CstNode.
///
/// Cache key: CstNode.hash (structural content hash, position-independent).
/// Cache entries store the CstNode for collision verification via Eq.
/// The cache persists across folds — unchanged subtrees are O(1) on cache hit.
/// Stale entries from deleted subtrees remain until the CstFold is dropped;
/// this trades bounded memory overhead for O(1) reuse without tree walks.
pub struct CstFold[Ast] {
  algebra : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  priv cache : Map[Int, CacheEntry[Ast]]
  mut stats : FoldStats
}

///|
pub fn[Ast] CstFold::new(
  algebra : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast,
) -> CstFold[Ast] {
  { algebra, cache: {}, stats: FoldStats::zero() }
}

///|
/// Run the memoized fold over a syntax tree.
/// Resets stats but preserves the cache for incremental reuse.
pub fn[Ast] CstFold::fold(self : CstFold[Ast], root : @seam.SyntaxNode) -> Ast {
  self.stats = FoldStats::zero()
  self.fold_node(root)
}

///|
/// Internal recursive fold with persistent cache lookup.
fn[Ast] CstFold::fold_node(self : CstFold[Ast], node : @seam.SyntaxNode) -> Ast {
  let cst = node.cst_node()
  let hash = cst.hash
  // Check cache — verify structural equality to guard against hash collisions.
  match self.cache.get(hash) {
    Some(entry) if entry.cst == cst => {
      self.stats.reused = self.stats.reused + 1
      return entry.result
    }
    _ => ()
  }
  // Cache miss — call algebra with tracked recurse function
  // Key by (start, end) to distinguish siblings at the same offset (e.g. zero-length nodes)
  let visited : Map[(Int, Int), Unit] = {}
  let recurse = fn(child : @seam.SyntaxNode) -> Ast {
    visited[(child.start(), child.end())] = ()
    self.fold_node(child)
  }
  let result = (self.algebra)(node, recurse)
  self.cache[hash] = { cst, result }
  self.stats.recomputed = self.stats.recomputed + 1
  // Verification: warm cache for unvisited node-children
  for child in node.children() {
    if !visited.contains((child.start(), child.end())) {
      self.stats.unvisited = self.stats.unvisited + 1
      let _ = self.fold_node(child)
    }
  }
  result
}

///|
pub fn[Ast] CstFold::get_stats(self : CstFold[Ast]) -> FoldStats {
  self.stats
}
