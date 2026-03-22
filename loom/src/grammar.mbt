///|
/// Complete grammar description — the four things that vary per language.
///
/// Pass to `new_imperative_parser` or `new_reactive_parser`; the factories
/// handle all infrastructure wiring (TokenBuffer lifecycle, ReuseCursor
/// construction, diagnostic formatting).
///
/// Define one per grammar as a module-level `let`.
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  fold_node : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  on_lex_error : (String) -> Ast
  error_token : T?
  prefix_lexer : @core.PrefixLexer[T]?
  block_reparse_spec : @core.BlockReparseSpec[T, K]?
}

///|
/// Parse a source string to CST + diagnostics.
/// Eliminates boilerplate that every grammar must duplicate:
/// tokenize → build_starts → parse_tokens_indexed.
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind, Ast] Grammar::parse_cst(
  self : Grammar[T, K, Ast],
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[T]]) raise @core.LexError {
  let tokens = (self.tokenize)(source)
  let starts = @core.build_starts(tokens)
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) { starts[i] + tokens[i].len },
    self.spec,
  )
  (cst, diagnostics)
}

///|
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  tokenize~ : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  fold_node~ : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast,
  on_lex_error~ : (String) -> Ast,
  error_token? : T? = None,
  prefix_lexer? : @core.PrefixLexer[T]? = None,
  block_reparse_spec? : @core.BlockReparseSpec[T, K]? = None,
) -> Grammar[T, K, Ast] {
  {
    spec,
    tokenize,
    fold_node,
    on_lex_error,
    error_token,
    prefix_lexer,
    block_reparse_spec,
  }
}
