///|
/// Complete grammar description — the things that vary per language.
///
/// Pass to `new_parser` or `new_imperative_parser`; the factories handle
/// all infrastructure wiring (TokenBuffer lifecycle, ReuseCursor
/// construction, diagnostic formatting).
///
/// Define one per grammar as a module-level `let` when you want Loom to fold
/// the CST into an AST. If a consumer only needs reactive source, CST, and
/// diagnostics, use `SyntaxGrammar` instead so no placeholder AST is needed.
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  lex : (String) -> @core.LexResult[T]
  fold_node : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  incremental_relex_enabled : Bool
  block_reparse_spec : @core.BlockReparseSpec[T, K]?
  mode_relex : @core.ModeRelexState[T]?
}

///|
/// Syntax-only grammar description.
///
/// Use this when a language integration wants Loom's incremental CST reuse,
/// structured diagnostics, and reactive `SyntaxParser` views without providing
/// an AST fold or requiring the eventual AST type to implement `Eq`.
pub struct SyntaxGrammar[T, K] {
  spec : @core.LanguageSpec[T, K]
  lex : (String) -> @core.LexResult[T]
  incremental_relex_enabled : Bool
  block_reparse_spec : @core.BlockReparseSpec[T, K]?
  mode_relex : @core.ModeRelexState[T]?
}

///|
/// Shared one-shot CST parse implementation for `Grammar` and `SyntaxGrammar`.
#warnings("-unused_error_type")
fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] parse_cst_from_parts(
  source : String,
  spec : @core.LanguageSpec[T, K],
  lex : (String) -> @core.LexResult[T],
  incremental_relex_enabled : Bool,
  mode_relex : @core.ModeRelexState[T]?,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  let buffer = create_buffer(
    source,
    lex,
    spec.eof_token,
    incremental_relex_enabled~,
    mode_relex~,
  )
  let (cst, parse_diagnostics, _) = @core.parse_tokens_indexed(
    source,
    buffer.token_count(),
    fn(i) { buffer.get_token(i) },
    fn(i) { buffer.get_start(i) },
    fn(i) { buffer.get_end(i) },
    spec,
  )
  let diagnostics = buffer.get_diagnostics()
  diagnostics.extend(parse_diagnostics)
  (cst, diagnostics)
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
  parse_cst_from_parts(
    source,
    self.spec,
    self.lex,
    self.incremental_relex_enabled,
    self.mode_relex,
  )
}

///|
/// Parse a source string to CST + diagnostics without an AST fold.
#warnings("-unused_error_type")
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] SyntaxGrammar::parse_cst(
  self : SyntaxGrammar[T, K],
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  parse_cst_from_parts(
    source,
    self.spec,
    self.lex,
    self.incremental_relex_enabled,
    self.mode_relex,
  )
}

///|
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  lex~ : (String) -> @core.LexResult[T],
  fold_node~ : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast,
  incremental_relex_enabled? : Bool = true,
  block_reparse_spec? : @core.BlockReparseSpec[T, K]? = None,
  mode_relex? : @core.ModeRelexState[T]? = None,
) -> Grammar[T, K, Ast] {
  {
    spec,
    lex,
    fold_node,
    incremental_relex_enabled,
    block_reparse_spec,
    mode_relex,
  }
}

///|
pub fn[T, K] SyntaxGrammar::new(
  spec~ : @core.LanguageSpec[T, K],
  lex~ : (String) -> @core.LexResult[T],
  incremental_relex_enabled? : Bool = true,
  block_reparse_spec? : @core.BlockReparseSpec[T, K]? = None,
  mode_relex? : @core.ModeRelexState[T]? = None,
) -> SyntaxGrammar[T, K] {
  { spec, lex, incremental_relex_enabled, block_reparse_spec, mode_relex }
}

///|
/// Project an AST grammar to its syntax-only facade.
///
/// The returned grammar reuses the same lexer, language spec, and reparse
/// configuration but intentionally drops `fold_node`. This is useful when the
/// AST type is not `Eq`, or when a consumer only needs CST/diagnostics.
pub fn[T, K, Ast] Grammar::to_syntax_grammar(
  self : Grammar[T, K, Ast],
) -> SyntaxGrammar[T, K] {
  {
    spec: self.spec,
    lex: self.lex,
    incremental_relex_enabled: self.incremental_relex_enabled,
    block_reparse_spec: self.block_reparse_spec,
    mode_relex: self.mode_relex,
  }
}
