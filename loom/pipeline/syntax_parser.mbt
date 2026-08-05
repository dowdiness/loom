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
/// Derive the syntax-only adapter view directly from `Parser`'s canonical
/// snapshot input. Keeping this projection package-private avoids exposing the
/// mutable input while also avoiding the extra Derived and defensive copy used
/// by the public `Parser::snapshot` interface.
fn Parser::derive_syntax_snapshot(
  self : Parser[Unit],
) -> @incr.Derived[SyntaxSnapshot] {
  @incr.Derived(
    self.rt,
    () => syntax_snapshot_from_parse(self.snapshot_input.get()),
    label="syntax_parser_snapshot_view",
  )
}

///|
/// Reactive syntax-only parser handle.
///
/// `SyntaxParser` adapts `Parser[Unit]` into a syntax-only interface. The
/// underlying parser owns engine advancement, coherent reactive publication,
/// runtime ownership, and source-update semantics; this adapter only removes
/// the meaningless `Unit` AST from the public snapshot.
///
/// Use this for lexer/parser integrations whose AST is unavailable, expensive
/// to fold, or not naturally `Eq`.
pub struct SyntaxParser {
  priv parser : Parser[Unit]
  priv snapshot_view : @incr.Derived[SyntaxSnapshot]
}

///|
/// Construct a new syntax-only parser. Primes the engine via an initial
/// `parse()` so published views reflect a real parse.
///
/// Runtime ownership matches `Parser::new`: supplying `runtime~` joins a
/// caller-owned graph, while omitting it creates a fresh parser-owned runtime.
/// Downstream syntax-only attachments should still use `parser.runtime()`.
pub fn SyntaxParser::new(
  source_id : @core.SourceId,
  source : String,
  lang : @incremental.ImperativeLanguage[Unit],
  runtime? : @incr.Runtime,
) -> SyntaxParser {
  let parser = Parser::new(source_id, source, lang, runtime?)
  let snapshot_view = parser.derive_syntax_snapshot()
  { parser, snapshot_view }
}

///|
/// Replace the source text, discarding incremental state. Identical source is
/// a no-op, matching `Parser::set_source`.
pub fn SyntaxParser::set_source(self : SyntaxParser, source : String) -> Unit {
  self.parser.set_source(source)
}

///|
/// Apply a text `Edit` using CST-node-level reuse. The snapshot input is
/// updated atomically inside `Runtime::batch` after the engine advances.
pub fn SyntaxParser::apply_edit(
  self : SyntaxParser,
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  self.parser.apply_edit(edit, new_source)
}

///|
pub fn SyntaxParser::source_id(self : SyntaxParser) -> @core.SourceId {
  self.parser.source_id()
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
  self.parser.source()
}

///|
/// Reactive view of the current recovered CST.
pub fn SyntaxParser::syntax_tree(
  self : SyntaxParser,
) -> @incr.Derived[@seam.SyntaxNode] {
  self.parser.syntax_tree()
}

///|
/// Reactive view of the current parse diagnostics.
pub fn SyntaxParser::diagnostics(
  self : SyntaxParser,
) -> @incr.Derived[@core.DiagnosticSet] {
  self.parser.diagnostics()
}

///|
/// Return the `Runtime` backing this parser so downstream derived cells can
/// join the same dependency graph. Parser-attached syntax-only pipelines
/// should own their own `Scope` / `Watch` lifecycle and dispose that scope
/// separately from the parser.
pub fn SyntaxParser::runtime(self : SyntaxParser) -> @incr.Runtime {
  self.parser.runtime()
}
