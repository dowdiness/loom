///|
/// Unified `Parser[Ast]` — wraps `@incremental.ImperativeParser` and publishes
/// derived state (source, syntax tree, AST, diagnostics) as read-only
/// `@incr.Memo` views.
///
/// Accepts two update methods:
/// - `apply_edit(edit, new_source)` — CST-node-level reuse via the engine.
/// - `set_source(source)` — full reparse, discarding incremental state.
///
/// Both methods update four private `Signal` cells inside a single
/// `Runtime::batch` after the engine has advanced, so downstream consumers
/// see one coherent update regardless of which method was called.
///
/// Accepts an optional external `Runtime` so downstream derived cells can
/// share the dependency graph.
///
/// See ADR 2026-04-17 and the implementation plan at
/// `docs/plans/2026-04-17-unified-parser.md` for rationale.
pub struct Parser[Ast] {
  priv engine : @incremental.ImperativeParser[Ast]
  priv rt : @incr.Runtime
  priv source_signal : @incr.Signal[String]
  priv syntax_signal : @incr.Signal[@seam.SyntaxNode?]
  priv ast_signal : @incr.Signal[Ast]
  priv diagnostics_signal : @incr.Signal[Array[String]]
  priv source_view : @incr.Memo[String]
  priv syntax_view : @incr.Memo[@seam.SyntaxNode?]
  priv ast_view : @incr.Memo[Ast]
  priv diagnostics_view : @incr.Memo[Array[String]]
}

///|
/// Construct a new `Parser`. Primes the engine via an initial `parse()`
/// so the published `source`/`syntax_tree`/`ast`/`diagnostics` values
/// reflect a real parse rather than the empty initial state.
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
  let initial_ast = engine.parse()
  let initial_syntax = engine.get_syntax_tree()
  let initial_diagnostics = engine.diagnostics()
  let rt = match runtime {
    Some(r) => r
    None => @incr.Runtime::new()
  }
  let source_signal = @incr.Signal::new(rt, source, label="parser_source")
  let syntax_signal = @incr.Signal::new(
    rt,
    initial_syntax,
    label="parser_syntax",
  )
  let ast_signal = @incr.Signal::new(rt, initial_ast, label="parser_ast")
  let diagnostics_signal = @incr.Signal::new(
    rt,
    initial_diagnostics,
    label="parser_diagnostics",
  )
  let source_view = @incr.Memo::new(
    rt,
    fn() { source_signal.get() },
    label="parser_source_view",
  )
  let syntax_view = @incr.Memo::new(
    rt,
    fn() { syntax_signal.get() },
    label="parser_syntax_view",
  )
  let ast_view = @incr.Memo::new(
    rt,
    fn() { ast_signal.get() },
    label="parser_ast_view",
  )
  let diagnostics_view = @incr.Memo::new(
    rt,
    fn() { diagnostics_signal.get() },
    label="parser_diagnostics_view",
  )
  {
    engine,
    rt,
    source_signal,
    syntax_signal,
    ast_signal,
    diagnostics_signal,
    source_view,
    syntax_view,
    ast_view,
    diagnostics_view,
  }
}

///|
/// Replace the source text, discarding incremental state. All four
/// published cells are updated atomically inside `Runtime::batch`.
pub fn[Ast : Eq] Parser::set_source(
  self : Parser[Ast],
  source : String,
) -> Unit {
  self.rt.batch(fn() {
    let ast = self.engine.reset(source)
    self.source_signal.set(source)
    self.syntax_signal.set(self.engine.get_syntax_tree())
    self.ast_signal.set(ast)
    self.diagnostics_signal.set(self.engine.diagnostics())
  })
}

///|
/// Apply a text `Edit` using CST-node-level reuse. All four published
/// cells are updated atomically inside `Runtime::batch` after the engine
/// has advanced.
pub fn[Ast : Eq] Parser::apply_edit(
  self : Parser[Ast],
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  self.rt.batch(fn() {
    let ast = self.engine.edit(edit, new_source)
    self.source_signal.set(new_source)
    self.syntax_signal.set(self.engine.get_syntax_tree())
    self.ast_signal.set(ast)
    self.diagnostics_signal.set(self.engine.diagnostics())
  })
}

///|
/// Reactive view of the current source text.
pub fn[Ast] Parser::source(self : Parser[Ast]) -> @incr.Memo[String] {
  self.source_view
}

///|
/// Reactive view of the current CST. `None` after a lex error.
pub fn[Ast] Parser::syntax_tree(
  self : Parser[Ast],
) -> @incr.Memo[@seam.SyntaxNode?] {
  self.syntax_view
}

///|
/// Reactive view of the current AST.
pub fn[Ast] Parser::ast(self : Parser[Ast]) -> @incr.Memo[Ast] {
  self.ast_view
}

///|
/// Reactive view of the current parse diagnostics, updated atomically
/// with `syntax_tree`.
pub fn[Ast] Parser::diagnostics(
  self : Parser[Ast],
) -> @incr.Memo[Array[String]] {
  self.diagnostics_view
}

///|
/// Return the `Runtime` backing this parser so downstream derived cells
/// can join the same dependency graph.
pub fn[Ast] Parser::runtime(self : Parser[Ast]) -> @incr.Runtime {
  self.rt
}
