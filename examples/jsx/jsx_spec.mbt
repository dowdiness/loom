///|
/// LanguageSpec for the simplified JSX grammar.
let jsx_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = make_jsx_spec(
  parse_jsx_root,
  reuse_size_threshold=0,
)
