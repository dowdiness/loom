///|
/// Complete syntax-only result of a parse pass.
///
/// `SyntaxSnapshot` keeps the source text, recovered CST, structured
/// diagnostics, and incremental reuse count together for consumers that do not
/// need an AST fold.
pub struct SyntaxSnapshot {
  source : String
  syntax : @seam.SyntaxNode
  diagnostics : @core.DiagnosticSet
  reuse_count : Int
} derive(Eq, Debug)

///|
/// Copy a syntax snapshot, cloning its mutable diagnostic collection.
pub fn SyntaxSnapshot::copy(self : SyntaxSnapshot) -> SyntaxSnapshot {
  {
    source: self.source,
    syntax: self.syntax,
    diagnostics: self.diagnostics.copy(),
    reuse_count: self.reuse_count,
  }
}

///|
fn syntax_snapshot_from_parse(
  snapshot : @incremental.ParseSnapshot[Unit],
) -> SyntaxSnapshot {
  {
    source: snapshot.source,
    syntax: snapshot.syntax,
    diagnostics: snapshot.diagnostics.copy(),
    reuse_count: snapshot.reuse_count,
  }
}

///|
/// Reactive syntax-only parser handle.
///
/// `SyntaxParser` wraps an `ImperativeParser[Unit]` and publishes coherent
/// source, syntax tree, diagnostics, and reuse-count views without requiring an
/// AST type or AST equality. Use this for lexer/parser integrations whose AST
/// is unavailable, expensive to fold, or not naturally `Eq`.
pub struct SyntaxParser {
  priv engine : @incremental.ImperativeParser[Unit]
  priv rt : @incr.Runtime
  priv snapshot_input : @incr.Input[SyntaxSnapshot]
  priv snapshot_view : @incr.Derived[SyntaxSnapshot]
  priv source_view : @incr.Derived[String]
  priv syntax_view : @incr.Derived[@seam.SyntaxNode]
  priv diagnostics_view : @incr.Derived[@core.DiagnosticSet]
}

///|
/// Construct a new syntax-only parser. Primes the engine via an initial
/// `parse()` so published views reflect a real parse.
pub fn SyntaxParser::new(
  source : String,
  lang : @incremental.ImperativeLanguage[Unit],
  runtime? : @incr.Runtime,
) -> SyntaxParser {
  let engine = @incremental.ImperativeParser::new(source, lang)
  let initial_snapshot = syntax_snapshot_from_parse(engine.parse())
  let rt = match runtime {
    Some(r) => r
    None => @incr.Runtime::new()
  }
  let snapshot_input = @incr.Input(
    rt,
    initial_snapshot,
    label="syntax_parser_snapshot",
  )
  let snapshot_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_input.get().copy() },
    label="syntax_parser_snapshot_view",
  )
  let source_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_input.get().source },
    label="syntax_parser_source_view",
  )
  let syntax_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_input.get().syntax },
    label="syntax_parser_syntax_view",
  )
  let diagnostics_view = @incr.Derived::Derived(
    rt,
    fn() { snapshot_input.get().diagnostics.copy() },
    label="syntax_parser_diagnostics_view",
  )
  {
    engine,
    rt,
    snapshot_input,
    snapshot_view,
    source_view,
    syntax_view,
    diagnostics_view,
  }
}

///|
/// Replace the source text, discarding incremental state. Identical source is
/// a no-op, matching `Parser::set_source`.
pub fn SyntaxParser::set_source(self : SyntaxParser, source : String) -> Unit {
  if source == self.engine.get_source() {
    return
  }
  self.rt.batch(fn() {
    self.snapshot_input.set(
      syntax_snapshot_from_parse(self.engine.reset(source)),
    )
  })
}

///|
/// Apply a text `Edit` using CST-node-level reuse. The snapshot input is
/// updated atomically inside `Runtime::batch` after the engine advances.
pub fn SyntaxParser::apply_edit(
  self : SyntaxParser,
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  self.rt.batch(fn() {
    self.snapshot_input.set(
      syntax_snapshot_from_parse(self.engine.edit(edit, new_source)),
    )
  })
}

///|
/// Reactive view of the complete current syntax-only parse snapshot.
pub fn SyntaxParser::snapshot(
  self : SyntaxParser,
) -> @incr.Derived[SyntaxSnapshot] {
  self.snapshot_view
}

///|
/// Reactive view of the current source text.
pub fn SyntaxParser::source(self : SyntaxParser) -> @incr.Derived[String] {
  self.source_view
}

///|
/// Reactive view of the current recovered CST.
pub fn SyntaxParser::syntax_tree(
  self : SyntaxParser,
) -> @incr.Derived[@seam.SyntaxNode] {
  self.syntax_view
}

///|
/// Reactive view of the current parse diagnostics.
pub fn SyntaxParser::diagnostics(
  self : SyntaxParser,
) -> @incr.Derived[@core.DiagnosticSet] {
  self.diagnostics_view
}

///|
/// Return the `Runtime` backing this parser so downstream derived cells can
/// join the same dependency graph.
pub fn SyntaxParser::runtime(self : SyntaxParser) -> @incr.Runtime {
  self.rt
}
