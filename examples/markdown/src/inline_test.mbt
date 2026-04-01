///|
test "inline: bold" {
  let block = parse("**bold**\n")
  inspect(block, content="Document([Paragraph([Bold([Text(\"bold\")])])])")
}

///|
test "inline: italic" {
  let block = parse("*italic*\n")
  inspect(block, content="Document([Paragraph([Italic([Text(\"italic\")])])])")
}

///|
test "inline: inline code" {
  let block = parse("`code`\n")
  inspect(block, content="Document([Paragraph([InlineCode(\"code\")])])")
}

///|
test "inline: link" {
  let block = parse("[click](http://example.com)\n")
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"click\")], \"http://example.com\")])])",
  )
}

///|
test "inline: bold inside paragraph" {
  let block = parse("Hello **world** end\n")
  inspect(
    block,
    content="Document([Paragraph([Text(\"Hello \"), Bold([Text(\"world\")]), Text(\" end\")])])",
  )
}

///|
test "inline: bold in heading" {
  let block = parse("# **Bold** title\n")
  inspect(
    block,
    content="Document([Heading(1, [Bold([Text(\"Bold\")]), Text(\" title\")])])",
  )
}
