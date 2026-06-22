// Lambda Calculus language specification for the generic parser infrastructure.

///|
/// LanguageSpec for the lambda grammar (LetDef* Expression?).
/// reuse_size_threshold=0: all nodes eligible for reuse. LetDef uses ctx.node()
/// so individual definitions can be reused during incremental parsing.
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  parse_root=parse_lambda_root,
  reuse_size_threshold=0,
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
  parse_root=parse_lambda_root,
  reuse_size_threshold=0,
)
