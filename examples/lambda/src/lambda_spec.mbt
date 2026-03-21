// Lambda Calculus language specification for the generic parser infrastructure.

///|
/// Map RawKind to the corresponding Token for structural token comparison.
fn syntax_kind_to_token_kind(kind : @seam.RawKind) -> @token.Token? {
  match @syntax.SyntaxKind::from_raw(kind) {
    @syntax.LambdaToken => Some(@token.Lambda)
    @syntax.DotToken => Some(@token.Dot)
    @syntax.LeftParenToken => Some(@token.LeftParen)
    @syntax.RightParenToken => Some(@token.RightParen)
    @syntax.PlusToken => Some(@token.Plus)
    @syntax.MinusToken => Some(@token.Minus)
    @syntax.IfKeyword => Some(@token.If)
    @syntax.ThenKeyword => Some(@token.Then)
    @syntax.ElseKeyword => Some(@token.Else)
    @syntax.LetKeyword => Some(@token.Let)
    @syntax.EqToken => Some(@token.Eq)
    @syntax.NewlineToken => Some(@token.Newline)
    @syntax.LBraceToken => Some(@token.LBrace)
    @syntax.RBraceToken => Some(@token.RBrace)
    @syntax.CommaToken => Some(@token.Comma)
    @syntax.SemicolonToken => Some(@token.Semicolon)
    _ => None
  }
}

///|
/// Shared structural token matcher for the lambda spec.
let cst_token_matches : (@seam.RawKind, String, @token.Token) -> Bool = (
  raw,
  text,
  tok,
) => {
  match @syntax.SyntaxKind::from_raw(raw) {
    IntToken => if tok is Integer(i) { text == i.to_string() } else { false }
    IdentToken => if tok is Identifier(name) { name == text } else { false }
    _ =>
      match syntax_kind_to_token_kind(raw) {
        Some(expected) => expected == tok
        None => false
      }
  }
}

///|
/// LanguageSpec for the lambda grammar (LetDef* Expression?).
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  cst_token_matches~,
  parse_root=parse_lambda_root,
)

///|
/// LanguageSpec with reuse_size_threshold=0 (no skip — all nodes eligible).
let lambda_spec_no_threshold : @core.LanguageSpec[
  @token.Token,
  @syntax.SyntaxKind,
] = @core.LanguageSpec::new(
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  cst_token_matches~,
  parse_root=parse_lambda_root,
  reuse_size_threshold=0,
)
