///|
/// Session-global token interner shared across all parse calls in this process.
/// Tokens are accumulated, never cleared — deduplication improves with use.
///
/// Safe to share across parsers for different grammars: Interner keys on
/// (RawKind, text) with no dependency on trivia policy.
pub let core_interner : @seam.Interner = @seam.Interner::new()

///|
/// Session-global node interner shared across all parse calls in this process.
///
/// trivia_kind invariant: all grammars registered in this process MUST use the
/// same raw kind value for their whitespace token. NodeInterner equality is
/// structural (kind + children) and does NOT include token_count, which depends
/// on the trivia_kind passed to build_tree_fully_interned. Mixing grammars with
/// different trivia_kinds in one process silently canonicalises to the
/// first-seen token_count, producing incorrect values for subsequent callers.
///
/// For single-grammar processes (the common case) this is unconditionally safe.
pub let core_node_interner : @seam.NodeInterner = @seam.NodeInterner::new()
