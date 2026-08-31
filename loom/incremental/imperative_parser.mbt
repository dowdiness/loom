// Generic incremental parser — Wagner-Graham damage tracking strategy.
// Language-specific behavior injected via ImperativeLanguage[Ast] vtable.

///|
pub struct ImperativeParser[Ast] {
  priv source_id : @core.SourceId
  priv lang : ImperativeLanguage[Ast]
  priv mut source : String
  priv mut snapshot : ParseSnapshot[Ast]?
  priv mut prev_cst : @seam.CstNode? // cached CstNode from last successful parse
}

///|
pub fn[Ast] ImperativeParser::new(
  source_id : @core.SourceId,
  source : String,
  lang : ImperativeLanguage[Ast],
) -> ImperativeParser[Ast] {
  { source_id, lang, source, snapshot: None, prev_cst: None }
}

///|
fn[Ast] ImperativeParser::accept_tree(
  self : ImperativeParser[Ast],
  source : String,
  syntax : @seam.SyntaxNode,
  diagnostics : @core.DiagnosticSet,
  reuse_count : Int,
) -> ParseSnapshot[Ast] {
  let new_cst = syntax.cst_node()
  let ast = match (self.prev_cst, self.snapshot) {
    (Some(old_cst), Some(snapshot)) if old_cst == new_cst => snapshot.ast
    _ => (self.lang.to_ast)(syntax)
  }
  let snapshot : ParseSnapshot[Ast] = {
    source,
    syntax,
    ast,
    diagnostics: diagnostics.copy(),
    reuse_count,
  }
  self.snapshot = Some(snapshot)
  self.prev_cst = Some(new_cst)
  snapshot.copy()
}

///|
pub fn[Ast] ImperativeParser::parse(
  self : ImperativeParser[Ast],
) -> ParseSnapshot[Ast] raise Failure {
  let (syntax, diagnostics, reuse_count) = (self.lang.full_parse)(
    self.source_id,
    self.source,
  )
  self.accept_tree(self.source, syntax, diagnostics, reuse_count)
}

///|
pub fn[Ast] ImperativeParser::edit(
  self : ImperativeParser[Ast],
  edit : @core.Edit,
  new_source : String,
) -> ParseSnapshot[Ast] raise Failure {
  self.source = new_source
  if self.snapshot is None {
    return self.parse()
  }
  match self.snapshot {
    Some(old_snapshot) => {
      let (syntax, diagnostics, reuse_count) = (self.lang.incremental_parse)(
        self.source_id,
        new_source,
        old_snapshot.syntax,
        edit,
      )
      self.accept_tree(new_source, syntax, diagnostics, reuse_count)
    }
    None => self.parse()
  }
}

///|
/// Apply a validated atomic transition through an optional language fast path,
/// falling back to a transactional full parse.
pub fn[Ast] ImperativeParser::apply_changes(
  self : ImperativeParser[Ast],
  changes : @text_change.ChangeSet,
  new_source : String,
) -> ParseSnapshot[Ast] raise Failure {
  match (self.snapshot, self.lang.atomic_parse) {
    (Some(old_snapshot), Some(parse_atomic)) =>
      match
        parse_atomic(self.source_id, new_source, old_snapshot.syntax, changes) {
        Some((syntax, diagnostics, reuse_count)) => {
          self.source = new_source
          self.accept_tree(new_source, syntax, diagnostics, reuse_count)
        }
        None => self.reset(new_source)
      }
    _ => self.reset(new_source)
  }
}

///|
/// Reset the parser to a new source string, discarding all incremental state.
/// Use this when the source changes in a way that cannot be expressed as an
/// Edit (e.g. after a structural edit regenerates the text in a hybrid editor).
pub fn[Ast] ImperativeParser::reset(
  self : ImperativeParser[Ast],
  source : String,
) -> ParseSnapshot[Ast] raise Failure {
  let (syntax, diagnostics, reuse_count) = (self.lang.full_parse)(
    self.source_id,
    source,
  )
  self.source = source
  self.snapshot = None
  self.prev_cst = None
  self.accept_tree(source, syntax, diagnostics, reuse_count)
}

///|
pub fn[Ast] ImperativeParser::current(
  self : ImperativeParser[Ast],
) -> ParseSnapshot[Ast]? {
  self.snapshot.map(snapshot => snapshot.copy())
}

///|
pub fn[Ast] ImperativeParser::get_tree(self : ImperativeParser[Ast]) -> Ast? {
  self.snapshot.map(snapshot => snapshot.ast)
}

///|
pub fn[Ast] ImperativeParser::get_source_id(
  self : ImperativeParser[Ast],
) -> @core.SourceId {
  self.source_id
}

///|
pub fn[Ast] ImperativeParser::get_source(
  self : ImperativeParser[Ast],
) -> String {
  self.source
}

///|
pub fn[Ast] ImperativeParser::diagnostics(
  self : ImperativeParser[Ast],
) -> @core.DiagnosticSet {
  match self.snapshot {
    Some(snapshot) => snapshot.diagnostics.copy()
    None => @core.DiagnosticSet::empty()
  }
}

///|
pub fn[Ast] ImperativeParser::get_last_reuse_count(
  self : ImperativeParser[Ast],
) -> Int {
  match self.snapshot {
    Some(snapshot) => snapshot.reuse_count
    None => 0
  }
}

///|
pub fn[Ast] ImperativeParser::get_fold_stats(
  self : ImperativeParser[Ast],
) -> @core.FoldStats? {
  self.lang.get_fold_stats.map(fn(f) { f() })
}

///|
/// Return the last SyntaxNode produced by parse/edit, if any.
/// Useful for consumers that need CST-level access alongside the Ast result.
pub fn[Ast] ImperativeParser::get_syntax_tree(
  self : ImperativeParser[Ast],
) -> @seam.SyntaxNode? {
  self.snapshot.map(snapshot => snapshot.syntax)
}
