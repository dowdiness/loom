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
} derive(Show)

///|
pub fn FoldStats::zero() -> FoldStats {
  { reused: 0, recomputed: 0, unvisited: 0 }
}

///|
/// Memoized catamorphism over CstNode.
///
/// Cache key: CstNode.hash (structural content hash, position-independent).
/// Traversal: top-down with cache check first — unchanged subtrees are O(1).
pub struct CstFold[Ast] {
  algebra : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  mut cache : Map[Int, Ast]
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
/// Swaps in a fresh cache (old cache used for lookups), resets stats.
pub fn[Ast] CstFold::fold(
  self : CstFold[Ast],
  root : @seam.SyntaxNode,
) -> Ast {
  let old_cache = self.cache
  self.cache = {}
  self.stats = FoldStats::zero()
  self.fold_node(root, old_cache)
}

///|
/// Internal recursive fold with old-cache lookup.
fn[Ast] CstFold::fold_node(
  self : CstFold[Ast],
  node : @seam.SyntaxNode,
  old_cache : Map[Int, Ast],
) -> Ast {
  let hash = node.cst_node().hash
  // Check old cache (from previous fold invocation)
  match old_cache.get(hash) {
    Some(cached) => {
      self.cache[hash] = cached
      self.stats.reused = self.stats.reused + 1
      return cached
    }
    None => ()
  }
  // Check new cache (structural duplicate within same tree)
  match self.cache.get(hash) {
    Some(cached) => {
      self.stats.reused = self.stats.reused + 1
      return cached
    }
    None => ()
  }
  // Cache miss — call algebra with tracked recurse function
  let visited : Map[Int, Unit] = {}
  let recurse = fn(child : @seam.SyntaxNode) -> Ast {
    visited[child.start()] = ()
    self.fold_node(child, old_cache)
  }
  let result = (self.algebra)(node, recurse)
  self.cache[hash] = result
  self.stats.recomputed = self.stats.recomputed + 1
  // Verification: warm cache for unvisited node-children
  for child in node.children() {
    if not(visited.contains(child.start())) {
      self.stats.unvisited = self.stats.unvisited + 1
      let _ = self.fold_node(child, old_cache)
    }
  }
  result
}

///|
pub fn[Ast] CstFold::get_stats(self : CstFold[Ast]) -> FoldStats {
  self.stats
}
