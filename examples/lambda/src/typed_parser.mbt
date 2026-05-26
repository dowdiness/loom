// Unified parser + type checker integration for the lambda calculus.
//
// Composes `@loom.Parser[Term]` with `@typecheck.build_typecheck_pipeline_with_index`
// by bridging SyntaxNode → TypedTerm through a thin Derived. The bridge reads
// `parser.syntax_tree().get_or_abort()` inside its closure — that registers the
// parser's syntax-tree Derived as a reactive dependency so the pipeline
// recomputes on every published edit.
//
// Typechecking runs off the CST rather than `Term` because `Term` drops
// lambda type annotations; `convert_from_cst` preserves them. The parser
// publishes a recovered syntax tree for every source snapshot.

///|
/// A bidirectional type-checker attached to a unified lambda `Parser`.
///
/// Holds a `Scope` owning the bridge Derived + typecheck pipeline cells, a
/// `Watch` that anchors the result Derived as a GC root, and a `TypecheckIndex`
/// for query-by-DefId access. The watch keeps the whole reactive chain
/// reachable through `Runtime::gc()` — including the parser's syntax-tree
/// and AST derived cells, which would otherwise be eligible for sweep as
/// unobserved interior cells.
///
/// `dispose()` releases the GC root and tears down the type-checker scope.
/// The parser is unaffected.
pub(all) struct TypecheckAttachment {
  scope : @incr.Scope
  watch : @incr.Watch[@typecheck.ModuleTypeResult]
  index : @typecheck.TypecheckIndex
}

///|
/// Read the latest type-check result. Triggers pull verification if stale.
pub fn TypecheckAttachment::get(
  self : TypecheckAttachment,
) -> @typecheck.ModuleTypeResult {
  self.watch.read_or_abort()
}

///|
/// Dispose the type-checker scope (children → watch → owned cells).
/// Idempotent. Does not dispose the parser.
pub fn TypecheckAttachment::dispose(self : TypecheckAttachment) -> Unit {
  self.scope.dispose()
}

///|
/// Attach the bidirectional type checker to a unified lambda `Parser`.
///
/// Returns a `TypecheckAttachment` that owns a fresh `Scope` rooted at
/// `parser.runtime()`. The attachment registers a persistent `Watch`
/// on the result Derived, both for ergonomic untracked reads and to keep the
/// reactive chain alive across `Runtime::gc()`.
pub fn attach_typecheck(
  parser : @loom.Parser[@ast.Term],
) -> TypecheckAttachment {
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let typed_derived = scope.derived(
    fn() { @typecheck.convert_from_cst(parser.syntax_tree().get_or_abort()) },
    label="typed_term_bridge",
  )
  let (results, index) = @typecheck.build_typecheck_pipeline_with_index(
    rt, scope, typed_derived,
  )
  let watch = scope.add_watch(results.watch())
  { scope, watch, index }
}
