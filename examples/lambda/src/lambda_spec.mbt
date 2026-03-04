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
    @syntax.InKeyword => Some(@token.In)
    @syntax.EqToken => Some(@token.Eq)
    _ => None
  }
}

///|
/// The LanguageSpec for Lambda Calculus.
/// Created once at module init, reused across all parses (zero per-parse allocation).
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  fn(t) { t == @token.EOF },
  fn(t) { t == @token.Whitespace },
  fn(a, b) { a == b },
  @token.print_token,
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  cst_token_matches=(raw, text, tok) => {
    match @syntax.SyntaxKind::from_raw(raw) {
      IntToken => if tok is Integer(i) { text == i.to_string() } else { false }
      IdentToken => if tok is Identifier(name) { name == text } else { false }
      _ =>
        match syntax_kind_to_token_kind(raw) {
          Some(expected) => expected == tok
          None => false
        }
    }
  },
  parse_root=parse_lambda_root,
)
