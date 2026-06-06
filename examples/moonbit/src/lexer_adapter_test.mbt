///|
test "official lexer adapter keeps ASI and EOF" {
  let tokens = tokenize("let x = 1\nlet y = 2\n")
  let summary = tokens.map(fn(info) {
    info.token.to_string() + ":" + info.len.to_string()
  })
  debug_inspect(
    summary,
    content=(
      #|[
      #|  "\"let\"/KeywordOrOperator:3",
      #|  "Whitespace:1",
      #|  "LIDENT/Identifier:1",
      #|  "Whitespace:1",
      #|  "\"=\"/KeywordOrOperator:1",
      #|  "Whitespace:1",
      #|  "INT/Literal:1",
      #|  "SEMI/Semicolon:0",
      #|  "NEWLINE/Trivia:1",
      #|  "\"let\"/KeywordOrOperator:3",
      #|  "Whitespace:1",
      #|  "LIDENT/Identifier:1",
      #|  "Whitespace:1",
      #|  "\"=\"/KeywordOrOperator:1",
      #|  "Whitespace:1",
      #|  "INT/Literal:1",
      #|  "SEMI/Semicolon:0",
      #|  "NEWLINE/Trivia:1",
      #|  "EOF:0",
      #|]
    ),
  )
}

///|
test "official lexer diagnostics are preserved" {
  let result = lex_moonbit("let x = `")
  inspect(result.diagnostics().length(), content="1")
}
