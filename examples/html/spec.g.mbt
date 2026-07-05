///|
/// Generated factory: fills derived LanguageSpec fields
/// from annotation metadata.
pub fn make_html_spec(
  parse_root : (@core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit,
  reuse_size_threshold? : Int = 64,
  incomplete_kind? : @syntax.SyntaxKind = @syntax.ErrorToken,
) -> @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] {
  @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.RootNode,
    @token.EOF,
    parse_root~,
    reuse_size_threshold~,
    incomplete_kind~,
    trivia_kinds_spec=[@syntax.WhitespaceToken],
  )
}
