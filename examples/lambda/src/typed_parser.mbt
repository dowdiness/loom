// Unified parser + type checker integration for the lambda calculus.
//
// Composes `@loom.Parser[Term]` with `@typecheck.build_typecheck_pipeline_with_index`
// by bridging SyntaxNode → TypedTerm through a thin Memo. The bridge reads
// `parser.syntax_tree().get()` inside its closure — that registers the
// parser's syntax-tree Memo as a reactive dependency so the pipeline
// recomputes on every published edit.
//
// Typechecking runs off the CST rather than `Term` because `Term` drops
// lambda type annotations; `convert_from_cst` preserves them. The `None`
// branch (lex / recoverable parse failure) yields a `TypedTerm::Error`
// instead of aborting, matching the FFI path in canopy.

///|
/// A bidirectional type-checker attached to a unified lambda `Parser`.
///
/// Holds a `Scope` owning the bridge Memo + typecheck pipeline cells, an
/// `Observer` that anchors the result Memo as a GC root, and a `TypecheckIndex`
/// for query-by-DefId access. The observer keeps the whole reactive chain
/// reachable through `Runtime::gc()` — including the parser's syntax-tree
/// and AST memos, which would otherwise be eligible for sweep as unobserved
/// interior cells.
///
/// `dispose()` releases the GC root and tears down the type-checker scope.
/// The parser is unaffected.
pub(all) struct TypecheckAttachment {
  scope : @incr.Scope
  observer : @incr.Observer[@typecheck.ModuleTypeResult]
  index : @typecheck.TypecheckIndex
}

///|
/// Read the latest type-check result. Triggers pull verification if stale.
pub fn TypecheckAttachment::get(
  self : TypecheckAttachment,
) -> @typecheck.ModuleTypeResult {
  self.observer.get()
}

///|
/// Dispose the type-checker scope (children → observer → owned cells).
/// Idempotent. Does not dispose the parser.
pub fn TypecheckAttachment::dispose(self : TypecheckAttachment) -> Unit {
  self.scope.dispose()
}

///|
/// Attach the bidirectional type checker to a unified lambda `Parser`.
///
/// Returns a `TypecheckAttachment` that owns a fresh `Scope` rooted at
/// `parser.runtime()`. The attachment registers a persistent `Observer`
/// on the result Memo, both for ergonomic untracked reads and to keep the
/// reactive chain alive across `Runtime::gc()`.
pub fn attach_typecheck(
  parser : @loom.Parser[@ast.Term],
) -> TypecheckAttachment {
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let typed_memo = scope.memo(
    fn() {
      match parser.syntax_tree().get() {
        Some(tree) => @typecheck.convert_from_cst(tree)
        None => @typecheck.TypedTerm::Error("parse")
      }
    },
    label="typed_term_bridge",
  )
  let (results, index) = @typecheck.build_typecheck_pipeline_with_index(
    rt, scope, typed_memo,
  )
  let observer = scope.add_observer(results.observe())
  { scope, observer, index }
}
