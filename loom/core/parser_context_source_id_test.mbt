///|
enum SourceKind {
  Whitespace
  Error
  Root
}

///|
impl @seam.ToRawKind for SourceKind with fn to_raw(self) {
  match self {
    Whitespace => @seam.RawKind(0)
    Error => @seam.RawKind(1)
    Root => @seam.RawKind(2)
  }
}

///|
test "ParserContext exposes caller-owned source identity to reusable grammars" {
  let spec : LanguageSpec[Bool, SourceKind] = LanguageSpec::new(
    Whitespace,
    Error,
    Root,
    false,
  )
  let source_a = SourceId::SourceId("grammar-source-a")
  let source_b = SourceId::SourceId("grammar-source-b")
  let context_a = ParserContext::new(source_a, [], "", spec)
  let context_b = ParserContext::new(source_b, [], "", spec)
  inspect(context_a.source_id() == source_a, content="true")
  inspect(context_b.source_id() == source_b, content="true")
  inspect(context_a.source_id() != context_b.source_id(), content="true")
}

///|
test "LanguageSpec owns trivia declaration order independently of caller mutation" {
  let trivia = [Whitespace, Root]
  let spec : LanguageSpec[Bool, SourceKind] = LanguageSpec::new(
    Whitespace,
    Error,
    Root,
    false,
    trivia_kinds_spec=trivia,
  )
  trivia[0] = Error
  assert_eq(spec.trivia_kinds_raw(), [@seam.RawKind(0), @seam.RawKind(2)])
}

///|
test "LanguageSpec exposes detached trivia and named scalar capabilities" {
  let spec : LanguageSpec[Bool, SourceKind] = LanguageSpec::new(
    Whitespace,
    Error,
    Root,
    false,
    reuse_size_threshold=17,
    trivia_kinds_spec=[Whitespace, Root],
  )
  let trivia = spec.trivia_kinds_raw()
  trivia[0] = @seam.RawKind(99)
  assert_eq(spec.trivia_kinds_raw(), [@seam.RawKind(0), @seam.RawKind(2)])
  inspect(spec.eof_token(), content="false")
  inspect(spec.reuse_size_threshold(), content="17")
}
