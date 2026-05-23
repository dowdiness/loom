///|
/// Unified `Parser[Ast]` — wraps `@incremental.ImperativeParser` and publishes
/// a coherent parse snapshot plus derived read-only `@incr.Derived` views.
///
/// Accepts two update methods:
/// - `apply_edit(edit, new_source)` — CST-node-level reuse via the engine.
/// - `set_source(source)` — full reparse, discarding incremental state.
///
/// Both methods update one private snapshot `Signal` inside `Runtime::batch`
/// after the engine has advanced, so downstream consumers see one coherent
/// parse state regardless of which method was called.
///
/// Accepts an optional external `Runtime` so downstream derived cells can
/// share the dependency graph.
///
/// See ADR 2026-04-17 and the implementation plan at
/// `docs/plans/2026-04-17-unified-parser.md` for rationale.
pub struct Parser[Ast] {
  priv engine : @incremental.ImperativeParser[Ast]
  priv rt : @incr.Runtime
  priv snapshot_signal : @incr.Signal[@incremental.ParseSnapshot[Ast]]
  priv snapshot_view : @incr.Derived[@incremental.ParseSnapshot[Ast]]
  priv source_view : @incr.Derived[String]
  priv syntax_view : @incr.Derived[@seam.SyntaxNode]
  priv ast_view : @incr.Derived[Ast]
  priv diagnostics_view : @incr.Derived[@core.DiagnosticSet]
}

///|
/// Construct a new `Parser`. Primes the engine via an initial `parse()`
/// so the published snapshot and derived views reflect a real parse rather
/// than the empty initial state.
///
/// If `runtime` is supplied the parser joins that reactive graph;
/// otherwise a fresh `Runtime` is created. Sharing lets downstream
/// consumers subscribe to `parser.source()` / `parser.ast()` on the
/// same runtime as their own memos.
pub fn[Ast : Eq] Parser::new(
  source : String,
  lang : @incremental.ImperativeLanguage[Ast],
  runtime? : @incr.Runtime,
) -> Parser[Ast] {
  let engine = @incremental.ImperativeParser::new(source, lang)
  let initial_snapshot = engine.parse()
  let rt = match runtime {
    Some(r) => r
    None => @incr.Runtime::new()
  }
  let snapshot_signal = @incr.Signal::new(
    rt,
    initial_snapshot,
    label="parser_snapshot",
  )
  let snapshot_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_signal.get().copy() },
    label="parser_snapshot_view",
  )
  let source_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_signal.get().source },
    label="parser_source_view",
  )
  let syntax_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_signal.get().syntax },
    label="parser_syntax_view",
  )
  let ast_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_signal.get().ast },
    label="parser_ast_view",
  )
  let diagnostics_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_signal.get().diagnostics.copy() },
    label="parser_diagnostics_view",
  )
  {
    engine,
    rt,
    snapshot_signal,
    snapshot_view,
    source_view,
    syntax_view,
    ast_view,
    diagnostics_view,
  }
}

///|
/// Replace the source text, discarding incremental state. The snapshot
/// signal is updated atomically inside `Runtime::batch`.
///
/// Identity is a no-op: if `source` equals the engine's current source,
/// this returns immediately without reparsing or touching any signal.
/// Editors and LSP flows that emit repeated identical snapshots thus
/// avoid a redundant full parse + fold pass (downstream Memos would
/// backdate anyway, but the engine's incremental state would have been
/// discarded for nothing).
pub fn[Ast : Eq] Parser::set_source(
  self : Parser[Ast],
  source : String,
) -> Unit {
  if source == self.engine.get_source() {
    return
  }
  self.rt.batch(fn() { self.snapshot_signal.set(self.engine.reset(source)) })
}

///|
/// Apply a text `Edit` using CST-node-level reuse. The snapshot signal is
/// updated atomically inside `Runtime::batch` after the engine has advanced.
pub fn[Ast : Eq] Parser::apply_edit(
  self : Parser[Ast],
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  self.rt.batch(fn() {
    self.snapshot_signal.set(self.engine.edit(edit, new_source))
  })
}

///|
/// Reactive view of the complete current parse snapshot.
pub fn[Ast] Parser::snapshot(
  self : Parser[Ast],
) -> @incr.Derived[@incremental.ParseSnapshot[Ast]] {
  self.snapshot_view
}

///|
/// Reactive view of the current source text.
pub fn[Ast] Parser::source(self : Parser[Ast]) -> @incr.Derived[String] {
  self.source_view
}

///|
/// Reactive view of the current recovered CST.
pub fn[Ast] Parser::syntax_tree(
  self : Parser[Ast],
) -> @incr.Derived[@seam.SyntaxNode] {
  self.syntax_view
}

///|
/// Reactive view of the current AST.
pub fn[Ast] Parser::ast(self : Parser[Ast]) -> @incr.Derived[Ast] {
  self.ast_view
}

///|
/// Reactive view of the current parse diagnostics, derived from the
/// current parse snapshot.
pub fn[Ast] Parser::diagnostics(
  self : Parser[Ast],
) -> @incr.Derived[@core.DiagnosticSet] {
  self.diagnostics_view
}

///|
/// Return the `Runtime` backing this parser so downstream derived cells
/// can join the same dependency graph.
pub fn[Ast] Parser::runtime(self : Parser[Ast]) -> @incr.Runtime {
  self.rt
}
