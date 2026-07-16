///|
test "error recovery: unclosed bold" {
  inspect(
    parse("**unclosed\n"),
    content="Document([Paragraph([Error(\"**\"), Text(\"unclosed\")])])",
  )
}

///|
test "error recovery: unclosed link" {
  inspect(
    parse("[unclosed\n"),
    content="Document([Paragraph([Error(\"[\"), Text(\"unclosed\")])])",
  )
}

///|
test "error recovery: unclosed code fence" {
  inspect(
    parse("```\ncode without close\n"),
    content="Document([CodeBlock(\"\", \"code without close\")])",
  )
}

///|
test "error recovery: unmatched code-span run stays literal" {
  inspect(
    parse("``unclosed *em*\n"),
    content="Document([Paragraph([Text(\"``\"), Text(\"unclosed \"), Italic([Text(\"em\")])])])",
  )
}
