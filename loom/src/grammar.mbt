///|
/// Complete grammar description — the four things that vary per language.
///
/// Pass to `new_parser` or `new_imperative_parser`; the factories handle
/// all infrastructure wiring (TokenBuffer lifecycle, ReuseCursor
/// construction, diagnostic formatting).
///
/// Define one per grammar as a module-level `let`.
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  lex : (String) -> @core.LexResult[T]
  fold_node : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  on_lex_error : (String) -> Ast
  incremental_relex_enabled : Bool
  block_reparse_spec : @core.BlockReparseSpec[T, K]?
  mode_relex : @core.ModeRelexState[T]?
}

///|
/// Parse a source string to CST + diagnostics.
/// Eliminates boilerplate that every grammar must duplicate:
/// lex → TokenBuffer → parse_tokens_indexed.
#warnings("-unused_error_type")
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind, Ast] Grammar::parse_cst(
  self : Grammar[T, K, Ast],
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  let buffer = create_buffer(
    source,
    self.lex,
    self.spec.eof_token,
    incremental_relex_enabled=self.incremental_relex_enabled,
    mode_relex=self.mode_relex,
  )
  let (cst, parse_diagnostics, _) = @core.parse_tokens_indexed(
    source,
    buffer.token_count(),
    fn(i) { buffer.get_token(i) },
    fn(i) { buffer.get_start(i) },
    fn(i) { buffer.get_end(i) },
    self.spec,
  )
  let diagnostics = buffer.get_diagnostics()
  diagnostics.extend(parse_diagnostics)
  (cst, diagnostics)
}

///|
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  lex~ : (String) -> @core.LexResult[T],
  fold_node~ : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast,
  on_lex_error~ : (String) -> Ast,
  incremental_relex_enabled? : Bool = true,
  block_reparse_spec? : @core.BlockReparseSpec[T, K]? = None,
  mode_relex? : @core.ModeRelexState[T]? = None,
) -> Grammar[T, K, Ast] {
  {
    spec,
    lex,
    fold_node,
    on_lex_error,
    incremental_relex_enabled,
    block_reparse_spec,
    mode_relex,
  }
}
