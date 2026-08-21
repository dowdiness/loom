///|
test "official lexer adapter keeps ASI and EOF" {
  let tokens = tokenize(
    @core.SourceId::SourceId("moonbit-lexer-asi"),
    "let x = 1\nlet y = 2\n",
  )
  let summary = tokens.map(fn(info) {
    info.token.to_string() + ":" + info.len.to_string()
  })
  debug_inspect(
    summary,
    content=(
      #|[
      #|  "\"let\"/LetToken:3",
      #|  "Whitespace:1",
      #|  "LIDENT/LidentToken:1",
      #|  "Whitespace:1",
      #|  "\"=\"/EqualToken:1",
      #|  "Whitespace:1",
      #|  "INT/IntToken:1",
      #|  "SEMI/SemiToken:0",
      #|  "NEWLINE/NewlineToken:1",
      #|  "\"let\"/LetToken:3",
      #|  "Whitespace:1",
      #|  "LIDENT/LidentToken:1",
      #|  "Whitespace:1",
      #|  "\"=\"/EqualToken:1",
      #|  "Whitespace:1",
      #|  "INT/IntToken:1",
      #|  "SEMI/SemiToken:0",
      #|  "NEWLINE/NewlineToken:1",
      #|  "EOF:0",
      #|]
    ),
  )
}

///|
test "official lexer diagnostics are preserved" {
  let result = lex_moonbit(
    @core.SourceId::SourceId("moonbit-lexer-preservation"),
    "let x = `",
  )
  inspect(result.diagnostics().length(), content="1")
}

///|
test "official lexer diagnostics retain supplied source IDs independently of names" {
  let source = "let x = `"
  let source_a = @core.SourceId::SourceId("moonbit-lexer-a")
  let source_b = @core.SourceId::SourceId("moonbit-lexer-b")
  let result_a = lex_moonbit(source_a, source, name="first.mbt")
  let result_b = lex_moonbit(source_b, source, name="second.mbt")
  let diagnostic_a = result_a.diagnostics().items()[0]
  let diagnostic_b = result_b.diagnostics().items()[0]
  inspect(diagnostic_a.origin().name(), content="lexer")
  inspect(diagnostic_a.code().unwrap().value(), content="moonbitlang/lexer")
  guard diagnostic_a.labels()[0].style() is @core.LabelStyle::Primary else {
    fail("expected a primary lexer label")
  }
  inspect(
    diagnostic_a.labels()[0].span().source_id().value(),
    content="moonbit-lexer-a",
  )
  inspect(
    diagnostic_b.labels()[0].span().source_id().value(),
    content="moonbit-lexer-b",
  )
}
