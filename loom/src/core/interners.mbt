///|
/// Process-global token interner retained for callers that explicitly choose
/// `@seam.build_tree_interned` / `build_tree_fully_interned`.
///
/// The generic parser no longer uses a process-global interner: its CST tokens
/// are source spans, and global node/token interners would retain full historic
/// source buffers. This value remains available as a compatibility utility for
/// workloads that prefer canonical owned token text over source-span tokens.
pub let core_interner : @seam.Interner = @seam.Interner::new()
