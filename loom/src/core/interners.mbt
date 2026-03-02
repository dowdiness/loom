///|
/// Session-global token interner shared across all parse calls in this process.
/// Tokens are accumulated, never cleared — deduplication improves with use.
///
/// Safe to share across parsers for different grammars: Interner keys on
/// (RawKind, text) with no dependency on trivia policy.
pub let core_interner : @seam.Interner = @seam.Interner::new()

///|
/// Per-trivia-kind node interners. Each distinct whitespace RawKind gets its
/// own NodeInterner, so grammars with different trivia_kinds can coexist in
/// the same process without corrupting each other's token_count values.
///
/// NodeInterner equality is structural (kind + children) and does NOT include
/// token_count, which depends on the trivia_kind passed to
/// build_tree_fully_interned. Sharing one interner across grammars with
/// different trivia_kinds silently canonicalises to the first grammar's
/// token_count, producing incorrect values for subsequent callers.
///
/// Lookup via get_core_node_interner(trivia_kind) — O(n) over the number of
/// distinct trivia kinds registered in this process (almost always 1).
let core_node_interners : Array[(@seam.RawKind, @seam.NodeInterner)] = []

///|
/// Return the NodeInterner for `trivia_kind`, creating one on first use.
fn get_core_node_interner(trivia_kind : @seam.RawKind) -> @seam.NodeInterner {
  for i = 0; i < core_node_interners.length(); i = i + 1 {
    let (k, interner) = core_node_interners[i]
    if k == trivia_kind {
      return interner
    }
  }
  let interner = @seam.NodeInterner::new()
  core_node_interners.push((trivia_kind, interner))
  interner
}
