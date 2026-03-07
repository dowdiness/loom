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
  to_ast : (@seam.SyntaxNode) -> Ast
  on_lex_error : (String) -> Ast
  error_token : T?
  prefix_lexer : @core.PrefixLexer[T]?
}

///|
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  tokenize~ : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
  error_token? : T? = None,
  prefix_lexer? : @core.PrefixLexer[T]? = None,
) -> Grammar[T, K, Ast] {
  { spec, tokenize, to_ast, on_lex_error, error_token, prefix_lexer }
}
