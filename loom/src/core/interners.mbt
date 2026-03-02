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
/// Violation is detected at runtime via core_registered_trivia_kind: the first
/// grammar to call build_tree_generic registers its trivia_kind; subsequent
/// calls with a different trivia_kind abort the process.
pub let core_node_interner : @seam.NodeInterner = @seam.NodeInterner::new()

///|
/// Registered trivia raw kind for core_node_interner.
/// None before first parse; set on first build_tree_generic call.
/// Subsequent calls with a different raw kind abort immediately.
pub let core_registered_trivia_kind : Ref[@seam.RawKind?] = Ref::new(None)
