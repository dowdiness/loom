///|
test "ParserContext source_view returns zero-copy bounded ranges" {
  let source_id = SourceId("parser-context-source-view")
  let source = "zero-width 😈 range"
  let tokens : Array[TokenInfo[TestTok]] = [
    TokenInfo::new(TestTok::Num(0), source.length()),
  ]
  let spec : LanguageSpec[TestTok, TestKind] = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
  )
  let ctx = ParserContext::new(source_id, tokens, source, spec)
  assert_eq(ctx.source_view(start=0, end=4), "zero")
  assert_eq(ctx.source_view(start=4, end=4), "")
  assert_eq(ctx.source_view(start=5, end=source.length()), "width 😈 range")
  assert_eq(ctx.source_view(start=-1, end=2), "")
  assert_eq(ctx.source_view(start=2, end=source.length() + 1), "")
}
