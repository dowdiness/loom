///|
test "ParserContext exposes caller-owned source identity to reusable grammars" {
  let spec : LanguageSpec[Bool, Int] = LanguageSpec::new(0, 1, 2, false)
  let source_a = SourceId::SourceId("grammar-source-a")
  let source_b = SourceId::SourceId("grammar-source-b")
  let context_a = ParserContext::new(source_a, [], "", spec)
  let context_b = ParserContext::new(source_b, [], "", spec)
  inspect(context_a.source_id() == source_a, content="true")
  inspect(context_b.source_id() == source_b, content="true")
  inspect(context_a.source_id() != context_b.source_id(), content="true")
}
