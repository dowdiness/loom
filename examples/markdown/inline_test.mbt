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
test "inline: italic can contain bold" {
  let block = parse("*foo **bar** baz*\n")
  inspect(
    block,
    content="Document([Paragraph([Italic([Text(\"foo \"), Bold([Text(\"bar\")]), Text(\" baz\")])])])",
  )
}

///|
test "inline: ordered marker can remain paragraph text inside multiline emphasis" {
  let block = parse("*foo\n2. bar*\n")
  inspect(
    block,
    content="Document([Paragraph([Italic([Text(\"foo\"), Text(\"2. \"), Text(\"bar\")])])])",
  )
}

///|
test "inline: multiline emphasis stops at ordered list item boundary" {
  let block = parse("1. *foo\n2. bar*\n")
  inspect(
    block,
    content=(
      #|Document(
      #|  [
      #|    OrderedList(
      #|      [
      #|        OrderedListItem(
      #|          [Error("*"), Text("foo")],
      #|          Some({ start: 1, delimiter: Period }),
      #|        ),
      #|        OrderedListItem(
      #|          [Text("bar"), Error("*")],
      #|          Some({ start: 2, delimiter: Period }),
      #|        ),
      #|      ],
      #|      Some({ start: 1, delimiter: Period }),
      #|    ),
      #|  ],
      #|)
    ),
  )
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
test "inline: link destination preserves balanced parentheses" {
  let block = parse("[wiki](page_(C).html)\n")
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"wiki\")], \"page_(C).html\")])])",
  )
}

///|
test "inline: link destination preserves delimiter characters" {
  let block = parse("[api](docs/*items*`v1`)\n")
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"api\")], \"docs/*items*`v1`\")])])",
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
