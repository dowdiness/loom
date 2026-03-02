///|
/// Session-global token interner shared across all parse calls in this process.
/// Tokens are accumulated, never cleared — deduplication improves with use.
pub let core_interner : @seam.Interner = @seam.Interner::new()

///|
/// Session-global node interner shared across all parse calls.
pub let core_node_interner : @seam.NodeInterner = @seam.NodeInterner::new()
