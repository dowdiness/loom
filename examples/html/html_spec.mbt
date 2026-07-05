///|
/// LanguageSpec for simplified HTML grammar.
let html_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = make_html_spec(
  parse_html_root,
  reuse_size_threshold=0,
)
