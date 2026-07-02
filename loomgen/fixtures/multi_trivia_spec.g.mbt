///|
/// Generated factory: fills derived LanguageSpec fields
/// from annotation metadata.
pub fn make_multiTrivia_spec(
  parse_root : (@core.ParserContext[@token.MultiTriviaToken, @syntax.MultiTriviaSyntaxKind]) -> Unit,
  reuse_size_threshold? : Int = 64,
  incomplete_kind? : @syntax.MultiTriviaSyntaxKind = @syntax.ErrorToken,
) -> @core.LanguageSpec[@token.MultiTriviaToken, @syntax.MultiTriviaSyntaxKind] {
  @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root~,
    reuse_size_threshold~,
    incomplete_kind~,
    trivia_kinds_spec=[@syntax.WhitespaceToken, @syntax.CommentToken],
  )
}

///|
/// Returns true for all trivia syntax kinds in this language.
/// Generated from all #loom.trivia-annotated token variants.
pub fn is_multiTrivia_trivia_kind(kind : @syntax.MultiTriviaSyntaxKind) -> Bool {
  match kind {
    @syntax.WhitespaceToken | @syntax.CommentToken => true
    _ => false
  }
}
