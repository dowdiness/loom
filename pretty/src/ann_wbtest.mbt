///|
test "SyntaxCategory values" {
  inspect(Keyword, content="Keyword")
  inspect(Identifier, content="Identifier")
  inspect(Number, content="Number")
  inspect(Error, content="Error")
}

///|
test "Span construction" {
  let span : Span = { start: 0, end: 5 }
  inspect(span.start, content="0")
  inspect(span.end, content="5")
}
