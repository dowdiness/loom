///|
/// Generated factory: fills derived LanguageSpec fields
/// from annotation metadata.
pub fn make_json_spec(
  parse_root : (@core.ParserContext[Token, SyntaxKind]) -> Unit,
  reuse_size_threshold? : Int = 64,
  incomplete_kind? : SyntaxKind = ErrorToken,
) -> @core.LanguageSpec[Token, SyntaxKind] {
  @core.LanguageSpec::new(
    WhitespaceToken,
    ErrorToken,
    RootNode,
    EOF,
    parse_root~,
    reuse_size_threshold~,
    incomplete_kind~,
    trivia_kinds_spec=[WhitespaceToken],
  )
}
