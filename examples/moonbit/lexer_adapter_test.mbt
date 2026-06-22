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
  let result = lex_moonbit("let x = `")
  inspect(result.diagnostics().length(), content="1")
}
