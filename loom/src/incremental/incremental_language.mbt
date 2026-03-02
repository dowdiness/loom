///|
/// Outcome of a parse attempt by IncrementalLanguage.
/// Tree carries the new syntax tree and the node reuse count (0 for full parses).
/// LexError carries the error message for on_lex_error dispatch.
pub(all) enum ParseOutcome {
  Tree(@seam.SyntaxNode, Int)
  LexError(String)
}

///|
/// Token-erased vtable for incremental language integration.
///
/// Analogous to `@pipeline.Language[Ast]`: the token type is erased into
/// closures at call site, keeping `IncrementalParser[Ast]` generic.
///
/// `full_parse` — initial (non-incremental) parse. Returns Tree(syntax, 0)
///   or LexError(msg). The closure captures and manages TokenBuffer state.
///
/// `incremental_parse` — edit-triggered reparse. Receives the old SyntaxNode
///   so the closure can call SyntaxNode::cst_node() for the reuse cursor.
///   Returns Tree(new_syntax, reuse_count) or LexError(msg). The closure
///   captures and updates TokenBuffer and last_diagnostics state.
///
/// `to_ast` — convert a syntax tree to Ast.
///
/// `on_lex_error` — build an error Ast from a lex-error message.
pub struct IncrementalLanguage[Ast] {
  priv full_parse : (String) -> ParseOutcome
  priv incremental_parse : (String, @seam.SyntaxNode, @core.Edit) -> ParseOutcome
  priv to_ast : (@seam.SyntaxNode) -> Ast
  priv on_lex_error : (String) -> Ast
}

///|
/// Constructor for IncrementalLanguage vtable.
pub fn[Ast] IncrementalLanguage::new(
  full_parse~ : (String) -> ParseOutcome,
  incremental_parse~ : (String, @seam.SyntaxNode, @core.Edit) -> ParseOutcome,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
) -> IncrementalLanguage[Ast] {
  { full_parse, incremental_parse, to_ast, on_lex_error }
}
