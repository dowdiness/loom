///|
/// Complete result of a parse pass.
///
/// `ParseSnapshot` keeps the source text, recovered CST, folded AST,
/// structured diagnostics, and incremental reuse count together so parser
/// consumers cannot observe mismatched side-channel state.
pub struct ParseSnapshot[Ast] {
  source : String
  syntax : @seam.SyntaxNode
  ast : Ast
  diagnostics : @core.DiagnosticSet
  reuse_count : Int
} derive(Eq, Debug)

///|
/// Copy a parse snapshot, cloning its mutable diagnostic collection.
pub fn[Ast] ParseSnapshot::copy(
  self : ParseSnapshot[Ast],
) -> ParseSnapshot[Ast] {
  {
    source: self.source,
    syntax: self.syntax,
    ast: self.ast,
    diagnostics: self.diagnostics.copy(),
    reuse_count: self.reuse_count,
  }
}

///|
/// Token-erased vtable for incremental language integration.
///
/// The token type is erased into closures at call site, keeping
/// `ImperativeParser[Ast]` generic over the Ast type.
///
/// `full_parse` — initial (non-incremental) parse. Returns the recovered
///   syntax tree, structured diagnostics, and reuse count (0 for full parses).
///
/// `incremental_parse` — edit-triggered reparse. Receives the old SyntaxNode
///   so the closure can call SyntaxNode::cst_node() for the reuse cursor.
///   Returns the recovered syntax tree, structured diagnostics, and reuse
///   count. The closure captures and updates TokenBuffer and parser state.
///
/// `to_ast` — convert a syntax tree to Ast.
pub struct ImperativeLanguage[Ast] {
  priv full_parse : (String) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int)
  priv incremental_parse : (String, @seam.SyntaxNode, @core.Edit) -> (
    @seam.SyntaxNode,
    @core.DiagnosticSet,
    Int,
  )
  priv to_ast : (@seam.SyntaxNode) -> Ast
  priv get_fold_stats : (() -> @core.FoldStats)?
}

///|
/// Constructor for ImperativeLanguage vtable.
pub fn[Ast] ImperativeLanguage::new(
  full_parse~ : (String) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int),
  incremental_parse~ : (String, @seam.SyntaxNode, @core.Edit) -> (
    @seam.SyntaxNode,
    @core.DiagnosticSet,
    Int,
  ),
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  get_fold_stats? : (() -> @core.FoldStats)? = None,
) -> ImperativeLanguage[Ast] {
  { full_parse, incremental_parse, to_ast, get_fold_stats }
}
